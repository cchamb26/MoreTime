import { Request, Response, NextFunction } from 'express';
import { getSupabase } from '../utils/supabase.js';
import { UnauthorizedError } from '../utils/errors.js';

export interface AuthPayload {
  userId: string;
  email: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthPayload;
    }
  }
}

const DEV_USER_ID = 'dev-bypass-user';
const DEV_EMAIL = 'dev@moretime.local';

export function authGuard(req: Request, _res: Response, next: NextFunction): void {
  // Dev bypass: skip auth when DEV_BYPASS_AUTH is set
  if (process.env.DEV_BYPASS_AUTH === 'true') {
    req.user = { userId: DEV_USER_ID, email: DEV_EMAIL };
    return next();
  }

  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return next(new UnauthorizedError('Missing or invalid Authorization header'));
  }

  const token = header.slice(7);
  const supabase = getSupabase();

  supabase.auth
    .getUser(token)
    .then(({ data, error }) => {
      if (error || !data.user) {
        return next(new UnauthorizedError('Invalid or expired token'));
      }
      req.user = { userId: data.user.id, email: data.user.email! };
      next();
    })
    .catch(() => next(new UnauthorizedError('Authentication failed')));
}
