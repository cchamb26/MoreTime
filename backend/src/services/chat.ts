import crypto from 'node:crypto';
import { getSupabase } from '../utils/supabase.js';
import { ValidationError } from '../utils/errors.js';
import { chatCompletion } from './ai.js';
import { generateSchedule } from './scheduling.js';

/** Max characters injected from attached file text into a single chat completion (approximate token guard). */
const MAX_ATTACHMENT_INJECT_CHARS = 80_000;

interface ChatResult {
  sessionId: string;
  response: string;
  action?: {
    type: 'task_created' | 'schedule_query' | 'reschedule';
    data?: unknown;
  };
  scheduleGenerated?: boolean;
}

async function buildSystemContext(userId: string): Promise<string> {
  const supabase = getSupabase();
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const todayStr = today.toISOString().slice(0, 10);
  const tomorrowStr = new Date(today.getTime() + 86400000).toISOString().slice(0, 10);

  const [tasksResult, blocksResult, userResult, coursesResult] = await Promise.all([
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
    supabase
      .from('courses')
      .select('id, name')
      .eq('user_id', userId),
  ]);

  const tasks = tasksResult.data ?? [];
  const todayBlocks = blocksResult.data ?? [];
  const user = userResult.data;
  const courses = coursesResult.data ?? [];

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

  const courseList = courses
    .map((c: Record<string, unknown>) => `- "${c.name}" (id: ${c.id})`)
    .join('\n');

  return `You are MoreTime, an AI study assistant helping ${user?.name ?? 'a student'} manage their academic schedule.
Today is ${todayStr} (${user?.timezone ?? 'America/New_York'}).

Current tasks:
${taskList || '(No pending tasks)'}

Today's schedule:
${scheduleList || '(Nothing scheduled today)'}

Student's courses:
${courseList || '(No courses yet)'}

---
RULES — follow these exactly:

1. **Detect tasks aggressively.** Whenever the user mentions ANY assignment, project, exam, quiz, paper, lab, presentation, homework, or deadline — even casually — you MUST emit an <action> block. Do NOT ask for confirmation first; just create it and tell the user you did.

2. **Action block format** (include this EXACTLY as-is at the END of your message, after your natural-language reply):
<action type="task_created">{"title": "...", "courseId": "..." or null, "dueDate": "YYYY-MM-DDTHH:MM:SSZ" or null, "estimatedHours": N, "priority": N, "description": "..."}</action>

3. **Task titles must be specific and descriptive.** Include the course prefix/number and the deliverable type.
   GOOD: "CS310 — Research Paper: Distributed Systems Survey"
   GOOD: "MATH201 — Problem Set 7 (Ch. 12 Integrals)"
   GOOD: "BIO150 — Lab Report: Enzyme Kinetics Experiment"
   BAD: "Research Paper"  BAD: "Problem Set"  BAD: "Lab Report"

4. **courseId**: Match the user's mention to a course from the list above. Use the course's UUID if it matches. Use null only if no course matches and the user didn't specify one.

5. **estimatedHours**: Be realistic. Guidelines:
   - Short homework / problem set: 1–3h
   - Lab report or short paper (2–5 pages): 3–6h
   - Midterm exam study: 6–12h
   - Research paper (8+ pages): 10–20h
   - Final exam study: 10–20h
   - Group project: 8–15h per person
   - Reading response / reflection: 1–2h

6. **priority**: 1 = highest … 5 = lowest. Base it on due-date proximity and likely grade weight.

7. **Schedule queries**: When the user asks what to work on or about their schedule, respond naturally using the task and schedule data above.

8. **General chat**: For non-task conversation (motivation, study tips), just respond helpfully without an action block.

Keep responses concise — 2–4 sentences of natural language, then the action block (if any).`;
}

