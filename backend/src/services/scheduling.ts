import { getSupabase } from '../utils/supabase.js';
import { generateScheduleBlocks, ScheduleBlockInput, SemesterEvent } from './ai.js';
import { ValidationError } from '../utils/errors.js';
import { toCamel } from '../utils/transform.js';

// MARK: - Semester Heat Map

export interface SemesterWeek {
  weekStart: string;
  weekEnd: string;
  totalEstimatedHours: number;
  intensity: 'low' | 'medium' | 'high' | 'critical';
  events: SemesterEvent[];
}

export interface SemesterPlanResult {
  weeks: SemesterWeek[];
  crunchWeeks: string[];
  totalEvents: number;
  semesterStart: string;
  semesterEnd: string;
}

function getIntensity(hours: number): 'low' | 'medium' | 'high' | 'critical' {
  if (hours <= 5) return 'low';
  if (hours <= 10) return 'medium';
  if (hours <= 15) return 'high';
  return 'critical';
}

export function groupEventsIntoWeeks(
  events: SemesterEvent[],
  semesterStart: string,
  semesterEnd: string,
): SemesterPlanResult {
  const weeks: SemesterWeek[] = [];
  const current = new Date(semesterStart);

  // Align to Monday
  const day = current.getDay();
  const diff = day === 0 ? 1 : day === 1 ? 0 : 8 - day;
  current.setDate(current.getDate() + diff);

  const end = new Date(semesterEnd);

  while (current <= end) {
    const weekStart = current.toISOString().split('T')[0];
    const weekEndDate = new Date(current);
    weekEndDate.setDate(weekEndDate.getDate() + 6);
    const weekEnd = weekEndDate.toISOString().split('T')[0];

    const weekEvents = events.filter((e) => e.dueDate >= weekStart && e.dueDate <= weekEnd);
    const totalHours = weekEvents.reduce((sum, e) => sum + e.estimatedHours, 0);

    weeks.push({
      weekStart,
      weekEnd,
      totalEstimatedHours: Math.round(totalHours * 10) / 10,
      intensity: getIntensity(totalHours),
      events: weekEvents,
    });

    current.setDate(current.getDate() + 7);
  }

  const crunchWeeks = weeks
    .filter((w) => w.intensity === 'critical' || w.intensity === 'high')
    .map((w) => w.weekStart);

  return {
    weeks,
    crunchWeeks,
    totalEvents: events.length,
    semesterStart,
    semesterEnd,
  };
}

