import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { getSupabase } from '../utils/supabase.js';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { NotFoundError } from '../utils/errors.js';
import { toCamel } from '../utils/transform.js';
import { generateSchedule } from '../services/scheduling.js';

const router = Router();
router.use(authGuard);

const querySchema = z.object({
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
});

const createBlockSchema = z.object({
  taskId: z.string().optional(),
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  startTime: z.string().regex(/^\d{2}:\d{2}$/),
  endTime: z.string().regex(/^\d{2}:\d{2}$/),
  isLocked: z.boolean().optional(),
  label: z.string().max(200).optional(),
});

const updateBlockSchema = createBlockSchema.partial();

router.get('/', validate(querySchema, 'query'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { startDate, endDate } = req.query as z.infer<typeof querySchema>;
    const supabase = getSupabase();

    const { data, error } = await supabase
      .from('schedule_blocks')
      .select('*, tasks:task_id(id, title, priority, courses:course_id(id, name, color))')
      .eq('user_id', req.user!.userId)
      .gte('date', startDate)
      .lte('date', endDate)
      .order('date')
      .order('start_time');

    if (error) throw error;

    const blocks = (data ?? []).map((row: Record<string, unknown>) => {
      const { tasks, user_id, ...rest } = row as Record<string, unknown>;
      const taskData = tasks as Record<string, unknown> | null;
      let task = null;
      if (taskData) {
        const { courses, ...taskRest } = taskData;
        task = { ...toCamel(taskRest), course: courses ? toCamel(courses) : null };
      }
      return { ...toCamel(rest), task };
    });

    res.json(blocks);
  } catch (err) {
    next(err);
  }
});

router.post(
  '/',
  validate(createBlockSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const supabase = getSupabase();

      const { data, error } = await supabase
        .from('schedule_blocks')
        .insert({
          user_id: req.user!.userId,
          task_id: req.body.taskId ?? null,
          date: req.body.date,
          start_time: req.body.startTime,
          end_time: req.body.endTime,
          is_locked: req.body.isLocked ?? false,
          label: req.body.label ?? null,
        })
        .select('*, tasks:task_id(id, title)')
        .single();

      if (error) throw error;

      const { tasks, user_id, ...rest } = data as Record<string, unknown>;
      res.status(201).json({ ...toCamel(rest), task: tasks ? toCamel(tasks) : null });
    } catch (err) {
      next(err);
    }
  },
);

router.patch(
  '/:id',
  validate(updateBlockSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id = req.params.id as string;
      const supabase = getSupabase();

      const updates: Record<string, unknown> = {};
      if (req.body.taskId !== undefined) updates.task_id = req.body.taskId;
      if (req.body.date !== undefined) updates.date = req.body.date;
      if (req.body.startTime !== undefined) updates.start_time = req.body.startTime;
      if (req.body.endTime !== undefined) updates.end_time = req.body.endTime;
      if (req.body.isLocked !== undefined) updates.is_locked = req.body.isLocked;
      if (req.body.label !== undefined) updates.label = req.body.label;

      const { data, error } = await supabase
        .from('schedule_blocks')
        .update(updates)
        .eq('id', id)
        .eq('user_id', req.user!.userId)
        .select('*, tasks:task_id(id, title)')
        .single();

      if (error) throw new NotFoundError('ScheduleBlock', id);

      const { tasks, user_id, ...rest } = data as Record<string, unknown>;
      res.json({ ...toCamel(rest), task: tasks ? toCamel(tasks) : null });
    } catch (err) {
      next(err);
    }
  },
);

router.delete('/clear', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const supabase = getSupabase();

    const { count, error } = await supabase
      .from('schedule_blocks')
      .delete({ count: 'exact' })
      .eq('user_id', req.user!.userId)
      .eq('is_locked', false);

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
      .from('schedule_blocks')
      .delete()
      .eq('id', id)
      .eq('user_id', req.user!.userId);

    if (error) throw new NotFoundError('ScheduleBlock', id);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

router.post('/generate', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await generateSchedule(req.user!.userId);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

export default router;
