import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/db.js';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { NotFoundError } from '../utils/errors.js';

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

router.get('/', validate(querySchema, 'query'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { courseId, status, sortBy = 'dueDate', sortOrder = 'asc' } = req.query as z.infer<typeof querySchema>;

    const where: Record<string, unknown> = { userId: req.user!.userId };
    if (courseId) where.courseId = courseId;
    if (status) where.status = status;

    const tasks = await prisma.task.findMany({
      where,
      include: { course: { select: { id: true, name: true, color: true } } },
      orderBy: { [sortBy]: sortOrder },
    });
    res.json(tasks);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const task = await prisma.task.findFirst({
      where: { id, userId: req.user!.userId },
      include: {
        course: { select: { id: true, name: true, color: true } },
        scheduleBlocks: { orderBy: { date: 'asc' } },
      },
    });
    if (!task) throw new NotFoundError('Task', id);
    res.json(task);
  } catch (err) {
    next(err);
  }
});

router.post(
  '/',
  validate(createTaskSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = { ...req.body, userId: req.user!.userId };
      if (data.dueDate) data.dueDate = new Date(data.dueDate);

      const task = await prisma.task.create({
        data,
        include: { course: { select: { id: true, name: true, color: true } } },
      });
      res.status(201).json(task);
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
      const existing = await prisma.task.findFirst({
        where: { id, userId: req.user!.userId },
      });
      if (!existing) throw new NotFoundError('Task', id);

      const data = { ...req.body };
      if (data.dueDate) data.dueDate = new Date(data.dueDate);

      const task = await prisma.task.update({
        where: { id },
        data,
        include: { course: { select: { id: true, name: true, color: true } } },
      });
      res.json(task);
    } catch (err) {
      next(err);
    }
  },
);

router.delete('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const existing = await prisma.task.findFirst({
      where: { id, userId: req.user!.userId },
    });
    if (!existing) throw new NotFoundError('Task', id);

    await prisma.task.delete({ where: { id } });
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

export default router;
