import jwt from 'jsonwebtoken';
import crypto from 'node:crypto';

import { env } from '../config/env';

export interface AccessPayload {
  sub: string;
}

export function signAccessToken(userId: string): string {
  return jwt.sign({ sub: userId }, env.JWT_ACCESS_SECRET, {
    expiresIn: `${env.ACCESS_TOKEN_TTL_MIN}m`,
  });
}

/**
 * Refresh tokens are stored in DB by hash. We hand the user the random opaque
 * token; the DB holds sha256(token). On refresh we hash the incoming token
 * and look it up — this lets us revoke without invalidating the access secret.
 */
export function newRefreshToken(): { token: string; hash: string; expiresAt: Date } {
  const token = crypto.randomBytes(48).toString('base64url');
  const hash = crypto.createHash('sha256').update(token).digest('hex');
  const expiresAt = new Date(Date.now() + env.REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000);
  return { token, hash, expiresAt };
}

export function hashRefreshToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
