import { Router, Request, Response, NextFunction } from 'express';
import { z } from 'zod';
import { getSupabase } from '../utils/supabase.js';
import { validate } from '../middleware/validate.js';
import { authGuard } from '../middleware/auth.js';
import { ConflictError, UnauthorizedError } from '../utils/errors.js';
import { toCamel } from '../utils/transform.js';

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

router.post(
  '/register',
  validate(registerSchema),
  async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { email, name, password, timezone } = req.body;
      const supabase = getSupabase();

      // Create user via Supabase Auth
      const { data: authData, error: authError } = await supabase.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, timezone: timezone ?? 'America/New_York' },
      });

      if (authError) {
        if (authError.message.includes('already')) throw new ConflictError('Email already registered');
        throw authError;
      }

      // Create profile row
      await supabase.from('profiles').insert({
        id: authData.user.id,
        email,
        name,
        timezone: timezone ?? 'America/New_York',
      });

      // Sign in to get session tokens
      const { data: session, error: loginError } = await supabase.auth.signInWithPassword({
        email,
        password,
      });
      if (loginError) throw loginError;

      const user = {
        id: authData.user.id,
        email,
        name,
        timezone: timezone ?? 'America/New_York',
        preferences: {},
        createdAt: authData.user.created_at,
      };

      res.status(201).json({
        user,
        accessToken: session.session!.access_token,
        refreshToken: session.session!.refresh_token,
      });
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
      const supabase = getSupabase();

      const { data, error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw new UnauthorizedError('Invalid credentials');

      // Fetch profile
      const { data: profile } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', data.user!.id)
        .single();

      res.json({
        user: profile ? toCamel(profile) : {
          id: data.user!.id,
          email: data.user!.email,
          name: data.user!.user_metadata?.name ?? '',
          timezone: data.user!.user_metadata?.timezone ?? 'America/New_York',
        },
        accessToken: data.session!.access_token,
        refreshToken: data.session!.refresh_token,
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
      const supabase = getSupabase();

      const { data, error } = await supabase.auth.refreshSession({ refresh_token: token });
      if (error || !data.session) throw new UnauthorizedError('Invalid or expired refresh token');

      res.json({
        accessToken: data.session.access_token,
        refreshToken: data.session.refresh_token,
      });
    } catch (err) {
      next(err);
    }
  },
);

router.post('/logout', authGuard, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const supabase = getSupabase();
    await supabase.auth.admin.signOut(req.user!.userId);
    res.json({ message: 'Logged out successfully' });
  } catch (err) {
    next(err);
  }
});

router.get('/me', authGuard, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const supabase = getSupabase();
    const { data, error } = await supabase
      .from('profiles')
      .select('id, email, name, timezone, preferences, created_at')
      .eq('id', req.user!.userId)
      .single();

    if (error || !data) throw new UnauthorizedError('Profile not found');
    res.json(toCamel(data));
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
      const supabase = getSupabase();
      const updates: Record<string, unknown> = {};
      if (req.body.name !== undefined) updates.name = req.body.name;
      if (req.body.timezone !== undefined) updates.timezone = req.body.timezone;
      if (req.body.preferences !== undefined) updates.preferences = req.body.preferences;

      const { data, error } = await supabase
        .from('profiles')
        .update(updates)
        .eq('id', req.user!.userId)
        .select('id, email, name, timezone, preferences')
        .single();

      if (error) throw error;
      res.json(toCamel(data));
    } catch (err) {
      next(err);
    }
  },
);

export default router;
