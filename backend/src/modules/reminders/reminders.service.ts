import type { Car, ServiceReminder } from '@prisma/client';

import { prisma } from '../../lib/prisma';
import { ForbiddenError, NotFoundError } from '../../lib/errors';
import { llm, llmOrFallback } from '../../services/llm';
import { assertOwnsCar } from '../cars/cars.service';
import type { CreateReminderInput, UpdateReminderInput } from './reminders.schemas';

const MS_PER_DAY = 86_400_000;
/**
 * Trade-off (spec §16-B): the spec says "recompute when predictedDate shifts"
 * but the schema doesn't store a predictedDate snapshot, so we use a 7-day
 * staleness heuristic instead. avgKmPerDay only meaningfully shifts after
 * several new fuel entries (which take days), so a week of cached phrasing
 * stays accurate without paying for the LLM on every dashboard refresh. If
 * the cache is missing entirely (`aiMessage IS NULL`) we always regenerate.
 */
const AI_MESSAGE_MAX_AGE_MS = 7 * MS_PER_DAY;

const REMINDER_SYSTEM_PROMPT =
  'You write friendly, factual one-sentence service reminders for a car owner. Use ONLY the numbers provided — do not invent any. Do not give specific repair cost estimates. Aim for ~20 words. Conversational but practical.';

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
 * Phase 3 — `min(kmBased, calendar)` projection per spec §6.2. The km leg
 * activates once `Car.avgKmPerDay` is cached (recomputed in the same tx as
 * every fuel mutation, plus a nightly cron for stale rows). When both legs
 * are computable we take the earlier of the two — whichever threshold the
 * driver hits first. Returns `null` only when neither leg produces a date
 * (e.g. km-only reminder on a car with no fuel history yet).
 *
 * `daysRemaining` is whole days from `now` to `predictedDate`. It can be
 * negative when the reminder is overdue — callers (the /due endpoint, the
 * Flutter banner) display "overdue by N days" in that case.
 *
 * Pure + exported so the math can be smoke-tested in isolation.
 */
export function projectNextDate(
  reminder: Pick<
    ServiceReminder,
    'lastDoneKm' | 'lastDoneDate' | 'intervalKm' | 'intervalMonths'
  >,
  car: Pick<Car, 'currentKm' | 'avgKmPerDay'>,
  now: Date = new Date(),
): { predictedDate: Date; daysRemaining: number } | null {
  let kmBasedDate: Date | null = null;
  let calendarDate: Date | null = null;

  // Km leg: needs both an intervalKm and a positive cached avgKmPerDay.
  // kmRemaining can go negative when the car is already past the threshold,
  // which produces a `predictedDate` in the past — that's correct (overdue).
  if (reminder.intervalKm != null && car.avgKmPerDay != null) {
    const avg = Number(car.avgKmPerDay);
    if (avg > 0) {
      const kmRemaining =
        reminder.lastDoneKm + reminder.intervalKm - car.currentKm;
      const daysFromKm = kmRemaining / avg;
      kmBasedDate = new Date(now.getTime() + daysFromKm * MS_PER_DAY);
    }
  }

  // Calendar leg: needs only an intervalMonths. setMonth handles month-length
  // edge cases (e.g. Jan 31 + 1 month → Mar 3) the same way the JS Date API
  // does — close enough for human-scale "every 6 months" reminders.
  if (reminder.intervalMonths != null) {
    const d = new Date(reminder.lastDoneDate);
    d.setMonth(d.getMonth() + reminder.intervalMonths);
    calendarDate = d;
  }

  // min(km, calendar) when both exist; whichever is non-null otherwise.
  let predictedDate: Date | null = null;
  if (kmBasedDate && calendarDate) {
    predictedDate =
      kmBasedDate.getTime() <= calendarDate.getTime() ? kmBasedDate : calendarDate;
  } else {
    predictedDate = kmBasedDate ?? calendarDate;
  }

  if (!predictedDate) return null;

  // Whole days; can be negative for overdue reminders. Math.round picks the
  // nearest day so a 12-hour-overdue reminder shows as 0 days, not -1.
  const daysRemaining = Math.round(
    (predictedDate.getTime() - now.getTime()) / MS_PER_DAY,
  );
  return { predictedDate, daysRemaining };
}

/**
 * Spec §16-B prompt template — pure function, exported so the verification
 * script can hit it without spinning up an LLM client. Numbers are formatted
 * lightly (km as integers, dates as `YYYY-MM-DD`, avg with one decimal) so
 * the model never has to round long floats.
 */
