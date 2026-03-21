import { Router, Request, Response, NextFunction } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import { prisma } from '../utils/db.js';
import { getEnv } from '../utils/env.js';
import { validate } from '../middleware/validate.js';
import { authGuard, AuthPayload } from '../middleware/auth.js';
import { ConflictError, UnauthorizedError } from '../utils/errors.js';
import crypto from 'node:crypto';

const router = Router();

const registerSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(100),
  password: z.string().min(8).max(128),
  timezone: z.string().optional(),
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string(),
});

const refreshSchema = z.object({
  refreshToken: z.string(),
});

function generateTokens(payload: AuthPayload) {
  const env = getEnv();
  const accessToken = jwt.sign(payload, env.JWT_SECRET, { expiresIn: '15m' });
  const refreshToken = crypto.randomBytes(48).toString('hex');
  return { accessToken, refreshToken };
}

router.post(
  '/register',
  validate(registerSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { email, name, password, timezone } = req.body;

      const existing = await prisma.user.findUnique({ where: { email } });
      if (existing) {
        throw new ConflictError('Email already registered');
      }

      const passwordHash = await bcrypt.hash(password, 12);
      const user = await prisma.user.create({
        data: { email, name, passwordHash, timezone: timezone ?? 'America/New_York' },
        select: { id: true, email: true, name: true, timezone: true, createdAt: true },
      });

      const payload: AuthPayload = { userId: user.id, email: user.email };
      const { accessToken, refreshToken } = generateTokens(payload);

      await prisma.refreshToken.create({
        data: {
          token: refreshToken,
          userId: user.id,
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days
        },
      });

      res.status(201).json({ user, accessToken, refreshToken });
    } catch (err) {
      next(err);
    }
  },
);

router.post(
  '/login',
  validate(loginSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { email, password } = req.body;

      const user = await prisma.user.findUnique({ where: { email } });
      if (!user) throw new UnauthorizedError('Invalid credentials');

      const valid = await bcrypt.compare(password, user.passwordHash);
      if (!valid) throw new UnauthorizedError('Invalid credentials');

      const payload: AuthPayload = { userId: user.id, email: user.email };
      const { accessToken, refreshToken } = generateTokens(payload);

      await prisma.refreshToken.create({
        data: {
          token: refreshToken,
          userId: user.id,
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        },
      });

      res.json({
        user: { id: user.id, email: user.email, name: user.name, timezone: user.timezone },
        accessToken,
        refreshToken,
      });
    } catch (err) {
      next(err);
    }
  },
);

router.post(
  '/refresh',
  validate(refreshSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { refreshToken: token } = req.body;

      const stored = await prisma.refreshToken.findUnique({
        where: { token },
        include: { user: true },
      });

      if (!stored || stored.expiresAt < new Date()) {
        if (stored) await prisma.refreshToken.delete({ where: { id: stored.id } });
        throw new UnauthorizedError('Invalid or expired refresh token');
      }

      // Rotate refresh token
      await prisma.refreshToken.delete({ where: { id: stored.id } });

      const payload: AuthPayload = { userId: stored.user.id, email: stored.user.email };
      const { accessToken, refreshToken } = generateTokens(payload);

      await prisma.refreshToken.create({
        data: {
          token: refreshToken,
          userId: stored.user.id,
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
        },
      });

      res.json({ accessToken, refreshToken });
    } catch (err) {
      next(err);
    }
  },
);

router.post('/logout', authGuard, async (req: Request, res: Response, next: NextFunction) => {
  try {
    // Delete all refresh tokens for this user
    await prisma.refreshToken.deleteMany({ where: { userId: req.user!.userId } });
    res.json({ message: 'Logged out successfully' });
  } catch (err) {
    next(err);
  }
});

router.get('/me', authGuard, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user!.userId },
      select: { id: true, email: true, name: true, preferences: true, timezone: true, createdAt: true },
    });
    res.json(user);
  } catch (err) {
    next(err);
  }
});

const updateProfileSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  timezone: z.string().optional(),
  preferences: z.record(z.unknown()).optional(),
});

router.patch(
  '/me',
  authGuard,
  validate(updateProfileSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const user = await prisma.user.update({
        where: { id: req.user!.userId },
        data: req.body,
        select: { id: true, email: true, name: true, preferences: true, timezone: true },
      });
      res.json(user);
    } catch (err) {
      next(err);
    }
  },
);

export default router;
