import { Router } from 'express';
import { z } from 'zod';

import { asyncHandler } from '../../lib/asyncHandler';
import { ok } from '../../lib/respond';
import { prisma } from '../../lib/prisma';
import { validateBody } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

const updateMeSchema = z
  .object({
    name: z.string().min(1).max(100).trim().optional(),
    phone: z.string().max(30).nullable().optional(),
  })
  .strict();

export const usersRouter = Router();

usersRouter.patch(
  '/me',
  requireAuth,
  validateBody(updateMeSchema),
  asyncHandler(async (req, res) => {
    const user = await prisma.user.update({
      where: { id: req.userId! },
      data: req.body,
      select: { id: true, email: true, name: true, phone: true, createdAt: true },
    });
    ok(res, { user });
  }),
);