export function buildReminderPrompt(
  reminder: Pick<
    ServiceReminder,
    'serviceType' | 'lastDoneKm' | 'lastDoneDate'
  >,
  car: Pick<Car, 'make' | 'model' | 'year' | 'currentKm' | 'avgKmPerDay'>,
  projection: { predictedDate: Date; daysRemaining: number },
): string {
  const avg = car.avgKmPerDay == null ? 0 : Number(car.avgKmPerDay.toString());
  const avgRounded = Math.round(avg * 10) / 10;
  const predictedDateIso = projection.predictedDate.toISOString().slice(0, 10);
  const lastDoneDateIso = new Date(reminder.lastDoneDate).toISOString().slice(0, 10);

  return [
    `Car: ${car.year} ${car.make} ${car.model}, currently at ${car.currentKm} km.`,
    `Service: ${reminder.serviceType}.`,
    `Last done: ${reminder.lastDoneKm} km on ${lastDoneDateIso}.`,
    `Predicted next: ${predictedDateIso} (${projection.daysRemaining} days from today).`,
    `Driving pace: ${avgRounded} km/day.`,
  ].join('\n');
}

/**
 * Hardcoded fallback string used when the LLM call fails or `DEMO_MODE=true`.
 * Matches the spec §16-B wording verbatim so the demo and the LLM output read
 * similarly enough that a viewer can't tell the difference at a glance.
 */
export function fallbackReminderMessage(
  serviceType: string,
  daysRemaining: number,
  predictedDate: Date,
): string {
  const iso = predictedDate.toISOString().slice(0, 10);
  return `${serviceType} due in ${daysRemaining} days (~${iso})`;
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
 * Each row is enriched with `predictedDate`, `daysRemaining`, and a
 * non-null `aiMessage` (§16-B). The message is either:
 *   - the cached `aiMessage` on the row when fresh enough (<7d old), OR
 *   - a fresh LLM-generated sentence (cached back to the row), OR
 *   - the deterministic fallback template (NOT written back — see comment
 *     in the inner async block).
 *
 * Per-reminder LLM calls run in parallel via Promise.all so 5 stale rows
 * don't serialize into a 5-second response.
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
    aiMessage: string;
  };

  // First pass: compute projections + decide which rows need a fresh LLM call.
  const candidates: {
    reminder: ServiceReminder;
    projection: { predictedDate: Date; daysRemaining: number };
    cacheFresh: boolean;
  }[] = [];

  for (const r of all) {
    const proj = projectNextDate(r, car, now);
    if (!proj) continue;
    const delta = proj.predictedDate.getTime() - now.getTime();
    if (delta > horizon) continue;
    const cacheFresh =
      r.aiMessage != null &&
      r.aiMessageGeneratedAt != null &&
      now.getTime() - r.aiMessageGeneratedAt.getTime() < AI_MESSAGE_MAX_AGE_MS;
    candidates.push({ reminder: r, projection: proj, cacheFresh });
  }

  // Second pass: resolve aiMessage for each row in parallel. Cached rows
  // resolve synchronously; stale rows go through llmOrFallback, which honors
  // DEMO_MODE and falls back to the template on any LLM failure.
  const enriched: Enriched[] = await Promise.all(
    candidates.map(async ({ reminder, projection, cacheFresh }) => {
      let aiMessage: string;

      if (cacheFresh && reminder.aiMessage) {
        aiMessage = reminder.aiMessage;
      } else {
        const prompt = buildReminderPrompt(reminder, car, projection);
        const result = await llmOrFallback(
          () =>
            llm().text(prompt, {
              temperature: 0.3,
              maxTokens: 60,
              systemPrompt: REMINDER_SYSTEM_PROMPT,
            }),
          () =>
            fallbackReminderMessage(
              reminder.serviceType,
              projection.daysRemaining,
              projection.predictedDate,
            ),
        );

        // Strip whitespace + a trailing period-less newline the model often
        // emits, but otherwise trust the model.
        aiMessage = result.value.trim();

        // Only write back when the LLM was actually used. Leaving aiMessage
        // null on fallback keeps the cache invariant: "non-null aiMessage =
        // an LLM has blessed this string at some point" (matches the §16-B
        // spec note about the demo/fallback path).
        if (result.usedLlm) {
          // Fire-and-forget the writeback — it's a cache update, not part of
          // the response contract. We still await it inside Promise.all so
          // the connection isn't dropped before Prisma flushes, but we
          // swallow errors so a transient DB write failure doesn't poison
          // the /due response.
          try {
            await prisma.serviceReminder.update({
              where: { id: reminder.id },
              data: { aiMessage, aiMessageGeneratedAt: now },
            });
          } catch {
            // best-effort cache write
          }
        }
      }

      return { ...reminder, ...projection, aiMessage };
    }),
  );

  enriched.sort(
    (a, b) => a.predictedDate.getTime() - b.predictedDate.getTime(),
  );
  return enriched;
}
