import { prisma } from '../utils/db.js';
import { generateScheduleBlocks, ScheduleBlockInput } from './ai.js';
import { ValidationError } from '../utils/errors.js';

interface ScheduleResult {
  blocksCreated: number;
  blocksRemoved: number;
  blocks: Array<{
    id: string;
    taskId: string | null;
    date: Date;
    startTime: string;
    endTime: string;
  }>;
  warnings: string[];
}

function timeToMinutes(time: string): number {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
}

function blocksOverlap(
  a: { startTime: string; endTime: string },
  b: { startTime: string; endTime: string },
): boolean {
  const aStart = timeToMinutes(a.startTime);
  const aEnd = timeToMinutes(a.endTime);
  const bStart = timeToMinutes(b.startTime);
  const bEnd = timeToMinutes(b.endTime);
  return aStart < bEnd && bStart < aEnd;
}

function validateBlocks(
  generated: ScheduleBlockInput[],
  lockedBlocks: Array<{ date: Date; startTime: string; endTime: string }>,
  taskIds: Set<string>,
): { valid: ScheduleBlockInput[]; warnings: string[] } {
  const warnings: string[] = [];
  const valid: ScheduleBlockInput[] = [];

  for (const block of generated) {
    // Check task exists
    if (!taskIds.has(block.taskId)) {
      warnings.push(`Skipped block for unknown task ${block.taskId}`);
      continue;
    }

    // Check time format
    if (!/^\d{2}:\d{2}$/.test(block.startTime) || !/^\d{2}:\d{2}$/.test(block.endTime)) {
      warnings.push(`Skipped block with invalid time format: ${block.startTime}-${block.endTime}`);
      continue;
    }

    // Check start < end
    if (timeToMinutes(block.startTime) >= timeToMinutes(block.endTime)) {
      warnings.push(`Skipped block where start >= end: ${block.startTime}-${block.endTime}`);
      continue;
    }

    // Check against locked blocks on same date
    const blockDate = block.date;
    const conflictsLocked = lockedBlocks.some(
      (locked) =>
        locked.date.toISOString().slice(0, 10) === blockDate &&
        blocksOverlap(block, locked),
    );
    if (conflictsLocked) {
      warnings.push(`Skipped block on ${blockDate} ${block.startTime}-${block.endTime} — conflicts with locked block`);
      continue;
    }

    // Check against already-accepted blocks
    const conflictsAccepted = valid.some(
      (v) => v.date === blockDate && blocksOverlap(block, v),
    );
    if (conflictsAccepted) {
      warnings.push(`Skipped overlapping block on ${blockDate} ${block.startTime}-${block.endTime}`);
      continue;
    }

    valid.push(block);
  }

  return { valid, warnings };
}

export async function generateSchedule(userId: string): Promise<ScheduleResult> {
  // Gather user data
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new ValidationError('User not found');

  const tasks = await prisma.task.findMany({
    where: {
      userId,
      status: { not: 'completed' },
    },
    include: { course: { select: { name: true } } },
  });

  if (tasks.length === 0) {
    return { blocksCreated: 0, blocksRemoved: 0, blocks: [], warnings: ['No pending tasks to schedule'] };
  }

  // Get date range: today to furthest deadline (or 14 days out)
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const maxDate = new Date(today);
  maxDate.setDate(maxDate.getDate() + 30);

  const furthestDeadline = tasks.reduce((max, t) => {
    if (t.dueDate && t.dueDate > max) return t.dueDate;
    return max;
  }, new Date(today.getTime() + 14 * 24 * 60 * 60 * 1000));

  const endDate = furthestDeadline < maxDate ? furthestDeadline : maxDate;

  // Get locked blocks in range
  const lockedBlocks = await prisma.scheduleBlock.findMany({
    where: {
      userId,
      isLocked: true,
      date: { gte: today, lte: endDate },
    },
  });

  const preferences = (user.preferences as Record<string, unknown>) || {};

  // Build prompt
  const taskDescriptions = tasks.map((t) => ({
    taskId: t.id,
    title: t.title,
    course: t.course?.name ?? 'General',
    dueDate: t.dueDate?.toISOString().slice(0, 10) ?? 'No deadline',
    priority: t.priority,
    estimatedHours: t.estimatedHours,
    hoursRemaining: t.estimatedHours, // Could subtract already-scheduled hours
  }));

  const lockedDescriptions = lockedBlocks.map((b) => ({
    date: b.date.toISOString().slice(0, 10),
    startTime: b.startTime,
    endTime: b.endTime,
    label: b.label ?? 'Locked',
  }));

  const prompt = `Today is ${today.toISOString().slice(0, 10)}. Schedule through ${endDate.toISOString().slice(0, 10)}.

Student preferences:
- Preferred study hours: ${preferences.preferredStartTime ?? '09:00'} to ${preferences.preferredEndTime ?? '22:00'}
- Max hours per day: ${preferences.maxHoursPerDay ?? 8}
- Preferred break duration: ${preferences.breakDuration ?? 15} minutes
- Timezone: ${user.timezone}

Tasks to schedule:
${JSON.stringify(taskDescriptions, null, 2)}

Locked blocks (DO NOT schedule over these):
${JSON.stringify(lockedDescriptions, null, 2)}

Generate an optimal study schedule. Spread work evenly, prioritize high-priority and approaching-deadline tasks.`;

  // Generate with up to 2 retries
  let allWarnings: string[] = [];
  let validBlocks: ScheduleBlockInput[] = [];
  const taskIds = new Set(tasks.map((t) => t.id));

  for (let attempt = 0; attempt < 3; attempt++) {
    const retryContext =
      attempt > 0
        ? `\n\nPrevious attempt had issues: ${allWarnings.join('; ')}. Please fix these issues.`
        : '';

    const generated = await generateScheduleBlocks(prompt + retryContext);
    const { valid, warnings } = validateBlocks(generated, lockedBlocks, taskIds);

    if (valid.length > 0 || attempt === 2) {
      validBlocks = valid;
      allWarnings = warnings;
      break;
    }

    allWarnings = warnings;
  }

  // Remove existing non-locked blocks in the date range
  const deleted = await prisma.scheduleBlock.deleteMany({
    where: {
      userId,
      isLocked: false,
      date: { gte: today, lte: endDate },
    },
  });

  // Insert new blocks
  const created = [];
  for (const block of validBlocks) {
    const record = await prisma.scheduleBlock.create({
      data: {
        userId,
        taskId: block.taskId,
        date: new Date(block.date),
        startTime: block.startTime,
        endTime: block.endTime,
        isLocked: false,
      },
    });
    created.push(record);
  }

  return {
    blocksCreated: created.length,
    blocksRemoved: deleted.count,
    blocks: created,
    warnings: allWarnings,
  };
}
