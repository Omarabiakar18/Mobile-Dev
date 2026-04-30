import type { Car, ServiceReminder } from '@prisma/client';

import { prisma } from '../../lib/prisma';
import { ForbiddenError, NotFoundError } from '../../lib/errors';
import { assertOwnsCar } from '../cars/cars.service';
import type { CreateReminderInput, UpdateReminderInput } from './reminders.schemas';

const MS_PER_DAY = 86_400_000;

/**
 * Verifies the reminder exists and the car it belongs to is owned by `userId`.
 * Returns the reminder so callers don't re-fetch.
 */
async function assertOwnsReminder(
  userId: string,
  reminderId: string,
): Promise<ServiceReminder> {
  const reminder = await prisma.serviceReminder.findUnique({
    where: { id: reminderId },
    include: { car: true },
  });
  if (!reminder) throw new NotFoundError('Reminder not found');
  if (reminder.car.userId !== userId) {
    throw new ForbiddenError('You do not own this reminder');
  }
  // Strip the `car` join before handing back — keeps types narrow.
  const { car: _car, ...rest } = reminder;
  return rest;
}

/**
 * Phase 2 calendar-only projection. Phase 3 will replace this with the full
 * km/day math from spec §6.2. Returns `null` when neither interval can produce
 * a date (e.g. only `intervalKm` set but no `avgKmPerDay` cached on the car).
 *
 * NOTE: kept exported and pure so Phase 3 can swap the body without touching
 * route/service callers.
 */
export function projectNextDate(
  reminder: Pick<
    ServiceReminder,
    'lastDoneKm' | 'lastDoneDate' | 'intervalKm' | 'intervalMonths'
  >,
  car: Pick<Car, 'currentKm' | 'avgKmPerDay'>,
  now: Date = new Date(),
): { predictedDate: Date; daysRemaining: number } | null {
  const candidates: Date[] = [];

  // Calendar leg — cheap, always applies if intervalMonths is set.
  if (reminder.intervalMonths != null) {
    const d = new Date(reminder.lastDoneDate);
    d.setMonth(d.getMonth() + reminder.intervalMonths);
    candidates.push(d);
  }

  // Km leg — only useful once Phase 3 wires `avgKmPerDay`. For Phase 2 this
  // branch is mostly dormant, which the spec calls out explicitly.
  if (reminder.intervalKm != null && car.avgKmPerDay != null) {
    const avg = Number(car.avgKmPerDay);
    if (avg > 0) {
      const kmRemaining =
        reminder.lastDoneKm + reminder.intervalKm - car.currentKm;
      const days = kmRemaining / avg;
      const d = new Date(now.getTime() + days * MS_PER_DAY);
      candidates.push(d);
    }
  }

  if (candidates.length === 0) return null;

  // Whichever projection comes first wins (matches §6.2 `min(km, calendar)`).
  candidates.sort((a, b) => a.getTime() - b.getTime());
  const predictedDate = candidates[0];
  const daysRemaining = Math.ceil(
    (predictedDate.getTime() - now.getTime()) / MS_PER_DAY,
  );
  return { predictedDate, daysRemaining };
}

/**
 * Lists all reminders for a car the user owns. Ordering matches the spec:
 * date-based first when `intervalMonths` is set, falling back to km-based.
 */
export async function listForCar(userId: string, carId: string) {
  await assertOwnsCar(userId, carId);
  // We sort in JS rather than two SQL queries because the rule is per-row, not
  // per-query. Prisma can't express "order by lastDoneDate when intervalMonths
  // is non-null else by lastDoneKm" cleanly.
  const all = await prisma.serviceReminder.findMany({ where: { carId } });
  return [...all].sort((a, b) => {
    const aHasMonths = a.intervalMonths != null;
    const bHasMonths = b.intervalMonths != null;
    if (aHasMonths && bHasMonths) {
      return a.lastDoneDate.getTime() - b.lastDoneDate.getTime();
    }
    if (!aHasMonths && !bHasMonths) {
      return a.lastDoneKm - b.lastDoneKm;
    }
    // Mixed: month-based reminders come first since they have a guaranteed
    // calendar projection.
    return aHasMonths ? -1 : 1;
  });
}

export async function create(
  userId: string,
  carId: string,
  input: CreateReminderInput,
) {
  await assertOwnsCar(userId, carId);
  return prisma.serviceReminder.create({
    data: {
      carId,
      serviceType: input.serviceType,
      lastDoneKm: input.lastDoneKm,
      lastDoneDate: input.lastDoneDate,
      intervalKm: input.intervalKm ?? null,
      intervalMonths: input.intervalMonths ?? null,
      isActive: input.isActive ?? true,
    },
  });
}

export async function update(
  userId: string,
  reminderId: string,
  input: UpdateReminderInput,
) {
  await assertOwnsReminder(userId, reminderId);
  // Pass through only the keys the caller actually sent; `null` is a real
  // signal here (clear-an-interval), so we keep it.
  return prisma.serviceReminder.update({
    where: { id: reminderId },
    data: {
      ...(input.serviceType !== undefined && { serviceType: input.serviceType }),
      ...(input.lastDoneKm !== undefined && { lastDoneKm: input.lastDoneKm }),
      ...(input.lastDoneDate !== undefined && { lastDoneDate: input.lastDoneDate }),
      ...(input.intervalKm !== undefined && { intervalKm: input.intervalKm }),
      ...(input.intervalMonths !== undefined && {
        intervalMonths: input.intervalMonths,
      }),
      ...(input.isActive !== undefined && { isActive: input.isActive }),
    },
  });
}

export async function remove(userId: string, reminderId: string) {
  await assertOwnsReminder(userId, reminderId);
  await prisma.serviceReminder.delete({ where: { id: reminderId } });
}

/**
 * Active reminders whose projected date falls within `withinDays` from now.
 * Each row is enriched with `predictedDate`, `daysRemaining`, and `aiMessage`
 * (which is null in Phase 2 — §16-B will populate it in Phase 4).
 */
export async function due(userId: string, carId: string, withinDays: number) {
  const car = await assertOwnsCar(userId, carId);
  const all = await prisma.serviceReminder.findMany({
    where: { carId, isActive: true },
  });

  const now = new Date();
  const horizon = withinDays * MS_PER_DAY;

  type Enriched = ServiceReminder & {
    predictedDate: Date;
    daysRemaining: number;
  };

  const enriched: Enriched[] = [];
  for (const r of all) {
    const proj = projectNextDate(r, car, now);
    if (!proj) continue;
    const delta = proj.predictedDate.getTime() - now.getTime();
    if (delta > horizon) continue;
    enriched.push({ ...r, ...proj });
  }
  enriched.sort(
    (a, b) => a.predictedDate.getTime() - b.predictedDate.getTime(),
  );
  return enriched;
}
