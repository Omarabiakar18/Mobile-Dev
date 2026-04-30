import fs from 'node:fs/promises';
import path from 'node:path';

import type { MaintenanceEntry, MaintenancePhoto } from '@prisma/client';

import { env } from '../../config/env';
import { ForbiddenError, NotFoundError } from '../../lib/errors';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';
import { assertOwnsCar } from '../cars/cars.service';

import type {
  CreateMaintenanceInput,
  ListMaintenanceQuery,
  UpdateMaintenanceInput,
} from './maintenance.schemas';

type MaintenanceWithPhotos = MaintenanceEntry & { photos: MaintenancePhoto[] };

/**
 * Throws ForbiddenError if the maintenance entry's car doesn't belong to the
 * user (or NotFound if the entry doesn't exist). Returns the loaded entry with
 * its photos so callers don't need a second round-trip.
 */
async function assertOwnsMaintenance(
  userId: string,
  maintId: string,
): Promise<MaintenanceWithPhotos> {
  const entry = await prisma.maintenanceEntry.findUnique({
    where: { id: maintId },
    include: { photos: true, car: { select: { userId: true } } },
  });
  if (!entry) throw new NotFoundError('Maintenance entry not found');
  if (entry.car.userId !== userId) {
    throw new ForbiddenError('You do not own this maintenance entry');
  }
  // Strip the joined car before returning — callers don't need it.
  const { car: _car, ...rest } = entry;
  return rest as MaintenanceWithPhotos;
}

export async function listForCar(
  userId: string,
  carId: string,
  query: ListMaintenanceQuery,
) {
  await assertOwnsCar(userId, carId);
  const { page, limit } = query;
  const [items, total] = await Promise.all([
    prisma.maintenanceEntry.findMany({
      where: { carId },
      orderBy: { date: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
      include: { photos: true },
    }),
    prisma.maintenanceEntry.count({ where: { carId } }),
  ]);
  return { items, total, page, limit };
}

export async function getOne(userId: string, maintId: string) {
  return assertOwnsMaintenance(userId, maintId);
}

export async function create(
  userId: string,
  carId: string,
  input: CreateMaintenanceInput,
) {
  await assertOwnsCar(userId, carId);
  return prisma.maintenanceEntry.create({
    data: {
      carId,
      date: new Date(input.date),
      km: input.km,
      type: input.type,
      description: input.description ?? null,
      cost: input.cost,
      notes: input.notes ?? null,
    },
    include: { photos: true },
  });
}

export async function update(
  userId: string,
  maintId: string,
  input: UpdateMaintenanceInput,
) {
  await assertOwnsMaintenance(userId, maintId);
  return prisma.maintenanceEntry.update({
    where: { id: maintId },
    data: {
      ...(input.date !== undefined ? { date: new Date(input.date) } : {}),
      ...(input.km !== undefined ? { km: input.km } : {}),
      ...(input.type !== undefined ? { type: input.type } : {}),
      ...(input.description !== undefined ? { description: input.description } : {}),
      ...(input.cost !== undefined ? { cost: input.cost } : {}),
      ...(input.notes !== undefined ? { notes: input.notes } : {}),
    },
    include: { photos: true },
  });
}

export async function remove(userId: string, maintId: string) {
  const entry = await assertOwnsMaintenance(userId, maintId);

  // Cascade deletes the photo rows automatically (schema), but we have to
  // unlink the files on disk ourselves. Do this BEFORE the DB delete so a
  // half-failed run leaves orphan files on disk (recoverable) rather than
  // orphan rows pointing at deleted files (broken).
  await Promise.all(entry.photos.map((p) => unlinkPhotoFile(p.url)));

  await prisma.maintenanceEntry.delete({ where: { id: maintId } });
}

// ---------- Photos --------------------------------------------------

export async function addPhoto(
  userId: string,
  maintId: string,
  file: Express.Multer.File,
) {
  await assertOwnsMaintenance(userId, maintId);
  // multer.diskStorage already wrote the file to disk. We just record the row.
  const url = `/uploads/maintenance/${file.filename}`;
  return prisma.maintenancePhoto.create({
    data: {
      maintenanceEntryId: maintId,
      url,
    },
  });
}

export async function removePhoto(
  userId: string,
  maintId: string,
  photoId: string,
) {
  await assertOwnsMaintenance(userId, maintId);
  const photo = await prisma.maintenancePhoto.findUnique({
    where: { id: photoId },
  });
  if (!photo || photo.maintenanceEntryId !== maintId) {
    throw new NotFoundError('Photo not found');
  }
  await unlinkPhotoFile(photo.url);
  await prisma.maintenancePhoto.delete({ where: { id: photoId } });
}

/**
 * Best-effort unlink. We log + swallow ENOENT etc. so a missing file on disk
 * doesn't block the DB cleanup.
 */
async function unlinkPhotoFile(urlPath: string): Promise<void> {
  // urlPath is e.g. "/uploads/maintenance/<id>.jpg"; strip the leading "/uploads/"
  // and resolve against UPLOADS_DIR. This keeps unlink confined to that tree.
  const prefix = '/uploads/';
  const rel = urlPath.startsWith(prefix) ? urlPath.slice(prefix.length) : urlPath;
  const abs = path.resolve(env.UPLOADS_DIR, rel);
  try {
    await fs.unlink(abs);
  } catch (err) {
    logger.warn({ err, abs }, 'Failed to unlink maintenance photo file');
  }
}
