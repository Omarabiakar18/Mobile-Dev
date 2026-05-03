import { Prisma } from '@prisma/client';

import { prisma } from './prisma';

const MS_PER_DAY = 86_400_000;

/**
 * Window fallbacks per spec §6.1 step 7: try the last 60 days first, then 90,
 * then 180. Two entries are needed so we have an odometer span to divide.
 */
const WINDOWS_DAYS = [60, 90, 180] as const;

interface OdometerSample {
  odometer: number;
  date: Date;
}

/**
 * Pure helper — exported so the math can be unit-tested without a DB. Returns
 * the avg km/day rounded to 2 decimals, or `null` if no window has ≥2 entries.
 *
 * Strategy: for each window (60d → 90d → 180d), filter entries whose `date` is
 * within that window of `now`. If ≥2 fall in, compute
 * `(maxOdo - minOdo) / daysSpan`. `daysSpan` is the gap between the earliest
 * and latest entry's `date`, clamped to ≥1 to avoid div-by-zero on same-day
 * fills.
 */
export function computeAvgKmPerDay(
  entries: OdometerSample[],
  now: Date = new Date(),
): number | null {
  if (entries.length < 2) return null;

  for (const windowDays of WINDOWS_DAYS) {
    const cutoff = now.getTime() - windowDays * MS_PER_DAY;
    const inWindow = entries.filter((e) => e.date.getTime() >= cutoff);
    if (inWindow.length < 2) continue;

    const odometers = inWindow.map((e) => e.odometer);
    const dates = inWindow.map((e) => e.date.getTime());
    const kmSpan = Math.max(...odometers) - Math.min(...odometers);
    const daysSpan = Math.max(
      (Math.max(...dates) - Math.min(...dates)) / MS_PER_DAY,
      1,
    );
    if (kmSpan <= 0) continue;

    return Math.round((kmSpan / daysSpan) * 100) / 100;
  }

  return null;
}

/**
 * Recomputes `Car.avgKmPerDay` from the car's fuel entries and writes it back.
 * Caller passes a `tx` to keep the recompute in the same transaction as the
 * mutating fuel write (per spec §6.2 — must be atomic). When `tx` is omitted
 * (e.g. the cron job), uses the singleton `prisma` client.
 *
 * Always sets the column — including back to `null` when there isn't enough
 * data — so the row reflects current reality.
 */
export async function recomputeAvgKmPerDay(
  carId: string,
  tx?: Prisma.TransactionClient,
): Promise<void> {
  const client = tx ?? prisma;

  const [entries, prevCar] = await Promise.all([
    client.fuelEntry.findMany({
      where: { carId },
      select: { odometer: true, date: true },
    }),
    client.car.findUnique({
      where: { id: carId },
      select: { avgKmPerDay: true },
    }),
  ]);

  const value = computeAvgKmPerDay(entries);
  const prev = prevCar?.avgKmPerDay == null ? null : Number(prevCar.avgKmPerDay);

  await client.car.update({
    where: { id: carId },
    data: {
      avgKmPerDay: value === null ? null : new Prisma.Decimal(value),
    },
  });

  // Invalidate AI-generated reminder messages when the underlying pace shifts
  // significantly (>5%). Otherwise the cached "due in 28 days" sentence stays
  // on the home banner while the recomputed projection now says 23 days — the
  // reviewer flagged this as a live-demo embarrassment.
  if (shouldInvalidateAiMessages(prev, value)) {
    await client.serviceReminder.updateMany({
      where: { carId, aiMessage: { not: null } },
      data: { aiMessage: null, aiMessageGeneratedAt: null },
    });
  }
}

/**
 * Returns true when the new avgKmPerDay differs from the previous value enough
 * that any cached `aiMessage` (which interpolates the predicted date) is
 * potentially stale.
 *
 * Rules:
 *   - prev null → next non-null: invalidate (we went from "no projection" to
 *     "projection exists"; cached fallback messages need refreshing).
 *   - prev non-null → next null: invalidate (we lost the km-based projection).
 *   - both non-null: invalidate when |Δ| / prev > 5%.
 */
export function shouldInvalidateAiMessages(prev: number | null, next: number | null): boolean {
  if (prev === null && next === null) return false;
  if (prev === null || next === null) return true;
  if (prev === 0) return next !== 0;
  return Math.abs(next - prev) / Math.abs(prev) > 0.05;
}
