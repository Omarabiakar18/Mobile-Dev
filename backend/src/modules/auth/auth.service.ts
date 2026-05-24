import { Prisma } from '@prisma/client';

import { prisma } from '../../lib/prisma';
import { hashPassword, verifyPassword } from '../../lib/passwords';
import { signAccessToken, newRefreshToken, hashRefreshToken } from '../../lib/jwt';
import { AuthError, ConflictError, NotFoundError } from '../../lib/errors';
import type { LoginInput, RegisterInput } from './auth.schemas';

export interface AuthResult {
  user: PublicUser;
  accessToken: string;
  refreshToken: string;
}

export interface PublicUser {
  id: string;
  email: string;
  name: string;
  phone: string | null;
  createdAt: Date;
}

function toPublic(u: {
  id: string;
  email: string;
  name: string;
  phone: string | null;
  createdAt: Date;
}): PublicUser {
  return { id: u.id, email: u.email, name: u.name, phone: u.phone, createdAt: u.createdAt };
}

export async function register(input: RegisterInput): Promise<AuthResult> {
  const passwordHash = await hashPassword(input.password);

  let user;
  try {
    user = await prisma.user.create({
      data: {
        email: input.email,
        passwordHash,
        name: input.name,
        phone: input.phone ?? null,
      },
    });
  } catch (err) {
    if (
      err instanceof Prisma.PrismaClientKnownRequestError &&
      err.code === 'P2002'
    ) {
      throw new ConflictError('Email already registered');
    }
    throw err;
  }

  const tokens = await issueTokens(user.id);
  return { user: toPublic(user), ...tokens };
}

export async function login(input: LoginInput): Promise<AuthResult> {
  const user = await prisma.user.findUnique({ where: { email: input.email } });
  if (!user) throw new AuthError('Invalid email or password');

  const ok = await verifyPassword(input.password, user.passwordHash);
  if (!ok) throw new AuthError('Invalid email or password');

  const tokens = await issueTokens(user.id);
  return { user: toPublic(user), ...tokens };
}

export async function refresh(refreshToken: string): Promise<AuthResult> {
  const tokenHash = hashRefreshToken(refreshToken);
  const stored = await prisma.refreshToken.findUnique({
    where: { tokenHash },
    include: { user: true },
  });

  if (!stored || stored.revokedAt || stored.expiresAt < new Date()) {
    throw new AuthError('Invalid or expired refresh token');
  }

  // Atomic revoke. `updateMany` with a `revokedAt: null` predicate becomes
  // a compare-and-swap at the DB level: only the first racer flips the row,
  // subsequent callers get `count: 0` and throw. Prevents a double-spend
  // window where two concurrent requests both pass the `!stored.revokedAt`
  // check in the findUnique above and each issue a fresh token pair from
  // a single refresh token. Caught by the 2026-05-24 backend audit.
  const revoked = await prisma.refreshToken.updateMany({
    where: { id: stored.id, revokedAt: null },
    data: { revokedAt: new Date() },
  });
  if (revoked.count === 0) {
    throw new AuthError('Invalid or expired refresh token');
  }

  const tokens = await issueTokens(stored.userId);
  return { user: toPublic(stored.user), ...tokens };
}

export async function logout(refreshToken: string): Promise<void> {
  const tokenHash = hashRefreshToken(refreshToken);
  // Revoke if it exists; silently no-op if it doesn't (don't leak info).
  await prisma.refreshToken
    .updateMany({
      where: { tokenHash, revokedAt: null },
      data: { revokedAt: new Date() },
    })
    .catch(() => undefined);
}

export async function getMe(userId: string): Promise<PublicUser> {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  if (!user) throw new NotFoundError('User not found');
  return toPublic(user);
}

async function issueTokens(userId: string): Promise<{ accessToken: string; refreshToken: string }> {
  const accessToken = signAccessToken(userId);
  const { token, hash, expiresAt } = newRefreshToken();
  await prisma.refreshToken.create({
    data: { userId, tokenHash: hash, expiresAt },
  });
  return { accessToken, refreshToken: token };
}
