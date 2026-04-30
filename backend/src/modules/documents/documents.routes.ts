import path from 'path';

import { Router } from 'express';
import multer from 'multer';

import { env } from '../../config/env';
import { asyncHandler } from '../../lib/asyncHandler';
import { ValidationError } from '../../lib/errors';
import { ok } from '../../lib/respond';
import { validateBody } from '../../lib/validate';
import { requireAuth } from '../../middleware/auth';

import * as documentsService from './documents.service';
import {
  createDocumentSchema,
  expiringQuerySchema,
  listQuerySchema,
  updateDocumentSchema,
} from './documents.schemas';

/**
 * Per-module multer instance. Files land in `<UPLOADS_DIR>/documents/tmp/`
 * with multer's auto-generated names; the service renames them to
 * `<UPLOADS_DIR>/documents/<docId>.<ext>` once the DB row is created.
 */
const ALLOWED_MIMES = new Set([
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/heic',
]);

const upload = multer({
  storage: multer.diskStorage({
    destination: path.join(env.UPLOADS_DIR, 'documents', 'tmp'),
    filename: (_req, file, cb) => {
      const unique = `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
      cb(null, `${unique}-${file.originalname}`);
    },
  }),
  limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter: (_req, file, cb) => {
    if (!ALLOWED_MIMES.has(file.mimetype)) {
      cb(new ValidationError(`Unsupported file type: ${file.mimetype}`));
      return;
    }
    cb(null, true);
  },
});

// ---------- Car-scoped router (mounted at /cars/:carId/documents) ----------

export const carScopedDocsRouter = Router({ mergeParams: true });

carScopedDocsRouter.use(requireAuth);

carScopedDocsRouter.get(
  '/',
  asyncHandler(async (req, res) => {
    const { page, limit } = listQuerySchema.parse(req.query);
    const documents = await documentsService.listForCar(
      req.userId!,
      req.params.carId,
      page,
      limit,
    );
    ok(res, { documents });
  }),
);

carScopedDocsRouter.get(
  '/expiring',
  asyncHandler(async (req, res) => {
    const { withinDays } = expiringQuerySchema.parse(req.query);
    const documents = await documentsService.expiring(
      req.userId!,
      req.params.carId,
      withinDays,
    );
    ok(res, { documents });
  }),
);

carScopedDocsRouter.post(
  '/',
  upload.single('file'),
  validateBody(createDocumentSchema),
  asyncHandler(async (req, res) => {
    const document = await documentsService.create(
      req.userId!,
      req.params.carId,
      req.body,
      req.file,
    );
    ok(res, { document }, 201);
  }),
);

// ---------- By-id router (mounted at /documents) -------------------------

export const docsByIdRouter = Router();

docsByIdRouter.use(requireAuth);

docsByIdRouter.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const document = await documentsService.getOne(req.userId!, req.params.id);
    ok(res, { document });
  }),
);

docsByIdRouter.patch(
  '/:id',
  validateBody(updateDocumentSchema),
  asyncHandler(async (req, res) => {
    const document = await documentsService.update(
      req.userId!,
      req.params.id,
      req.body,
    );
    ok(res, { document });
  }),
);

docsByIdRouter.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    await documentsService.remove(req.userId!, req.params.id);
    res.status(204).end();
  }),
);
