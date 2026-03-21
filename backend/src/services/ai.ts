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

  const currentYear = new Date().getFullYear();
  const systemPrompt = `You are an academic document parser. Extract ONLY concrete, submittable deliverables and scheduled assessments from the provided syllabus or document.

**EXTRACT these types:**
- Assignments, homework, problem sets
- Papers, essays, research projects
- Exams (midterm, final, quizzes)
- Lab reports, lab practicals
- Presentations, group projects
- Any other graded deliverable with a due date or exam date

**DO NOT extract:**
- Attendance or participation (these are ongoing policies, not tasks)
- Readings or "read chapter X" (unless a written response is due)
- Class policies, office hours, grading breakdowns by themselves
- Course objectives, learning outcomes, instructor info
- Extra credit unless it has a concrete deliverable and date

For each extracted item, return:
- title: Specific and descriptive. Include the deliverable type and topic.
  GOOD: "Problem Set 3 — Linear Transformations"  GOOD: "Midterm Exam — Chapters 1–6"
  BAD: "PS3"  BAD: "Midterm"
- description: Brief description if the document provides details
- dueDate: ISO 8601 (YYYY-MM-DDTHH:MM:SSZ). Use the ${currentYear}–${currentYear + 1} academic year. If only a weekday is given (e.g. "due Friday of Week 5"), estimate the calendar date.
- estimatedHours: Realistic estimate of student work time. Guidelines:
    * Short homework / problem set: 1–3h
    * Lab report (5–10 pages): 4–8h
    * Short paper (2–5 pages): 3–6h
    * Research paper (8+ pages): 10–20h
    * Midterm study: 6–12h
    * Final exam study: 10–20h
    * Group project (per person): 8–15h
    * Quiz study: 1–3h
    * Presentation prep: 3–6h
    * Reading response / reflection: 1–2h
- priority: 1 (highest) to 5 (lowest), based on grade weight and proximity
- weight: The grade weight if stated (e.g. "15%")

Return JSON: { "tasks": [ ... ] }. If nothing qualifies, return { "tasks": [] }.
Output ONLY valid JSON — no markdown fencing, no extra text.`;

  const response = await client.chat.completions.create({
    model: getDeploymentName(),
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: `Extract tasks from this document:\n\n${content.slice(0, 15000)}` },
    ],

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
