import { promises as fs } from 'fs';
import path from 'path';

import type { Document } from '@prisma/client';

import { env } from '../../config/env';
import { logger } from '../../lib/logger';
import { NotFoundError, ForbiddenError, ValidationError } from '../../lib/errors';
import { prisma } from '../../lib/prisma';
import { assertOwnsCar } from '../cars/cars.service';
import type {
  CreateDocumentInput,
  UpdateDocumentInput,
} from './documents.schemas';

const DAY_MS = 86_400_000;

/** MIME → file extension mapping for the upload allowlist. */
const EXT_BY_MIME: Record<string, string> = {
  'application/pdf': 'pdf',
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/heic': 'heic',
};

/** Public-facing URL for a document file (served by `express.static`). */
function buildFileUrl(documentId: string, ext: string): string {
  return `/uploads/documents/${documentId}.${ext}`;
}

/** Disk path for the uploaded blob, relative to the project's `UPLOADS_DIR`. */
function buildDiskPath(documentId: string, ext: string): string {
  return path.join(env.UPLOADS_DIR, 'documents', `${documentId}.${ext}`);
}

/**
 * Asserts the document exists, the parent car is owned by the user, and
 * returns the document. Used by every by-id handler.
 */
async function assertOwnsDocument(userId: string, documentId: string): Promise<Document> {
  const doc = await prisma.document.findUnique({ where: { id: documentId } });
  if (!doc) throw new NotFoundError('Document not found');
  const car = await prisma.car.findUnique({ where: { id: doc.carId } });
  if (!car || car.userId !== userId) throw new ForbiddenError('You do not own this document');
  return doc;
}

export async function listForCar(
  userId: string,
  carId: string,
  page: number,
  limit: number,
) {
  await assertOwnsCar(userId, carId);
  return prisma.document.findMany({
    where: { carId },
    orderBy: { expiryDate: 'asc' },
    skip: (page - 1) * limit,
    take: limit,
  });
}

export async function getOne(userId: string, documentId: string) {
  return assertOwnsDocument(userId, documentId);
}

export async function create(
  userId: string,
  carId: string,
  input: CreateDocumentInput,
  file: Express.Multer.File | undefined,
) {
  await assertOwnsCar(userId, carId);

  if (!file) throw new ValidationError('File is required');

  const ext = EXT_BY_MIME[file.mimetype];
  if (!ext) {
    // The multer fileFilter should have rejected this already, but we
    // double-check so a misconfigured filter can't slip a bad MIME through.
    throw new ValidationError(`Unsupported file type: ${file.mimetype}`);
  }

  // Build the row first so we can name the file by its DB id. The blob is
  // already on disk under multer's temp name — we rename it into place.
  const created = await prisma.document.create({
    data: {
      carId,
      type: input.type,
      issuedDate: input.issuedDate ?? null,
      expiryDate: input.expiryDate,
      issuer: input.issuer ?? null,
      notes: input.notes ?? null,
      fileUrl: buildFileUrl('pending', ext), // placeholder, patched below
    },
  });

  const finalDiskPath = buildDiskPath(created.id, ext);
  const finalFileUrl = buildFileUrl(created.id, ext);

  try {
    await fs.mkdir(path.dirname(finalDiskPath), { recursive: true });
    await fs.rename(file.path, finalDiskPath);
  } catch (err) {
    // Roll back the DB row if disk write failed so we don't leave orphans.
    await prisma.document.delete({ where: { id: created.id } }).catch(() => undefined);
    throw err;
  }

  return prisma.document.update({
    where: { id: created.id },
    data: { fileUrl: finalFileUrl },
  });
}

export async function update(
  userId: string,
  documentId: string,
  input: UpdateDocumentInput,
) {
  await assertOwnsDocument(userId, documentId);
  return prisma.document.update({
    where: { id: documentId },
    data: {
      type: input.type,
      issuedDate: input.issuedDate,
      expiryDate: input.expiryDate,
      issuer: input.issuer,
      notes: input.notes,
    },
  });
}

export async function remove(userId: string, documentId: string) {
  const doc = await assertOwnsDocument(userId, documentId);

  // Best-effort file unlink — log but don't throw if the blob is already gone,
  // since the DB row is the source of truth for the user's view.
  if (doc.fileUrl) {
    const filename = path.basename(doc.fileUrl);
    const diskPath = path.join(env.UPLOADS_DIR, 'documents', filename);
    try {
      await fs.unlink(diskPath);
    } catch (err) {
      logger.warn({ err, diskPath }, 'Failed to unlink document file on delete');
    }
  }

  await prisma.document.delete({ where: { id: documentId } });
}

export async function expiring(userId: string, carId: string, withinDays: number) {
  await assertOwnsCar(userId, carId);
  const now = new Date();
  const cutoff = new Date(now.getTime() + withinDays * DAY_MS);
  return prisma.document.findMany({
    where: {
      carId,
      expiryDate: { lte: cutoff },
    },
    orderBy: { expiryDate: 'asc' },
  });
}
