import { Router } from 'express';

import { asyncHandler } from '../../lib/asyncHandler';
import { ok } from '../../lib/respond';
import { validateBody } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as carsService from './cars.service';
import { createCarSchema, updateCarSchema } from './cars.schemas';

export const carsRouter = Router();

carsRouter.use(requireAuth);

carsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const cars = await carsService.listForUser(req.userId!);
    ok(res, { cars });
  }),
);

carsRouter.post(
  '/',
  validateBody(createCarSchema),
  asyncHandler(async (req, res) => {
    const car = await carsService.create(req.userId!, req.body);
    ok(res, { car }, 201);
  }),
);

carsRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const car = await carsService.getById(req.userId!, req.params.id);
    ok(res, { car });
  }),
);

carsRouter.patch(
  '/:id',
  validateBody(updateCarSchema),
  asyncHandler(async (req, res) => {
    const car = await carsService.update(req.userId!, req.params.id, req.body);
    ok(res, { car });
  }),
);

carsRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await carsService.remove(req.userId!, req.params.id);
    res.status(204).end();
  }),
);
