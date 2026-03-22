/** Max reflection lines injected into the chat system prompt. */
export const LEARNING_DEBRIEF_PROMPT_MAX_ENTRIES = 10;

const MAX_REVISIT_IN_PROMPT = 200;

function extractRawArray(preferences: unknown): unknown[] {
  if (preferences == null || typeof preferences !== 'object') return [];
  const prefs = preferences as Record<string, unknown>;
  let v = prefs.learningDebriefs;
  if (typeof v === 'string') {
    try {
      v = JSON.parse(v) as unknown;
    } catch {
      return [];
    }
  }
  if (!Array.isArray(v)) return [];
  return v;
}

function clampStr(s: unknown, max: number): string {
  if (typeof s !== 'string') return '';
  const t = s.trim();
  return t.length > max ? `${t.slice(0, max)}…` : t;
}

function asNumber(n: unknown): number | null {
  if (typeof n === 'number' && Number.isFinite(n)) return n;
  if (typeof n === 'string' && n.trim() !== '') {
    const x = Number(n);
    if (Number.isFinite(x)) return x;
  }
  return null;
}

interface NormalizedDebrief {
  at: string;
  taskTitle: string;
  confidence: number;
  blocker: string;
  revisit: string;
}

function normalizeEntry(raw: unknown): NormalizedDebrief | null {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const o = raw as Record<string, unknown>;
  const at = typeof o.at === 'string' ? o.at.trim() : '';
  const taskTitle = typeof o.taskTitle === 'string' ? o.taskTitle.trim() : '';
  if (!at || !taskTitle) return null;
  const confRaw = asNumber(o.confidence);
  const confidence =
    confRaw !== null ? Math.min(5, Math.max(1, Math.round(confRaw))) : 3;
  const blocker =
    typeof o.blocker === 'string' && o.blocker.trim() !== ''
      ? o.blocker.trim().slice(0, 80)
      : 'unknown';
  const revisit = clampStr(o.revisit, MAX_REVISIT_IN_PROMPT);
  return { at, taskTitle, confidence, blocker, revisit };
}

/** Compact bullet lines for the model; returns "(None)" if nothing usable. */
export function formatLearningDebriefsForPrompt(preferences: unknown): string {
  const raw = extractRawArray(preferences);
  const normalized: NormalizedDebrief[] = [];
  for (const item of raw) {
    const n = normalizeEntry(item);
    if (n) normalized.push(n);
  }
  if (normalized.length === 0) return '(None)';

  normalized.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0));

  const slice = normalized.slice(0, LEARNING_DEBRIEF_PROMPT_MAX_ENTRIES);
  return slice
    .map((e) => {
      const datePart = e.at.length >= 10 ? e.at.slice(0, 10) : e.at;
      const revisitPart = e.revisit ? `; revisit: ${e.revisit}` : '';
      return `- ${datePart} — "${e.taskTitle}" — confidence ${e.confidence}/5 — blocker: ${e.blocker}${revisitPart}`;
    })
    .join('\n');
}
