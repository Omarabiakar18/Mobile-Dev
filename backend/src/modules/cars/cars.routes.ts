import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

import { Router } from 'express';
import multer from 'multer';

import { env } from '../../config/env';
import { asyncHandler } from '../../lib/asyncHandler';
import { ValidationError } from '../../lib/errors';
import { ok } from '../../lib/respond';
import { validateBody } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as carsService from './cars.service';
import { createCarSchema, updateCarSchema } from './cars.schemas';

// ---------- Multer config (per-module) ------------------------------
// Mirrors the maintenance-photo upload: files land under
// `<UPLOADS_DIR>/cars/<uuid>.<ext>` and are served via `express.static`.

const PHOTO_DIR = path.resolve(env.UPLOADS_DIR, 'cars');
fs.mkdirSync(PHOTO_DIR, { recursive: true });

const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/heic']);

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

// Set / replace a car's photo. Separate multipart endpoint (rather than
// folding the file into POST/PATCH /cars) keeps the existing JSON create/update
// contract untouched. Mirrors POST /maintenance/:id/photos.
carsRouter.post(
  '/:id/photo',
  photoUpload.single('photo'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      throw new ValidationError('Missing "photo" file in multipart body');
    }
    const car = await carsService.setPhoto(req.userId!, req.params.id, req.file);
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
