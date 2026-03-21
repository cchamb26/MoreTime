import crypto from 'node:crypto';
import { getSupabase } from '../utils/supabase.js';
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
  const supabase = getSupabase();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const todayStr = today.toISOString().slice(0, 10);
  const tomorrowStr = new Date(today.getTime() + 86400000).toISOString().slice(0, 10);

  const [tasksResult, blocksResult, userResult] = await Promise.all([
    supabase
      .from('tasks')
      .select('*, courses:course_id(name)')
      .eq('user_id', userId)
      .neq('status', 'completed')
      .order('due_date')
      .limit(30),
    supabase
      .from('schedule_blocks')
      .select('*, tasks:task_id(title)')
      .eq('user_id', userId)
      .gte('date', todayStr)
      .lt('date', tomorrowStr)
      .order('start_time'),
    supabase
      .from('profiles')
      .select('name, timezone')
      .eq('id', userId)
      .single(),
  ]);

  const tasks = tasksResult.data ?? [];
  const todayBlocks = blocksResult.data ?? [];
  const user = userResult.data;

  const taskList = tasks
    .map((t: Record<string, unknown>) => {
      const due = t.due_date ? (t.due_date as string).slice(0, 10) : 'No deadline';
      const courseName = (t.courses as Record<string, unknown> | null)?.name ?? 'General';
      return `- ${t.title} (${courseName}) — Due: ${due}, Priority: ${t.priority}, Est: ${t.estimated_hours}h, Status: ${t.status}`;
    })
    .join('\n');

  const scheduleList = todayBlocks
    .map((b: Record<string, unknown>) => {
      const taskTitle = (b.tasks as Record<string, unknown> | null)?.title ?? b.label ?? 'Block';
      return `- ${b.start_time}-${b.end_time}: ${taskTitle}${b.is_locked ? ' [LOCKED]' : ''}`;
    })
    .join('\n');

  return `You are MoreTime, an AI study assistant helping ${user?.name ?? 'a student'} manage their academic schedule.
Today is ${todayStr} (${user?.timezone ?? 'America/New_York'}).

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
  const supabase = getSupabase();
  const sid = sessionId || crypto.randomUUID();

  // Save user message
  await supabase.from('chat_messages').insert({
    user_id: userId,
    role: 'user',
    content: message,
    session_id: sid,
  });

  // Get conversation history (last 20 messages)
  const { data: history } = await supabase
    .from('chat_messages')
    .select('role, content')
    .eq('user_id', userId)
    .eq('session_id', sid)
    .order('timestamp')
    .limit(20);

  // Build messages for AI
  const systemContent = await buildSystemContext(userId);
  const messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }> = [
    { role: 'system', content: systemContent },
    ...(history ?? []).map((m: Record<string, unknown>) => ({
      role: m.role as 'user' | 'assistant',
      content: m.content as string,
    })),
  ];

  const response = await chatCompletion(messages);

  // Save assistant response
  await supabase.from('chat_messages').insert({
    user_id: userId,
    role: 'assistant',
    content: response,
    session_id: sid,
  });

  // Parse any action from response
  let action: ChatResult['action'];
  const actionMatch = response.match(/<action type="(\w+)">(.+?)<\/action>/s);
  if (actionMatch) {
    const type = actionMatch[1] as 'task_created' | 'schedule_query' | 'reschedule';
    try {
      const data = JSON.parse(actionMatch[2]);

      if (type === 'task_created' && data.title) {
        const { data: task } = await supabase
          .from('tasks')
          .insert({
            user_id: userId,
            title: data.title,
            course_id: data.courseId || null,
            due_date: data.dueDate ? data.dueDate : null,
            estimated_hours: data.estimatedHours || 2,
            priority: data.priority || 2,
            description: data.description || '',
          })
          .select()
          .single();

        action = { type, data: task };
      } else {
        action = { type, data };
      }
    } catch {
      // Action parsing failed, just return response as-is
    }
  }

  const cleanResponse = response.replace(/<action[^>]*>.*?<\/action>/gs, '').trim();

  return { sessionId: sid, response: cleanResponse, action };
}