function buildAugmentedUserContent(
  trimmedMessage: string,
  files: Array<{ original_name: string; parsed_content: string }>,
): string {
  let out = `Use the attached document text below to schedule tasks and deadlines when relevant.

${trimmedMessage || '(User sent only file attachments.)'}`;

  let used = out.length;

  for (const f of files) {
    const header = `\n\n--- File: ${f.original_name} ---\n`;
    const raw = f.parsed_content;
    const budget = MAX_ATTACHMENT_INJECT_CHARS - used - header.length;
    if (budget <= 0) {
      out += '\n\n[Additional file content omitted: size limit reached.]';
      break;
    }
    let chunk = raw;
    if (chunk.length > budget) {
      chunk = chunk.slice(0, budget) + '\n[…truncated…]';
    }
    out += header + chunk;
    used = out.length;
  }

  return out;
}

export async function handleChatMessage(
  userId: string,
  message: string,
  sessionId?: string,
  fileIds?: string[],
): Promise<ChatResult> {
  const supabase = getSupabase();
  const sid = sessionId || crypto.randomUUID();
  const trimmedMessage = message.trim();
  const ids = fileIds?.filter(Boolean) ?? [];

  let attachmentRows: Array<{ original_name: string; parsed_content: string }> = [];
  if (ids.length > 0) {
    const { data: rows, error } = await supabase
      .from('file_uploads')
      .select('id, original_name, parse_status, parsed_content')
      .eq('user_id', userId)
      .in('id', ids);

    if (error) throw error;

    if (!rows || rows.length !== ids.length) {
      throw new ValidationError('One or more attached files were not found or do not belong to you.');
    }

    const byId = new Map(
      rows.map((row) => {
        const r = row as Record<string, unknown>;
        return [r.id as string, r];
      }),
    );

    for (const id of ids) {
      const r = byId.get(id);
      if (!r) {
        throw new ValidationError('One or more attached files were not found or do not belong to you.');
      }
      const name = r.original_name as string;
      if (r.parse_status !== 'completed') {
        throw new ValidationError(
          `File "${name}" is not ready yet (parse status: ${r.parse_status}). Wait for parsing to finish and try again.`,
        );
      }
      const text = (r.parsed_content as string | null)?.trim();
      if (!text) {
        throw new ValidationError(`File "${name}" has no extracted text.`);
      }
      attachmentRows.push({ original_name: name, parsed_content: text });
    }
  }

  let storedContent = trimmedMessage;
  if (attachmentRows.length > 0) {
    const names = attachmentRows.map((f) => f.original_name);
    const suffix = `[Attachments: ${names.join(', ')}]`;
    storedContent = trimmedMessage ? `${trimmedMessage}\n${suffix}` : suffix;
  }

  const augmentedForModel =
    attachmentRows.length > 0 ? buildAugmentedUserContent(trimmedMessage, attachmentRows) : storedContent;

  // Save user message (short form; not full file text)
  await supabase.from('chat_messages').insert({
    user_id: userId,
    role: 'user',
    content: storedContent,
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

  // Build messages for AI — use augmented text only for the latest user turn
  const systemContent = await buildSystemContext(userId);
  const historyRows = history ?? [];
  const mappedHistory = historyRows.map((m: Record<string, unknown>, index: number) => {
    const isLastUser =
      index === historyRows.length - 1 && m.role === 'user' && attachmentRows.length > 0;
    const content = isLastUser ? augmentedForModel : (m.content as string);
    return {
      role: m.role as 'user' | 'assistant',
      content,
    };
  });

  const messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }> = [
    { role: 'system', content: systemContent },
    ...mappedHistory,
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
  let scheduleGenerated = false;
  const actionMatch = response.match(/<action type="(\w+)">([\s\S]+?)<\/action>/);
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

        // Fire-and-forget: regenerate schedule in the background
        // so the chat response returns immediately
        generateSchedule(userId)
          .then(() => { console.log('Auto-schedule after chat task creation succeeded'); })
          .catch((err) => { console.error('Auto-schedule after chat task creation failed:', err); });
        scheduleGenerated = true;
      } else {
        action = { type, data };
      }
    } catch {
      // Action parsing failed, just return response as-is
    }
  }

  const cleanResponse = response.replace(/<action[^>]*>[\s\S]*?<\/action>/g, '').trim();

  return { sessionId: sid, response: cleanResponse, action, scheduleGenerated };
}
