import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { AuthError } from '../lib/errors';

export interface JwtPayload {
  sub: string; // userId
  iat: number;
  exp: number;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      userId?: string;
    }
  }
}

/**
 * Verifies the access token in the Authorization header and attaches userId to req.
 * Wire onto every protected route via app.use(...) or router.use(requireAuth).
 */
export const requireAuth = (req: Request, _res: Response, next: NextFunction) => {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    throw new AuthError('Missing bearer token');
  }
  const token = header.slice('Bearer '.length).trim();

  try {
    const decoded = jwt.verify(token, env.JWT_ACCESS_SECRET) as JwtPayload;
    req.userId = decoded.sub;
    next();
  } catch {
    throw new AuthError('Invalid or expired access token');
  }
};
