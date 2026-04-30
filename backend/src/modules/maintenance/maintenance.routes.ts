import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import { Router } from 'express';
import multer from 'multer';

import { env } from '../../config/env';
import { asyncHandler } from '../../lib/asyncHandler';
import { ValidationError } from '../../lib/errors';
import { ok } from '../../lib/respond';
import { validateBody, validateQuery } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as maintenanceService from './maintenance.service';
import {
  createMaintenanceSchema,
  listQuerySchema,
  updateMaintenanceSchema,
  type ListMaintenanceQuery,
} from './maintenance.schemas';

// ---------- Multer config (per-module) ------------------------------

const PHOTO_DIR = path.resolve(env.UPLOADS_DIR, 'maintenance');
fs.mkdirSync(PHOTO_DIR, { recursive: true });

const ALLOWED_MIME = new Set([
  'image/jpeg',
  'image/png',
  'image/heic',
]);

// Map MIME → extension. Using the MIME (not the user's filename) avoids spoofed
// extensions; the ext we write is the one we trust.
const MIME_EXT: Record<string, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/heic': '.heic',
};

const photoUpload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, PHOTO_DIR),
    filename: (_req, file, cb) => {
      const ext = MIME_EXT[file.mimetype] ?? path.extname(file.originalname) ?? '';
      cb(null, `${randomUUID()}${ext}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED_MIME.has(file.mimetype)) {
      cb(new ValidationError('Unsupported file type', { mimetype: file.mimetype }));
      return;
    }
    cb(null, true);
  },
});

// ---------- Routers --------------------------------------------------

/**
 * Mounted under `/cars/:carId/maintenance` — the create + list endpoints.
 * Needs `mergeParams` so `:carId` is visible inside this router's handlers.
 */
export const carScopedMaintenanceRouter = Router({ mergeParams: true });

carScopedMaintenanceRouter.use(requireAuth);

carScopedMaintenanceRouter.get(
  '/',
  validateQuery(listQuerySchema),
  asyncHandler(async (req, res) => {
    const query = (req as unknown as { validatedQuery: ListMaintenanceQuery })
      .validatedQuery;
    const result = await maintenanceService.listForCar(
      req.userId!,
      req.params.carId,
      query,
    );
    ok(res, result);
  }),
);

carScopedMaintenanceRouter.post(
  '/',
  validateBody(createMaintenanceSchema),
  asyncHandler(async (req, res) => {
    const entry = await maintenanceService.create(
      req.userId!,
      req.params.carId,
      req.body,
    );
    ok(res, { maintenance: entry }, 201);
  }),
);

/**
 * Mounted under `/maintenance` — get/patch/delete by id, plus photo subroutes.
 */
export const maintenanceByIdRouter = Router();

maintenanceByIdRouter.use(requireAuth);

maintenanceByIdRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const entry = await maintenanceService.getOne(req.userId!, req.params.id);
    ok(res, { maintenance: entry });
  }),
);

maintenanceByIdRouter.patch(
  '/:id',
  validateBody(updateMaintenanceSchema),
  asyncHandler(async (req, res) => {
    const entry = await maintenanceService.update(
      req.userId!,
      req.params.id,
      req.body,
    );
    ok(res, { maintenance: entry });
  }),
);

maintenanceByIdRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await maintenanceService.remove(req.userId!, req.params.id);
    res.status(204).end();
  }),
);

// ----- Photos -----

maintenanceByIdRouter.post(
  '/:id/photos',
  photoUpload.single('photo'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      throw new ValidationError('Missing "photo" file in multipart body');
    }
    const photo = await maintenanceService.addPhoto(
      req.userId!,
      req.params.id,
      req.file,
    );
    ok(res, { photo }, 201);
  }),
);

maintenanceByIdRouter.delete(
  '/:id/photos/:photoId',
  asyncHandler(async (req, res) => {
    await maintenanceService.removePhoto(
      req.userId!,
      req.params.id,
      req.params.photoId,
    );
    res.status(204).end();
  }),
);
