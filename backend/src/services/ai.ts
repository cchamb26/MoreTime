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

export async function breakdownAssignment(
  content: string,
  dueDate: string | null,
): Promise<ExtractedTask[]> {
  const client = getOpenAIClient();
  const currentYear = new Date().getFullYear();
  const todayStr = new Date().toISOString().slice(0, 10);
  const deadlineContext = dueDate
    ? `The assignment is due ${dueDate}. Today is ${todayStr}. Spread the subtasks so they finish 1 day before the deadline.`
    : `No specific due date given. Today is ${todayStr}. Spread subtasks over the next 2 weeks.`;

  const systemPrompt = `You are an academic project planner. Given assignment guidelines or a project description, break the work into small, actionable subtasks that a student can complete in 1–4 hour sessions.

${deadlineContext}

For each subtask, return:
- title: Specific and actionable. Start with a verb.
  GOOD: "Read and annotate 3 source papers on distributed systems"
  GOOD: "Write introduction and thesis statement (500 words)"
  GOOD: "Build database schema and seed test data"
  BAD: "Research"  BAD: "Writing"  BAD: "Setup"
- description: What specifically to accomplish in this chunk
- dueDate: ISO 8601 (YYYY-MM-DDTHH:MM:SSZ). Space subtasks evenly between now and the deadline. Earlier subtasks = research/planning, later = drafting/polishing/review.
- estimatedHours: Realistic for that subtask (1–4h each). Guidelines:
    * Research / reading: 1–2h per session
    * Outlining / planning: 1–2h
    * Writing a section: 2–4h
    * Coding a component: 2–4h
    * Testing / debugging: 1–3h
    * Review / revision: 1–2h
    * Presentation prep: 2–3h
- priority: 1 (highest) to 5 (lowest). Earlier subtasks get higher priority.

Return JSON: { "tasks": [ ... ] }. Order subtasks chronologically.
Output ONLY valid JSON — no markdown fencing, no extra text.`;

  const response = await client.chat.completions.create({
    model: getDeploymentName(),
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: `Break down this assignment into subtasks:\n\n${content.slice(0, 15000)}` },
    ],
    max_completion_tokens: 4000,
    response_format: { type: 'json_object' },
  });

  const raw = response.choices[0]?.message?.content;
  if (!raw) return [];

  try {
    const parsed = JSON.parse(raw);
    const items = Array.isArray(parsed) ? parsed : parsed.tasks || parsed.subtasks || [];
    return items.filter((item: ExtractedTask) => item.title);
  } catch {
    console.error('Failed to parse AI assignment breakdown response');
    return [];
  }
}

export async function detectDocumentType(
  content: string,
): Promise<'syllabus' | 'assignment'> {
  const client = getOpenAIClient();

  const response = await client.chat.completions.create({
    model: getDeploymentName(),
    messages: [
      {
        role: 'system',
        content: `Classify the following academic document as either "syllabus" or "assignment".

A SYLLABUS contains: course schedule, multiple assignments/exams listed, grading policies, instructor info, weekly topics.
An ASSIGNMENT contains: a single project/paper/lab description, specific requirements, rubric, submission instructions for one deliverable.

Return JSON: { "type": "syllabus" } or { "type": "assignment" }
Output ONLY valid JSON.`,
      },
      { role: 'user', content: content.slice(0, 5000) },
    ],
    max_completion_tokens: 50,
    response_format: { type: 'json_object' },
  });

  const raw = response.choices[0]?.message?.content;
  if (!raw) return 'syllabus';

  try {
    const parsed = JSON.parse(raw);
    return parsed.type === 'assignment' ? 'assignment' : 'syllabus';
  } catch {
    return 'syllabus';
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
  label?: string;
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
- IMPORTANT: Each block MUST include a "label" field — a short, specific description of what to work on during that block (e.g. "Read chapters 3-4 and take notes", "Draft introduction paragraph", "Solve problems 1-10"). Do NOT just repeat the task title.
- Output strict JSON: { "blocks": [{ "taskId": "", "date": "YYYY-MM-DD", "startTime": "HH:MM", "endTime": "HH:MM", "label": "" }] }
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
