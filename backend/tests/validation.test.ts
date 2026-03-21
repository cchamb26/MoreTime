import { describe, it, expect } from 'vitest';
import { z } from 'zod';

// Test the validation schemas used in routes

const registerSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(100),
  password: z.string().min(8).max(128),
  timezone: z.string().optional(),
});

const createTaskSchema = z.object({
  courseId: z.string().optional(),
  title: z.string().min(1).max(500),
  description: z.string().max(5000).optional(),
  dueDate: z.string().datetime().optional(),
  priority: z.number().int().min(1).max(5).optional(),
  estimatedHours: z.number().positive().max(100).optional(),
  status: z.enum(['pending', 'in_progress', 'completed']).optional(),
});

describe('registerSchema', () => {
  it('accepts valid input', () => {
    const result = registerSchema.safeParse({
      email: 'test@example.com',
      name: 'Test User',
      password: 'password123',
    });
    expect(result.success).toBe(true);
  });

  it('rejects invalid email', () => {
    const result = registerSchema.safeParse({
      email: 'not-an-email',
      name: 'Test',
      password: 'password123',
    });
    expect(result.success).toBe(false);
  });

  it('rejects short password', () => {
    const result = registerSchema.safeParse({
      email: 'test@example.com',
      name: 'Test',
      password: 'short',
    });
    expect(result.success).toBe(false);
  });

  it('rejects empty name', () => {
    const result = registerSchema.safeParse({
      email: 'test@example.com',
      name: '',
      password: 'password123',
    });
    expect(result.success).toBe(false);
  });
});

describe('createTaskSchema', () => {
  it('accepts minimal valid input', () => {
    const result = createTaskSchema.safeParse({ title: 'Do homework' });
    expect(result.success).toBe(true);
  });

  it('accepts full valid input', () => {
    const result = createTaskSchema.safeParse({
      courseId: 'abc123',
      title: 'Final project',
      description: 'Build a thing',
      dueDate: '2026-04-15T23:59:00Z',
      priority: 1,
      estimatedHours: 20,
      status: 'in_progress',
    });
    expect(result.success).toBe(true);
  });

  it('rejects priority out of range', () => {
    const result = createTaskSchema.safeParse({ title: 'Task', priority: 0 });
    expect(result.success).toBe(false);
  });

  it('rejects negative estimated hours', () => {
    const result = createTaskSchema.safeParse({ title: 'Task', estimatedHours: -1 });
    expect(result.success).toBe(false);
  });

  it('rejects invalid status', () => {
    const result = createTaskSchema.safeParse({ title: 'Task', status: 'done' });
    expect(result.success).toBe(false);
  });
});
