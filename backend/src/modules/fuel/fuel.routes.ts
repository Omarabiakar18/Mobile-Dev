import { Router } from 'express';
import rateLimit from 'express-rate-limit';

import { asyncHandler } from '../../lib/asyncHandler';
import { ok } from '../../lib/respond';
import { validateBody } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as fuelService from './fuel.service';
import * as fuelExplainService from './fuel.explain.service';
import {
  createFuelSchema,
  listQuerySchema,
  updateFuelSchema,
} from './fuel.schemas';

/**
 * Mounted under `/cars/:carId/...` — handles list/create/stats/predict-next.
 * `mergeParams` lets us read `:carId` even though it lives on the parent path.
 */
export const carScopedFuelRouter = Router({ mergeParams: true });

carScopedFuelRouter.use(requireAuth);

carScopedFuelRouter.get(
  '/fuel',
  asyncHandler(async (req, res) => {
    const { page, limit } = listQuerySchema.parse(req.query);
    const result = await fuelService.listForCar(
      req.userId!,
      req.params.carId,
      page,
      limit,
    );
    ok(res, result);
  }),
);

carScopedFuelRouter.post(
  '/fuel',
  validateBody(createFuelSchema),
  asyncHandler(async (req, res) => {
    const entry = await fuelService.create(
      req.userId!,
      req.params.carId,
      req.body,
    );
    ok(res, { entry }, 201);
  }),
);

carScopedFuelRouter.get(
  '/fuel/stats',
  asyncHandler(async (req, res) => {
    const result = await fuelService.stats(req.userId!, req.params.carId);
    ok(res, result);
  }),
);

carScopedFuelRouter.get(
  '/fuel/predict-next',
  asyncHandler(async (req, res) => {
    const result = await fuelService.predictNext(req.userId!, req.params.carId);
    ok(res, result);
  }),
);

/**
 * §16-C — "Explain this prediction" endpoint. Per-route rate-limit of
 * 30/day/user (spec §16 cost guard). The keyGenerator pins the bucket to
 * `req.userId` (set by `requireAuth` upstream) instead of the default IP
 * key — multiple users behind one NAT shouldn't share a budget.
 */
const explainLimiter = rateLimit({
  windowMs: 24 * 60 * 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => req.userId ?? req.ip ?? 'anon',
});

carScopedFuelRouter.get(
  '/fuel/predict-next/explain',
  explainLimiter,
  asyncHandler(async (req, res) => {
    const result = await fuelExplainService.explainPredictNext(
      req.userId!,
      req.params.carId,
    );
    ok(res, result);
  }),
);

/**
 * Mounted under `/fuel` — handles single-entry get/update/delete.
 * Each handler resolves the entry's car before checking ownership.
 */
export const fuelByIdRouter = Router();

fuelByIdRouter.use(requireAuth);

fuelByIdRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const entry = await fuelService.getOne(req.userId!, req.params.id);
    ok(res, { entry });
  }),
);

fuelByIdRouter.patch(
  '/:id',
  validateBody(updateFuelSchema),
  asyncHandler(async (req, res) => {
    const entry = await fuelService.update(
      req.userId!,
      req.params.id,
      req.body,
    );
    ok(res, { entry });
  }),
);

fuelByIdRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await fuelService.remove(req.userId!, req.params.id);
    res.status(204).end();
  }),
);
