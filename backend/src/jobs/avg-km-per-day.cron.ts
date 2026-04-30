import cron, { type ScheduledTask } from 'node-cron';

import { prisma } from '../lib/prisma';
import { logger } from '../lib/logger';
import { recomputeAvgKmPerDay } from '../lib/avg-km-per-day';

const MS_PER_DAY = 86_400_000;
const STALE_DAYS = 60;

/**
 * Spec §6.2: every fuel mutation already recomputes `avgKmPerDay` in-tx, so
 * fresh data stays accurate. This job is the safety net for cars that have
 * gone quiet — last fill-up >60 days ago, or no fills at all but a stale
 * cached value still on the row. We rebuild from whatever entries are left
 * (which may produce `null` and clear the column, which is the correct
 * "we no longer know" state).
 *
 * Returns the scheduled task so the caller can `.stop()` it on shutdown.
 */
export function startAvgKmPerDayCron(): ScheduledTask {
  // 3 AM daily — quiet hours, off the request path.
  const task = cron.schedule('0 3 * * *', () => {
    void runOnce().catch((err) => {
      logger.error({ err }, 'avgKmPerDay cron crashed unexpectedly');
    });
  });
  logger.info('avgKmPerDay cron scheduled (0 3 * * *)');
  return task;
}

/**
 * Exposed for ad-hoc invocation (manual run, future tests). Wraps the body in
 * try/catch so a single car failure doesn't take down the whole sweep.
 */
export async function runOnce(): Promise<{ scanned: number; recomputed: number }> {
  try {
    const cutoff = new Date(Date.now() - STALE_DAYS * MS_PER_DAY);

    // Find cars whose latest fuel entry is older than `cutoff`, OR who have a
    // cached `avgKmPerDay` but no fuel entries at all (stale value to clear).
    // Two queries because the OR mixes a "no related rows" check with a
    // "max(date) < cutoff" check — neither expressible cleanly in one Prisma
    // where clause.
    const [staleCars, orphanCars] = await Promise.all([
      prisma.car.findMany({
        where: {
          fuelEntries: {
            some: {},
            every: { date: { lt: cutoff } },
          },
        },
        select: { id: true },
      }),
      prisma.car.findMany({
        where: {
          avgKmPerDay: { not: null },
          fuelEntries: { none: {} },
        },
        select: { id: true },
      }),
    ]);

    const carIds = Array.from(new Set([...staleCars, ...orphanCars].map((c) => c.id)));

    let recomputed = 0;
    for (const carId of carIds) {
      try {
        await recomputeAvgKmPerDay(carId);
        recomputed += 1;
      } catch (err) {
        // One bad car shouldn't poison the rest of the sweep.
        logger.error({ err, carId }, 'avgKmPerDay recompute failed for car');
      }
    }

    logger.info(
      { scanned: carIds.length, recomputed },
      'avgKmPerDay cron sweep complete',
    );
    return { scanned: carIds.length, recomputed };
  } catch (err) {
    logger.error({ err }, 'avgKmPerDay cron sweep failed');
    return { scanned: 0, recomputed: 0 };
  }
}
