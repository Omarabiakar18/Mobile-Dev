import fs from 'node:fs/promises';
import path from 'node:path';

import type { Car } from '@prisma/client';

import { env } from '../../config/env';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';
import { ForbiddenError, NotFoundError } from '../../lib/errors';
import { recomputeAvgKmPerDay } from '../../lib/avg-km-per-day';
import type { CreateCarInput, UpdateCarInput } from './cars.schemas';

/**
 * Throws ForbiddenError if the car doesn't belong to the user (or NotFound if
 * it doesn't exist). Use at the top of every car-scoped handler.
 */
export async function assertOwnsCar(userId: string, carId: string): Promise<Car> {
  const car = await prisma.car.findUnique({ where: { id: carId } });
  if (!car) throw new NotFoundError('Car not found');
  if (car.userId !== userId) throw new ForbiddenError('You do not own this car');
  return car;
}

export function listForUser(userId: string) {
  return prisma.car.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
  });
}

export async function getById(userId: string, carId: string) {
  return assertOwnsCar(userId, carId);
}

export function create(userId: string, input: CreateCarInput) {
  return prisma.car.create({
    data: {
      userId,
      make: input.make,
      model: input.model,
      year: input.year,
      plate: input.plate,
      color: input.color ?? null,
      currentKm: input.currentKm,
      fuelType: input.fuelType,
      tankSize: input.tankSize,
      photoUrl: input.photoUrl ?? null,
    },
  });
}

export async function update(userId: string, carId: string, input: UpdateCarInput) {
  await assertOwnsCar(userId, carId);

  // If currentKm changed we must recompute avgKmPerDay because predict-next
  // and reminder projection both read it from the cached column. Wrap in a
  // transaction so the cached value never lags the source of truth.
  if (input.currentKm !== undefined) {
    return prisma.$transaction(async (tx) => {
      const car = await tx.car.update({ where: { id: carId }, data: input });
      await recomputeAvgKmPerDay(carId, tx);
      return tx.car.findUnique({ where: { id: car.id } }) as Promise<Car>;
    });
  }

  return prisma.car.update({ where: { id: carId }, data: input });
}

export async function remove(userId: string, carId: string) {
  await assertOwnsCar(userId, carId);
  await prisma.car.delete({ where: { id: carId } });
}

// ---------- Photo ----------------------------------------------------

/**
 * Sets (or replaces) a car's photo. The blob was already written to disk by
 * multer.diskStorage under `<UPLOADS_DIR>/cars/<uuid>.<ext>`; we just point the
 * row at it. If the car already had a locally-uploaded photo, that old file is
 * unlinked best-effort so we don't accumulate orphans. Mirrors the
 * maintenance-photo flow. Returns the updated car.
 */
export async function setPhoto(
  userId: string,
  carId: string,
  file: Express.Multer.File,
) {
  const car = await assertOwnsCar(userId, carId);
  const newUrl = `/uploads/cars/${file.filename}`;
  const oldUrl = car.photoUrl;

  const updated = await prisma.car.update({
    where: { id: carId },
    data: { photoUrl: newUrl },
  });

  // Unlink the previous file only AFTER the row is safely repointed. If we
  // unlinked first and the update then threw, the row would reference a file
  // that no longer exists; this ordering means a failed update leaves the old
  // file intact and only ever risks a recoverable orphan, never a dangling ref.
  if (oldUrl && oldUrl !== newUrl) {
    await unlinkUploadFile(oldUrl);
  }

  return updated;
}

/**
 * Best-effort unlink of a previously-uploaded file. Only touches paths under
 * the served `/uploads/` tree — external URLs (seed data, http...) are left
 * alone. The path comes from our own stored `photoUrl`, never user input.
 */
async function unlinkUploadFile(urlPath: string): Promise<void> {
  const prefix = '/uploads/';
  if (!urlPath.startsWith(prefix)) return;
  const rel = urlPath.slice(prefix.length);
  const abs = path.resolve(env.UPLOADS_DIR, rel);
  try {
    await fs.unlink(abs);
  } catch (err) {
    logger.warn({ err, abs }, 'Failed to unlink old car photo file');
  }
}
