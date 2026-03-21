import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { getSupabase } from '../utils/supabase.js';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { NotFoundError } from '../utils/errors.js';
import { toCamel } from '../utils/transform.js';

const router = Router();
router.use(authGuard);

const createCourseSchema = z.object({
  name: z.string().min(1).max(200),
  color: z.string().regex(/^#[0-9A-Fa-f]{6}$/).optional(),
  metadata: z.record(z.unknown()).optional(),
});

const updateCourseSchema = createCourseSchema.partial();

router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const supabase = getSupabase();

    const { data: courses, error } = await supabase
      .from('courses')
      .select('*, tasks(count)')
      .eq('user_id', req.user!.userId)
      .order('name');

    if (error) throw error;

    // Transform to match expected shape: { ..., _count: { tasks: N } }
    const result = (courses ?? []).map((c: Record<string, unknown>) => {
      const { tasks, user_id, ...rest } = c as Record<string, unknown> & { tasks: Array<{ count: number }> };
      return {
        ...toCamel(rest),
        _count: { tasks: tasks?.[0]?.count ?? 0 },
      };
    });

    res.json(result);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const supabase = getSupabase();

    const { data: course, error } = await supabase
      .from('courses')
      .select('*')
      .eq('id', id)
      .eq('user_id', req.user!.userId)
      .single();

    if (error || !course) throw new NotFoundError('Course', id);

    // Fetch tasks for this course
    const { data: tasks } = await supabase
      .from('tasks')
      .select('*')
      .eq('course_id', id)
      .order('due_date');

    res.json({ ...toCamel(course), tasks: (tasks ?? []).map((t: unknown) => toCamel(t)) });
  } catch (err) {
    next(err);
  }
});

router.post(
  '/',
  validate(createCourseSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const supabase = getSupabase();
      const { data, error } = await supabase
        .from('courses')
        .insert({
          user_id: req.user!.userId,
          name: req.body.name,
          color: req.body.color ?? '#6B7280',
          metadata: req.body.metadata ?? {},
        })
        .select()
        .single();

      if (error) throw error;
      res.status(201).json(toCamel(data));
    } catch (err) {
      next(err);
    }
  },
);

router.patch(
  '/:id',
  validate(updateCourseSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id = req.params.id as string;
      const supabase = getSupabase();

      const updates: Record<string, unknown> = {};
      if (req.body.name !== undefined) updates.name = req.body.name;
      if (req.body.color !== undefined) updates.color = req.body.color;
      if (req.body.metadata !== undefined) updates.metadata = req.body.metadata;

      const { data, error } = await supabase
        .from('courses')
        .update(updates)
        .eq('id', id)
        .eq('user_id', req.user!.userId)
        .select()
        .single();

      if (error) throw new NotFoundError('Course', id);
      res.json(toCamel(data));
    } catch (err) {
      next(err);
    }
  },
);

router.delete('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const supabase = getSupabase();

    const { error } = await supabase
      .from('courses')
      .delete()
      .eq('id', id)
      .eq('user_id', req.user!.userId);

    if (error) throw new NotFoundError('Course', id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

export default router;