interface ScheduleResult {
  blocksCreated: number;
  blocksRemoved: number;
  blocks: Array<{
    id: string;
    taskId: string | null;
    date: string;
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
  lockedBlocks: Array<{ date: string; start_time: string; end_time: string }>,
  taskIds: Set<string>,
): { valid: ScheduleBlockInput[]; warnings: string[] } {
  const warnings: string[] = [];
  const valid: ScheduleBlockInput[] = [];

  for (const block of generated) {
    if (!taskIds.has(block.taskId)) {
      warnings.push(`Skipped block for unknown task ${block.taskId}`);
      continue;
    }

    if (!/^\d{2}:\d{2}$/.test(block.startTime) || !/^\d{2}:\d{2}$/.test(block.endTime)) {
      warnings.push(`Skipped block with invalid time format: ${block.startTime}-${block.endTime}`);
      continue;
    }

    if (timeToMinutes(block.startTime) >= timeToMinutes(block.endTime)) {
      warnings.push(`Skipped block where start >= end: ${block.startTime}-${block.endTime}`);
      continue;
    }

    const blockDate = block.date;
    const conflictsLocked = lockedBlocks.some(
      (locked) =>
        locked.date === blockDate &&
        blocksOverlap(block, { startTime: locked.start_time, endTime: locked.end_time }),
    );
    if (conflictsLocked) {
      warnings.push(`Skipped block on ${blockDate} ${block.startTime}-${block.endTime} — conflicts with locked block`);
      continue;
    }

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
  const supabase = getSupabase();

  const { data: user } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();

  if (!user) throw new ValidationError('User not found');

  const { data: tasks } = await supabase
    .from('tasks')
    .select('*, courses:course_id(name)')
    .eq('user_id', userId)
    .neq('status', 'completed');

  if (!tasks || tasks.length === 0) {
    return { blocksCreated: 0, blocksRemoved: 0, blocks: [], warnings: ['No pending tasks to schedule'] };
  }

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // Auto-escalate priority of overdue tasks
  for (const task of tasks) {
    if (task.due_date && new Date(task.due_date as string) < today && (task.priority as number) > 1) {
      const newPriority = 1;
      await supabase
        .from('tasks')
        .update({ priority: newPriority })
        .eq('id', task.id);
      task.priority = newPriority;
    }
  }
  const todayStr = today.toISOString().slice(0, 10);
  const maxDate = new Date(today);
  maxDate.setDate(maxDate.getDate() + 30);

  const furthestDeadline = tasks.reduce((max: Date, t: Record<string, unknown>) => {
    if (t.due_date) {
      const d = new Date(t.due_date as string);
      if (d > max) return d;
    }
    return max;
  }, new Date(today.getTime() + 14 * 24 * 60 * 60 * 1000));

  const endDate = furthestDeadline < maxDate ? furthestDeadline : maxDate;
  const endDateStr = endDate.toISOString().slice(0, 10);

  const { data: lockedBlocks } = await supabase
    .from('schedule_blocks')
    .select('date, start_time, end_time, label')
    .eq('user_id', userId)
    .eq('is_locked', true)
    .gte('date', todayStr)
    .lte('date', endDateStr);

  const preferences = (user.preferences as Record<string, unknown>) || {};

  const taskDescriptions = tasks.map((t: Record<string, unknown>) => ({
    taskId: t.id,
    title: t.title,
    description: t.description || '',
    course: (t.courses as Record<string, unknown> | null)?.name ?? 'General',
    dueDate: t.due_date ? (t.due_date as string).slice(0, 10) : 'No deadline',
    priority: t.priority,
    estimatedHours: t.estimated_hours,
    hoursRemaining: t.estimated_hours,
  }));

  const lockedDescriptions = (lockedBlocks ?? []).map((b: Record<string, unknown>) => ({
    date: b.date,
    startTime: b.start_time,
    endTime: b.end_time,
    label: b.label ?? 'Locked',
  }));

  const prompt = `Today is ${todayStr}. Schedule through ${endDateStr}.

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

  let allWarnings: string[] = [];
  let validBlocks: ScheduleBlockInput[] = [];
  const taskIds = new Set(tasks.map((t: Record<string, unknown>) => t.id as string));

  for (let attempt = 0; attempt < 3; attempt++) {
    const retryContext =
      attempt > 0
        ? `\n\nPrevious attempt had issues: ${allWarnings.join('; ')}. Please fix these issues.`
        : '';

    const generated = await generateScheduleBlocks(prompt + retryContext);
    const { valid, warnings } = validateBlocks(generated, lockedBlocks ?? [], taskIds);

    if (valid.length > 0 || attempt === 2) {
      validBlocks = valid;
      allWarnings = warnings;
      break;
    }

    allWarnings = warnings;
  }

  // Remove existing non-locked blocks in the date range
  const { count: removedCount } = await supabase
    .from('schedule_blocks')
    .delete({ count: 'exact' })
    .eq('user_id', userId)
    .eq('is_locked', false)
    .gte('date', todayStr)
    .lte('date', endDateStr);

  // Insert new blocks
  const created = [];
  for (const block of validBlocks) {
    const { data: record } = await supabase
      .from('schedule_blocks')
      .insert({
        user_id: userId,
        task_id: block.taskId,
        date: block.date,
        start_time: block.startTime,
        end_time: block.endTime,
        is_locked: false,
        label: block.label || null,
      })
      .select()
      .single();

    if (record) created.push(toCamel(record));
  }

  return {
    blocksCreated: created.length,
    blocksRemoved: removedCount ?? 0,
    blocks: created as ScheduleResult['blocks'],
    warnings: allWarnings,
  };
}
