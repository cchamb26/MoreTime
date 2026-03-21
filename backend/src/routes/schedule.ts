import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/db.js';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { NotFoundError } from '../utils/errors.js';
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

    const blocks = await prisma.scheduleBlock.findMany({
      where: {
        userId: req.user!.userId,
        date: {
          gte: new Date(startDate),
          lte: new Date(endDate),
        },
      },
      include: {
        task: {
          select: { id: true, title: true, priority: true, course: { select: { id: true, name: true, color: true } } },
        },
      },
      orderBy: [{ date: 'asc' }, { startTime: 'asc' }],
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
      const data = {
        ...req.body,
        userId: req.user!.userId,
        date: new Date(req.body.date),
      };

      const block = await prisma.scheduleBlock.create({
        data,
        include: { task: { select: { id: true, title: true } } },
      });
      res.status(201).json(block);
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
      const existing = await prisma.scheduleBlock.findFirst({
        where: { id, userId: req.user!.userId },
      });
      if (!existing) throw new NotFoundError('ScheduleBlock', id);

      const data = { ...req.body };
      if (data.date) data.date = new Date(data.date);

      const block = await prisma.scheduleBlock.update({
        where: { id },
        data,
        include: { task: { select: { id: true, title: true } } },
      });
      res.json(block);
    } catch (err) {
      next(err);
    }
  },
);

router.delete('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const existing = await prisma.scheduleBlock.findFirst({
      where: { id, userId: req.user!.userId },
    });
    if (!existing) throw new NotFoundError('ScheduleBlock', id);

    await prisma.scheduleBlock.delete({ where: { id } });
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
