import { Router } from 'express';

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

authRouter.post(
  '/register',
  validateBody(registerSchema),
  asyncHandler(async (req, res) => {
    const result = await authService.register(req.body);
    ok(res, result, 201);
  }),
);

authRouter.post(
  '/login',
  validateBody(loginSchema),
  asyncHandler(async (req, res) => {
    const result = await authService.login(req.body);
    ok(res, result);
  }),
);

authRouter.post(
  '/refresh',
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
