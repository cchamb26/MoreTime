import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { getSupabase } from '../utils/supabase.js';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { NotFoundError } from '../utils/errors.js';
import { toCamel } from '../utils/transform.js';

const router = Router();
router.use(authGuard);

const createTaskSchema = z.object({
  courseId: z.string().optional(),
  title: z.string().min(1).max(500),
  description: z.string().max(5000).optional(),
  dueDate: z.string().datetime().optional(),
  priority: z.number().int().min(1).max(5).optional(),
  estimatedHours: z.number().positive().max(100).optional(),
  status: z.enum(['pending', 'in_progress', 'completed']).optional(),
  recurrence: z
    .object({
      pattern: z.enum(['daily', 'weekly', 'biweekly']),
      days: z.array(z.number().int().min(0).max(6)).optional(),
    })
    .optional(),
});

const updateTaskSchema = createTaskSchema.partial();

const querySchema = z.object({
  courseId: z.string().optional(),
  status: z.enum(['pending', 'in_progress', 'completed']).optional(),
  sortBy: z.enum(['dueDate', 'priority', 'createdAt']).optional(),
  sortOrder: z.enum(['asc', 'desc']).optional(),
});

const SORT_MAP: Record<string, string> = {
  dueDate: 'due_date',
  priority: 'priority',
  createdAt: 'created_at',
};

router.get('/', validate(querySchema, 'query'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { courseId, status, sortBy = 'dueDate', sortOrder = 'asc' } = req.query as z.infer<typeof querySchema>;
    const supabase = getSupabase();

    let query = supabase
      .from('tasks')
      .select('*, courses:course_id(id, name, color)')
      .eq('user_id', req.user!.userId);

    if (courseId) query = query.eq('course_id', courseId);
    if (status) query = query.eq('status', status);

    const column = SORT_MAP[sortBy] ?? 'due_date';
    query = query.order(column, { ascending: sortOrder !== 'desc', nullsFirst: false });

    const { data, error } = await query;
    if (error) throw error;

    const tasks = (data ?? []).map((row: Record<string, unknown>) => {
      const { courses, user_id, ...rest } = row as Record<string, unknown>;
      return { ...toCamel(rest), course: courses ? toCamel(courses) : null };
    });

    res.json(tasks);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const supabase = getSupabase();

    const { data: task, error } = await supabase
      .from('tasks')
      .select('*, courses:course_id(id, name, color)')
      .eq('id', id)
      .eq('user_id', req.user!.userId)
      .single();

    if (error || !task) throw new NotFoundError('Task', id);

    const { data: blocks } = await supabase
      .from('schedule_blocks')
      .select('*')
      .eq('task_id', id)
      .order('date');

    const { courses, user_id, ...rest } = task as Record<string, unknown>;
    res.json({
      ...toCamel(rest),
      course: courses ? toCamel(courses) : null,
      scheduleBlocks: (blocks ?? []).map((b: unknown) => toCamel(b)),
    });
  } catch (err) {
    next(err);
  }
});

router.post(
  '/',
  validate(createTaskSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const supabase = getSupabase();
      const { data, error } = await supabase
        .from('tasks')
        .insert({
          user_id: req.user!.userId,
          course_id: req.body.courseId ?? null,
          title: req.body.title,
          description: req.body.description ?? '',
          due_date: req.body.dueDate ?? null,
          priority: req.body.priority ?? 2,
          estimated_hours: req.body.estimatedHours ?? 1,
          status: req.body.status ?? 'pending',
          recurrence: req.body.recurrence ?? null,
        })
        .select('*, courses:course_id(id, name, color)')
        .single();

      if (error) throw error;

      const { courses, user_id, ...rest } = data as Record<string, unknown>;
      res.status(201).json({ ...toCamel(rest), course: courses ? toCamel(courses) : null });
    } catch (err) {
      next(err);
    }
  },
);

router.patch(
  '/:id',
  validate(updateTaskSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id = req.params.id as string;
      const supabase = getSupabase();

      const updates: Record<string, unknown> = {};
      if (req.body.title !== undefined) updates.title = req.body.title;
      if (req.body.description !== undefined) updates.description = req.body.description;
      if (req.body.dueDate !== undefined) updates.due_date = req.body.dueDate;
      if (req.body.priority !== undefined) updates.priority = req.body.priority;
      if (req.body.estimatedHours !== undefined) updates.estimated_hours = req.body.estimatedHours;
      if (req.body.status !== undefined) updates.status = req.body.status;
      if (req.body.courseId !== undefined) updates.course_id = req.body.courseId;
      if (req.body.recurrence !== undefined) updates.recurrence = req.body.recurrence;

      const { data, error } = await supabase
        .from('tasks')
        .update(updates)
        .eq('id', id)
        .eq('user_id', req.user!.userId)
        .select('*, courses:course_id(id, name, color)')
        .single();

      if (error) throw new NotFoundError('Task', id);

      // When a task is completed, remove its schedule blocks
      if (req.body.status === 'completed') {
        await supabase
          .from('schedule_blocks')
          .delete()
          .eq('task_id', id)
          .eq('user_id', req.user!.userId);
      }

      const { courses, user_id, ...rest } = data as Record<string, unknown>;
      res.json({ ...toCamel(rest), course: courses ? toCamel(courses) : null });
    } catch (err) {
      next(err);
    }
  },
);

router.delete('/clear', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const supabase = getSupabase();

    const { count, error } = await supabase
      .from('tasks')
      .delete({ count: 'exact' })
      .eq('user_id', req.user!.userId);

    if (error) throw error;
    res.json({ removed: count ?? 0 });
  } catch (err) {
    next(err);
  }
});

router.delete('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const supabase = getSupabase();

    const { error } = await supabase
      .from('tasks')
      .delete()
      .eq('id', id)
      .eq('user_id', req.user!.userId);

    if (error) throw new NotFoundError('Task', id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

export default router;
