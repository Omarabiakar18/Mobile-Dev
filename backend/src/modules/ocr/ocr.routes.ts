/**
 * OCR routes — `POST /cars/:carId/fuel/ocr`.
 *
 * Mounting note (see `index.ts`): this router is mounted at
 * `/cars/:carId/fuel/ocr` BEFORE `carScopedFuelRouter` so the more specific
 * prefix wins. Putting OCR concerns in their own module keeps multer config
 * and rate limits out of `fuel.routes.ts`.
 *
 * The route uses `multer.memoryStorage` rather than the disk-storage pattern
 * other modules use because we need the raw buffer for both sharp preprocess
 * (in-memory) and the sha256 hash. The `ocr.service.ts` is responsible for
 * persisting the processed image to `<UPLOADS_DIR>/ocr/<hash>.jpg`.
 */
import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import multer from 'multer';

import { asyncHandler } from '../../lib/asyncHandler';
import { ValidationError } from '../../lib/errors';
import { ok } from '../../lib/respond';
import { requireAuth } from '../../middleware/auth';
import { assertOwnsCar } from '../cars/cars.service';

import { ocrQuerySchema, type OcrResponse } from './ocr.schemas';
import * as ocrService from './ocr.service';

// ---------- Multer (memory storage) ---------------------------------------

const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/heic']);

const upload = multer({
  storage: multer.memoryStorage(),
  // 8 MB — receipts captured from a phone are commonly 4-6 MB before
  // compression. Other modules use 5 MB for thumbnails; OCR needs more
  // headroom so we don't reject legitimate captures.
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED_MIME.has(file.mimetype)) {
      cb(new ValidationError('Unsupported file type', { mimetype: file.mimetype }));
      return;
    }
    cb(null, true);
  },
});

// ---------- Rate limit ----------------------------------------------------

/**
 * Spec §3 mandates 10/day/user on `/fuel/ocr`. The default `express-rate-limit`
 * keys on IP, which is wrong for our case (multiple users behind a corporate
 * NAT would share the bucket). We key on `req.userId` — `requireAuth` runs
 * before this middleware, so it's always populated by the time we get here.
 */
const ocrLimiter = rateLimit({
  windowMs: 24 * 60 * 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  // Falling back to IP if userId is missing is paranoia — `requireAuth` would
  // have rejected the request first — but it satisfies TypeScript and the
  // ratelimit lib's "must always return a string" contract.
  keyGenerator: (req) => req.userId ?? req.ip ?? 'anonymous',
});

// ---------- Router --------------------------------------------------------

/**
 * Mounted at `/cars/:carId/fuel/ocr`. `mergeParams` makes `:carId` visible
 * inside this router's handlers despite living on the parent path.
 */
export const ocrRouter = Router({ mergeParams: true });

ocrRouter.use(requireAuth);

ocrRouter.post(
  '/',
  ocrLimiter,
  upload.single('receipt'),
  asyncHandler(async (req, res) => {
    if (!req.file) {
      throw new ValidationError('Missing "receipt" in multipart body');
    }

    const query = ocrQuerySchema.parse(req.query);

    // Defense-in-depth ownership check — the service re-runs this too, but
    // failing fast at the route level keeps an unauthorized user from
    // burning their daily OCR quota on a car they don't own.
    await assertOwnsCar(req.userId!, req.params.carId);

    const result: OcrResponse = await ocrService.extractFuelFields(
      req.userId!,
      req.params.carId,
      req.file.buffer,
      { force: query.force },
    );

    ok(res, result);
  }),
);
