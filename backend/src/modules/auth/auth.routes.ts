import { Router } from 'express';
import rateLimit from 'express-rate-limit';

import { asyncHandler } from '../../lib/asyncHandler';
import { ok } from '../../lib/respond';
import { validateBody } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as authService from './auth.service';
import {
  loginSchema,
  logoutSchema,
  refreshSchema,
  registerSchema,
} from './auth.schemas';

export const authRouter = Router();

// Per-route limiters. The previous mounted-with-skip approach didn't work
// because `req.path` after `app.use('/auth', limiter, router)` is the full
// path, not the router-relative one — so the skip never matched.
const writeLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});
const refreshLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 30, // refresh is hot during cold-start of multiple parallel requests
  standardHeaders: 'draft-7',
  legacyHeaders: false,
});

authRouter.post(
  '/register',
  writeLimiter,
  validateBody(registerSchema),
  asyncHandler(async (req, res) => {
    const result = await authService.register(req.body);
    ok(res, result, 201);
  }),
);

authRouter.post(
  '/login',
  writeLimiter,
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const result = await authService.login(req.body);
    ok(res, result);
  }),
);

authRouter.post(
  '/refresh',
  refreshLimiter,
  validateBody(refreshSchema),
  asyncHandler(async (req, res) => {
    const result = await authService.refresh(req.body.refreshToken);
    ok(res, result);
  }),
);

authRouter.post(
  '/logout',
  validateBody(logoutSchema),
  asyncHandler(async (req, res) => {
    await authService.logout(req.body.refreshToken);
    ok(res, { revoked: true });
  }),
);

authRouter.get(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    const user = await authService.getMe(req.userId!);
    ok(res, { user });
  }),
);
