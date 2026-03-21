import { getOpenAIClient, getDeploymentName } from '../utils/azure-openai.js';

interface ExtractedTask {
  title: string;
  description?: string;
  dueDate?: string;
  estimatedHours?: number;
  priority?: number;
  weight?: string;
}

export async function extractTasksFromContent(
  content: string,
  courseId: string | null,
): Promise<ExtractedTask[]> {
  const client = getOpenAIClient();

  const systemPrompt = `You are an academic document parser. Extract all assignments, projects, exams, and deadlines from the provided syllabus or document content.

For each item, extract:
- title: The assignment/exam name
- description: Brief description if available
- dueDate: In ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ) if a specific date is given. Use the current academic year.
- estimatedHours: Your estimate of hours needed (1-50 range)
- priority: 1 (highest) to 5 (lowest), based on weight/importance
- weight: The grade weight if specified (e.g., "15%")

Return a JSON array. If no items are found, return an empty array.
Only output valid JSON, no markdown fencing or extra text.`;

  const response = await client.chat.completions.create({
    model: getDeploymentName(),
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: `Extract tasks from this document:\n\n${content.slice(0, 15000)}` },
    ],
    temperature: 0.1,
    max_completion_tokens: 4000,
    response_format: { type: 'json_object' },
  });

  const raw = response.choices[0]?.message?.content;
  if (!raw) return [];

  try {
    const parsed = JSON.parse(raw);
    const items = Array.isArray(parsed) ? parsed : parsed.tasks || parsed.assignments || [];
    return items.filter((item: ExtractedTask) => item.title);
  } catch {
    console.error('Failed to parse AI task extraction response');
    return [];
  }
}

export async function chatCompletion(
  messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }>,
): Promise<string> {
  const client = getOpenAIClient();

  const response = await client.chat.completions.create({
    model: getDeploymentName(),
    messages,
    temperature: 0.7,
    max_completion_tokens: 2000,
  });

  return response.choices[0]?.message?.content ?? 'I was unable to generate a response.';
}

export interface ScheduleBlockInput {
  taskId: string;
  date: string;
  startTime: string;
  endTime: string;
}

export async function generateScheduleBlocks(prompt: string): Promise<ScheduleBlockInput[]> {
  const client = getOpenAIClient();

  const response = await client.chat.completions.create({
    model: getDeploymentName(),
    messages: [
      {
        role: 'system',
        content: `You are a student schedule optimizer. Given the following tasks, deadlines, estimated work hours, priorities, and the student's availability windows, produce an optimal day-by-day work schedule as a JSON array.

Rules:
- Never schedule over locked blocks (classes, work, etc.)
- Spread work across available days; avoid cramming
- Higher priority tasks get earlier and more consistent slots
- Respect estimated hours — split across multiple days if needed
- Include short breaks between blocks (at least 15 min)
- Schedule in blocks of 30min to 3hrs max
- Output strict JSON: { "blocks": [{ "taskId": "", "date": "YYYY-MM-DD", "startTime": "HH:MM", "endTime": "HH:MM" }] }
- Only output valid JSON, no markdown or extra text`,
      },
      { role: 'user', content: prompt },
    ],
    temperature: 0.2,
    max_completion_tokens: 8000,
    response_format: { type: 'json_object' },
  });

  const raw = response.choices[0]?.message?.content;
  if (!raw) return [];

  try {
    const parsed = JSON.parse(raw);
    const blocks = Array.isArray(parsed) ? parsed : parsed.blocks || parsed.schedule || [];
    return blocks.filter(
      (b: ScheduleBlockInput) => b.taskId && b.date && b.startTime && b.endTime,
    );
  } catch {
    console.error('Failed to parse schedule generation response');
    return [];
  }
}
