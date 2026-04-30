import { Router } from 'express';

import { asyncHandler } from '../../lib/asyncHandler';
import { ok } from '../../lib/respond';
import { validateBody, validateQuery } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as remindersService from './reminders.service';
import {
  createReminderSchema,
  updateReminderSchema,
  dueQuerySchema,
  type DueQueryInput,
} from './reminders.schemas';

/**
 * Mounted under `/cars/:carId/reminders`. Owns list/create + the `/due`
 * subroute. `mergeParams` is required so `req.params.carId` survives.
 */
export const carScopedRemindersRouter = Router({ mergeParams: true });
carScopedRemindersRouter.use(requireAuth);

carScopedRemindersRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const reminders = await remindersService.listForCar(
      req.userId!,
      req.params.carId,
    );
    ok(res, { reminders });
  }),
);

carScopedRemindersRouter.post(
  '/',
  validateBody(createReminderSchema),
  asyncHandler(async (req, res) => {
    const reminder = await remindersService.create(
      req.userId!,
      req.params.carId,
      req.body,
    );
    ok(res, { reminder }, 201);
  }),
);

carScopedRemindersRouter.get(
  '/due',
  validateQuery(dueQuerySchema),
  asyncHandler(async (req, res) => {
    const { withinDays } = (
      req as unknown as { validatedQuery: DueQueryInput }
    ).validatedQuery;
    const reminders = await remindersService.due(
      req.userId!,
      req.params.carId,
      withinDays,
    );
    ok(res, { reminders, withinDays });
  }),
);

/**
 * Mounted under `/reminders` for by-id PATCH/DELETE. Ownership is enforced
 * inside the service (it walks reminder → car → userId).
 */
export const remindersByIdRouter = Router();
remindersByIdRouter.use(requireAuth);

remindersByIdRouter.patch(
  '/:id',
  validateBody(updateReminderSchema),
  asyncHandler(async (req, res) => {
    const reminder = await remindersService.update(
      req.userId!,
      req.params.id,
      req.body,
    );
    ok(res, { reminder });
  }),
);

remindersByIdRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await remindersService.remove(req.userId!, req.params.id);
    res.status(204).end();
  }),
);
