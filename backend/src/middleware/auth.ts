import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { getEnv } from '../utils/env.js';
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
  // Dev bypass: skip JWT when DEV_BYPASS_AUTH is set
  if (process.env.DEV_BYPASS_AUTH === 'true') {
    req.user = { userId: DEV_USER_ID, email: DEV_EMAIL };
    return next();
  }

  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return next(new UnauthorizedError('Missing or invalid Authorization header'));
  }

  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, getEnv().JWT_SECRET) as AuthPayload;
    req.user = payload;
    next();
  } catch {
    next(new UnauthorizedError('Invalid or expired token'));
  }
}
