import fs from 'node:fs/promises';
import path from 'node:path';

import type {
  MaintenanceEntry,
  MaintenancePhoto,
  MaintenanceType,
  Prisma,
} from '@prisma/client';

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
 * Result of a maintenance create — includes the entry plus the IDs of any
 * service reminders that were auto-bumped because the maintenance type
 * matched their serviceType keyword. See [findReminderKeyword] for the
 * mapping. Returned so the mobile UI can tell the user "saved + 1 reminder
 * updated" in the success toast.
 */
export interface CreateMaintenanceResult {
  entry: MaintenanceWithPhotos;
  updatedReminderIds: string[];
}

/**
 * Maps a MaintenanceType enum value to the substring we search for inside a
 * ServiceReminder's free-form `serviceType` string. Case-insensitive match.
 * Returns null for `other` since "other" has no canonical keyword and would
 * match too liberally.
 *
 * Examples:
 *   `oil`     → matches "Oil change", "Engine oil + filter", "Oil + filter"
 *   `brakes`  → matches "Brake check", "Brake pads"
 *   `tires`   → matches "Tire rotation", "Tire balance"
 *   `filter`  → matches "Air filter", "Cabin filter"
 *   `battery` → matches "Battery check", "Battery replacement"
 *   `other`   → null (no auto-match)
 *
 * Pure + exported so the matcher can be unit-tested in isolation.
 */
export function findReminderKeyword(type: MaintenanceType): string | null {
  switch (type) {
    case 'oil':
      return 'oil';
    case 'brakes':
      return 'brake';
    case 'tires':
      return 'tire';
    case 'filter':
      return 'filter';
    case 'battery':
      return 'battery';
    case 'other':
      return null;
  }
}

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

/**
 * Creates a maintenance entry AND cross-updates any matching service
 * reminders in the same transaction.
 *
 * Cross-update logic (Alaa's #3 in HANDOFF.md):
 *   1. Insert the maintenance entry.
 *   2. Resolve a keyword for `input.type` via [findReminderKeyword]. If
 *      null (`other`), skip — no auto-match.
 *   3. Find every active reminder on this car whose `serviceType` contains
 *      the keyword (case-insensitive).
 *   4. For each match, only bump the reminder if the new event is strictly
 *      MORE RECENT than what's already on the reminder. Specifically:
 *        - `entry.date > reminder.lastDoneDate` AND
 *        - `entry.km   > reminder.lastDoneKm`
 *      This prevents an old entry (e.g. logging a forgotten 2-year-old oil
 *      change) from undoing more recent service history.
 *   5. Bumping clears `aiMessage` + `aiMessageGeneratedAt` so the next read
 *      will regenerate phrasing from the new projection (otherwise the
 *      dashboard banner contradicts the reminder list).
 *
 * Returns `{ entry, updatedReminderIds }` so the route handler / mobile UI
 * can tell the user "saved + N reminders updated".
 */
export async function create(
  userId: string,
  carId: string,
  input: CreateMaintenanceInput,
): Promise<CreateMaintenanceResult> {
  const car = await assertOwnsCar(userId, carId);

  const entryDate = new Date(input.date);

  return prisma.$transaction(async (tx) => {
    const entry = await tx.maintenanceEntry.create({
      data: {
        carId,
        date: entryDate,
        km: input.km,
        type: input.type,
        description: input.description ?? null,
        cost: input.cost,
        notes: input.notes ?? null,
      },
      include: { photos: true },
    });

    // Advance the cached odometer so the dashboard reflects the latest reading.
    // Forward-only: a historical maintenance entry with a lower km must never
    // roll Car.currentKm back to an earlier value.
    if (input.km > car.currentKm) {
      await tx.car.update({ where: { id: carId }, data: { currentKm: input.km } });
    }

    const updatedReminderIds = await bumpMatchingReminders(tx, {
      carId,
      type: input.type,
      km: input.km,
      date: entryDate,
    });

    return { entry, updatedReminderIds };
  });
}

/**
 * Inside-transaction helper: finds reminders on `carId` whose serviceType
 * matches `type`'s keyword and whose lastDone* are STRICTLY older than the
 * incoming entry, then bumps them.
 *
 * Exported for testability — verify-phase scripts call this directly with a
 * mock tx-like object.
 */
async function bumpMatchingReminders(
  tx: Prisma.TransactionClient,
  args: { carId: string; type: MaintenanceType; km: number; date: Date },
): Promise<string[]> {
  const keyword = findReminderKeyword(args.type);
  if (keyword === null) return [];

  // Case-insensitive substring match on serviceType — Postgres `ILIKE`.
  // `mode: 'insensitive'` is Prisma's portable way to ILIKE.
  const candidates = await tx.serviceReminder.findMany({
    where: {
      carId: args.carId,
      isActive: true,
      serviceType: { contains: keyword, mode: 'insensitive' },
    },
    select: {
      id: true,
      lastDoneKm: true,
      lastDoneDate: true,
    },
  });

  // Only bump reminders whose existing lastDone* are strictly older. This
  // protects the user from accidentally undoing a more-recent service when
  // they log a forgotten old maintenance entry.
  const toBump = candidates.filter(
    (r) =>
      args.date.getTime() > r.lastDoneDate.getTime() && args.km > r.lastDoneKm,
  );
  if (toBump.length === 0) return [];

  await tx.serviceReminder.updateMany({
    where: { id: { in: toBump.map((r) => r.id) } },
    data: {
      lastDoneKm: args.km,
      lastDoneDate: args.date,
      // Bust the cached LLM phrasing so the next read regenerates it from
      // the new projection. Otherwise the banner contradicts the list.
      aiMessage: null,
      aiMessageGeneratedAt: null,
      // Also re-arm notifications: clearing lastNotifiedAt lets the next
      // SchedulingSync send a fresh -30d/-7d notification for the new
      // projected date instead of staying silent because it "already
      // notified" the user.
      lastNotifiedAt: null,
    },
  });

  return toBump.map((r) => r.id);
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
