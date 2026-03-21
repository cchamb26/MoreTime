import crypto from 'node:crypto';
import { prisma } from '../utils/db.js';
import { chatCompletion } from './ai.js';

interface ChatResult {
  sessionId: string;
  response: string;
  action?: {
    type: 'task_created' | 'schedule_query' | 'reschedule';
    data?: unknown;
  };
}

async function buildSystemContext(userId: string): Promise<string> {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const tomorrow = new Date(today);
  tomorrow.setDate(tomorrow.getDate() + 1);

  const [tasks, todayBlocks, user] = await Promise.all([
    prisma.task.findMany({
      where: { userId, status: { not: 'completed' } },
      include: { course: { select: { name: true } } },
      orderBy: { dueDate: 'asc' },
      take: 30,
    }),
    prisma.scheduleBlock.findMany({
      where: {
        userId,
        date: { gte: today, lt: tomorrow },
      },
      include: { task: { select: { title: true } } },
      orderBy: { startTime: 'asc' },
    }),
    prisma.user.findUnique({
      where: { id: userId },
      select: { name: true, timezone: true },
    }),
  ]);

  const taskList = tasks
    .map((t) => {
      const due = t.dueDate ? t.dueDate.toISOString().slice(0, 10) : 'No deadline';
      return `- ${t.title} (${t.course?.name ?? 'General'}) — Due: ${due}, Priority: ${t.priority}, Est: ${t.estimatedHours}h, Status: ${t.status}`;
    })
    .join('\n');

  const scheduleList = todayBlocks
    .map((b) => `- ${b.startTime}-${b.endTime}: ${b.task?.title ?? b.label ?? 'Block'}${b.isLocked ? ' [LOCKED]' : ''}`)
    .join('\n');

  return `You are MoreTime, an AI study assistant helping ${user?.name ?? 'a student'} manage their academic schedule.
Today is ${today.toISOString().slice(0, 10)} (${user?.timezone ?? 'America/New_York'}).

Current tasks:
${taskList || '(No pending tasks)'}

Today's schedule:
${scheduleList || '(Nothing scheduled today)'}

You can help the student:
1. Create tasks: When they describe an assignment, extract the details and respond with a JSON action block.
2. Query schedule: Tell them what they should work on today/this week.
3. Reschedule: When they ask to move blocks, describe the change.
4. General study advice and motivation.

When the user describes a new task, include this in your response:
<action type="task_created">{"title": "...", "courseId": null, "dueDate": "YYYY-MM-DDTHH:MM:SSZ", "estimatedHours": N, "priority": N}</action>

When the user asks about their schedule, just respond naturally with the relevant information.
Keep responses concise and helpful.`;
}

export async function handleChatMessage(
  userId: string,
  message: string,
  sessionId?: string,
): Promise<ChatResult> {
  const sid = sessionId || crypto.randomUUID();

  // Save user message
  await prisma.chatMessage.create({
    data: { userId, role: 'user', content: message, sessionId: sid },
  });

  // Get conversation history (last 20 messages)
  const history = await prisma.chatMessage.findMany({
    where: { userId, sessionId: sid },
    orderBy: { timestamp: 'asc' },
    take: 20,
  });

  // Build messages for AI
  const systemContent = await buildSystemContext(userId);
  const messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }> = [
    { role: 'system', content: systemContent },
    ...history.map((m) => ({
      role: m.role as 'user' | 'assistant',
      content: m.content,
    })),
  ];

  const response = await chatCompletion(messages);

  // Save assistant response
  await prisma.chatMessage.create({
    data: { userId, role: 'assistant', content: response, sessionId: sid },
  });

  // Parse any action from response
  let action: ChatResult['action'];
  const actionMatch = response.match(/<action type="(\w+)">(.+?)<\/action>/s);
  if (actionMatch) {
    const type = actionMatch[1] as 'task_created' | 'schedule_query' | 'reschedule';
    try {
      const data = JSON.parse(actionMatch[2]);

      // Auto-create task if action type is task_created
      if (type === 'task_created' && data.title) {
        const task = await prisma.task.create({
          data: {
            userId,
            title: data.title,
            courseId: data.courseId || null,
            dueDate: data.dueDate ? new Date(data.dueDate) : null,
            estimatedHours: data.estimatedHours || 2,
            priority: data.priority || 2,
            description: data.description || '',
          },
        });
        action = { type, data: task };
      } else {
        action = { type, data };
      }
    } catch {
      // Action parsing failed, just return response as-is
    }
  }

  // Clean action tags from response text
  const cleanResponse = response.replace(/<action[^>]*>.*?<\/action>/gs, '').trim();

  return { sessionId: sid, response: cleanResponse, action };
}
