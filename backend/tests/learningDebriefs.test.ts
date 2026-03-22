import { describe, it, expect } from 'vitest';
import {
  formatLearningDebriefsForPrompt,
  LEARNING_DEBRIEF_PROMPT_MAX_ENTRIES,
} from '../src/utils/learningDebriefs.js';

describe('formatLearningDebriefsForPrompt', () => {
  it('returns (None) for missing or empty learningDebriefs', () => {
    expect(formatLearningDebriefsForPrompt(undefined)).toBe('(None)');
    expect(formatLearningDebriefsForPrompt(null)).toBe('(None)');
    expect(formatLearningDebriefsForPrompt({})).toBe('(None)');
    expect(formatLearningDebriefsForPrompt({ learningDebriefs: [] })).toBe('(None)');
    expect(formatLearningDebriefsForPrompt({ learningDebriefs: null })).toBe('(None)');
  });

  it('parses JSON string learningDebriefs', () => {
    const prefs = {
      learningDebriefs: JSON.stringify([
        {
          at: '2025-03-20T12:00:00Z',
          taskTitle: 'CS101 — Homework 1',
          confidence: 4,
          blocker: 'time',
          revisit: '',
        },
      ]),
    };
    const out = formatLearningDebriefsForPrompt(prefs);
    expect(out).not.toBe('(None)');
    expect(out).toContain('CS101 — Homework 1');
    expect(out).toContain('confidence 4/5');
    expect(out).toContain('blocker: time');
  });

  it('skips malformed entries without throwing', () => {
    const prefs = {
      learningDebriefs: [
        null,
        'not-an-object',
        { at: '', taskTitle: 'x' },
        { at: '2025-01-01T00:00:00Z', taskTitle: 'Valid Task', confidence: 2, blocker: 'understanding' },
        { foo: 'bar' },
      ],
    };
    const out = formatLearningDebriefsForPrompt(prefs);
    expect(out).toContain('Valid Task');
    expect(out).toContain('confidence 2/5');
    expect(out.split('\n').filter((l) => l.startsWith('-')).length).toBe(1);
  });

  it('sorts most recent first and caps at LEARNING_DEBRIEF_PROMPT_MAX_ENTRIES', () => {
    const entries = [];
    for (let i = 0; i < 15; i++) {
      const day = String(i + 1).padStart(2, '0');
      entries.push({
        at: `2025-03-${day}T10:00:00Z`,
        taskTitle: `Task ${i}`,
        confidence: 3,
        blocker: 'motivation',
      });
    }
    const prefs = { learningDebriefs: entries };
    const out = formatLearningDebriefsForPrompt(prefs);
    const lines = out.split('\n').filter((l) => l.startsWith('-'));
    expect(lines.length).toBe(LEARNING_DEBRIEF_PROMPT_MAX_ENTRIES);
    expect(lines[0]).toContain('Task 14');
    expect(out).not.toContain('Task 0');
  });

  it('clamps confidence to 1–5 and truncates long revisit', () => {
    const prefs = {
      learningDebriefs: [
        {
          at: '2025-06-01T00:00:00Z',
          taskTitle: 'T',
          confidence: 99,
          blocker: 'other',
          revisit: 'x'.repeat(300),
        },
      ],
    };
    const out = formatLearningDebriefsForPrompt(prefs);
    expect(out).toContain('confidence 5/5');
    expect(out).toContain('…');
    expect(out.length).toBeLessThan(500);
  });
});
