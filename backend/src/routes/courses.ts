import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { prisma } from '../utils/db.js';
import { authGuard } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { NotFoundError } from '../utils/errors.js';

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
    const courses = await prisma.course.findMany({
      where: { userId: req.user!.userId },
      include: { _count: { select: { tasks: true } } },
      orderBy: { name: 'asc' },
    });
    res.json(courses);
  } catch (err) {
    next(err);
  }
});

router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const course = await prisma.course.findFirst({
      where: { id, userId: req.user!.userId },
      include: { tasks: { orderBy: { dueDate: 'asc' } } },
    });
    if (!course) throw new NotFoundError('Course', id);
    res.json(course);
  } catch (err) {
    next(err);
  }
});

router.post(
  '/',
  validate(createCourseSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const course = await prisma.course.create({
        data: { ...req.body, userId: req.user!.userId },
      });
      res.status(201).json(course);
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
      const existing = await prisma.course.findFirst({
        where: { id, userId: req.user!.userId },
      });
      if (!existing) throw new NotFoundError('Course', id);

      const course = await prisma.course.update({
        where: { id },
        data: req.body,
      });
      res.json(course);
    } catch (err) {
      next(err);
    }
  },
);

router.delete('/:id', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const id = req.params.id as string;
    const existing = await prisma.course.findFirst({
      where: { id, userId: req.user!.userId },
    });
    if (!existing) throw new NotFoundError('Course', id);

    await prisma.course.delete({ where: { id } });
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

export default router;
