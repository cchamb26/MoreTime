import { describe, it, expect } from 'vitest';

// Unit tests for scheduling validation logic (extracted for testability)

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

describe('timeToMinutes', () => {
  it('converts HH:MM to minutes correctly', () => {
    expect(timeToMinutes('00:00')).toBe(0);
    expect(timeToMinutes('01:30')).toBe(90);
    expect(timeToMinutes('12:00')).toBe(720);
    expect(timeToMinutes('23:59')).toBe(1439);
  });
});

describe('blocksOverlap', () => {
  it('detects overlapping blocks', () => {
    expect(
      blocksOverlap({ startTime: '09:00', endTime: '10:00' }, { startTime: '09:30', endTime: '10:30' }),
    ).toBe(true);
  });

  it('detects contained blocks', () => {
    expect(
      blocksOverlap({ startTime: '09:00', endTime: '12:00' }, { startTime: '10:00', endTime: '11:00' }),
    ).toBe(true);
  });

  it('returns false for adjacent blocks', () => {
    expect(
      blocksOverlap({ startTime: '09:00', endTime: '10:00' }, { startTime: '10:00', endTime: '11:00' }),
    ).toBe(false);
  });

  it('returns false for non-overlapping blocks', () => {
    expect(
      blocksOverlap({ startTime: '09:00', endTime: '10:00' }, { startTime: '14:00', endTime: '15:00' }),
    ).toBe(false);
  });

  it('detects overlap when blocks share the same time range', () => {
    expect(
      blocksOverlap({ startTime: '09:00', endTime: '10:00' }, { startTime: '09:00', endTime: '10:00' }),
    ).toBe(true);
  });
});
