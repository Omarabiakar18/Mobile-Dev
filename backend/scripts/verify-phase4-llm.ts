/**
 * Phase 4 — LLM enhancement sanity checks (spec §16-B + §16-C). Hand-built
 * tests of the *prompt-building* layer, NOT the LLM call itself: we never hit
 * Gemini from this script. Goal is to lock the prompt template strings so a
 * regression on §16-B / §16-C wording (which a code reviewer can't easily
 * eyeball in a PR) is caught here.
 *
 * Run with: cd backend && npx tsx scripts/verify-phase4-llm.ts
 *
 * Stub env vars BEFORE importing modules — reminders.service and
 * fuel.explain.service transitively pull `lib/prisma`, which validates env
 * at import time. We never touch a DB or an LLM client.
 */
process.env.DATABASE_URL ??= 'postgresql://stub:stub@localhost:5432/stub';
process.env.JWT_ACCESS_SECRET ??= 'stub-access-secret-1234567890';
process.env.JWT_REFRESH_SECRET ??= 'stub-refresh-secret-1234567890';

import { Prisma } from '@prisma/client';
import {
  buildReminderPrompt,
  fallbackReminderMessage,
} from '../src/modules/reminders/reminders.service';
import {
  buildExplainPrompt,
  fallbackExplainMessage,
} from '../src/modules/fuel/fuel.explain.service';

let passed = 0;
let failed = 0;

function assertContains(label: string, haystack: string, needle: string): void {
  if (haystack.includes(needle)) {
    passed += 1;
    console.log(`  PASS  ${label}  ->  found "${needle}"`);
  } else {
    failed += 1;
    console.error(
      `  FAIL  ${label}\n        looking for: ${needle}\n        in: ${haystack.slice(0, 200)}`,
    );
  }
}

function assertEq(label: string, actual: unknown, expected: unknown): void {
  if (actual === expected) {
    passed += 1;
    console.log(`  PASS  ${label}  ->  ${String(actual).slice(0, 120)}`);
  } else {
    failed += 1;
    console.error(
      `  FAIL  ${label}\n        expected: ${String(expected).slice(0, 200)}\n        actual:   ${String(actual).slice(0, 200)}`,
    );
  }
}

function assertNotContains(
  label: string,
  haystack: string,
  needle: string,
): void {
  if (!haystack.includes(needle)) {
    passed += 1;
    console.log(`  PASS  ${label}  ->  did not contain "${needle}"`);
  } else {
    failed += 1;
    console.error(`  FAIL  ${label}\n        unexpectedly found: ${needle}`);
  }
}

// ---------------------------------------------------------------------------
console.log('\n[1] buildReminderPrompt — spec §16-B template');
{
  const reminder = {
    serviceType: 'oil change',
    lastDoneKm: 60_000,
    lastDoneDate: new Date('2025-10-30T12:00:00Z'),
  };
  const car = {
    make: 'Toyota',
    model: 'Corolla',
    year: 2020,
    currentKm: 64_000,
    avgKmPerDay: new Prisma.Decimal('50'),
  };
  const projection = {
    predictedDate: new Date('2026-06-29T12:00:00Z'),
    daysRemaining: 60,
  };
  const prompt = buildReminderPrompt(reminder, car, projection);

  // Each line of the spec template should be present, with values
  // interpolated.
  assertContains('serviceType in prompt', prompt, 'oil change');
  assertContains('car identity in prompt', prompt, '2020 Toyota Corolla');
  assertContains('currentKm in prompt', prompt, '64000 km');
  assertContains('lastDoneKm in prompt', prompt, '60000 km');
  assertContains('lastDoneDate iso in prompt', prompt, '2025-10-30');
  assertContains('predictedDate iso in prompt', prompt, '2026-06-29');
  // After the 2026-05-24 LLM sign-flip fix the prompt no longer says
  // "N days from today" (which the model could misread when N was negative).
  // It now emits an explicit `Status: due in N days.` line plus a
  // `daysRemaining: N` numeric field with a sign-convention reminder.
  assertContains('daysRemaining numeric in prompt', prompt, 'daysRemaining: 60');
  assertContains('status phrase in prompt', prompt, 'Status: due in 60 days');
  assertContains('isOverdue flag in prompt', prompt, 'isOverdue: false');
  assertContains('avg km/day in prompt', prompt, '50 km/day');
}

// ---------------------------------------------------------------------------
console.log('\n[2] buildReminderPrompt — null avgKmPerDay falls back to 0');
{
  const reminder = {
    serviceType: 'brake inspection',
    lastDoneKm: 30_000,
    lastDoneDate: new Date('2025-04-30T00:00:00Z'),
  };
  const car = {
    make: 'Honda',
    model: 'Civic',
    year: 2018,
    currentKm: 45_000,
    avgKmPerDay: null,
  };
  const projection = {
    predictedDate: new Date('2026-04-30T12:00:00Z'),
    daysRemaining: 0,
  };
  const prompt = buildReminderPrompt(reminder, car, projection);
  assertContains('null avgKmPerDay → 0 km/day', prompt, '0 km/day');
}

// ---------------------------------------------------------------------------
console.log('\n[3] fallbackReminderMessage — exact template per §16-B');
{
  const out = fallbackReminderMessage(
    'oil change',
    7,
    new Date('2026-05-07T12:00:00Z'),
  );
  assertEq(
    'fallback string',
    out,
    'oil change due in 7 days (~2026-05-07)',
  );
}

// ---------------------------------------------------------------------------
console.log('\n[4] fallbackReminderMessage — overdue (negative days)');
{
  // After the 2026-05-24 LLM sign-flip fix the fallback no longer emits
  // "due in -N days" (read live as confusingly natural English). Overdue
  // now phrases as "was due N days ago"; zero phrases as "due today";
  // positive phrases as "due in N day(s)".
  assertEq(
    'fallback overdue (negative daysRemaining)',
    fallbackReminderMessage('tires', -3, new Date('2026-04-27T12:00:00Z')),
    'tires was due 3 days ago (~2026-04-27)',
  );
  assertEq(
    'fallback overdue (exactly 1 day late)',
    fallbackReminderMessage('oil', -1, new Date('2026-04-27T12:00:00Z')),
    'oil was due 1 day ago (~2026-04-27)',
  );
  assertEq(
    'fallback zero (due today)',
    fallbackReminderMessage('belts', 0, new Date('2026-04-30T12:00:00Z')),
    'belts due today (~2026-04-30)',
  );
  assertEq(
    'fallback singular (due in 1 day)',
    fallbackReminderMessage('coolant', 1, new Date('2026-05-01T12:00:00Z')),
    'coolant due in 1 day (~2026-05-01)',
  );
}

// ---------------------------------------------------------------------------
console.log('\n[5] buildExplainPrompt — spec §16-C template');
{
  const car = {
    make: 'Toyota',
    model: 'Corolla',
    year: 2020,
    currentKm: 11_250,
    tankSize: new Prisma.Decimal('50.00'),
    avgKmPerDay: new Prisma.Decimal('50'),
  };
  const prediction = {
    confidence: 'ok' as const,
    tankRemainingLiters: 30,
    daysRemaining: 7.5,
    predictedDate: '2026-05-08T00:00:00.000Z',
    consumptionPer100km: 8,
    kmSinceLastFull: 250,
  };
  const ctx = {
    n: 2,
    avgKmPerDayWindow: '60 days',
    lastFullTank: {
      date: new Date('2026-04-15T00:00:00Z'),
      odometer: 11_000,
    },
  };
  const prompt = buildExplainPrompt(car, prediction, ctx);

  assertContains('car identity', prompt, '2020 Toyota Corolla');
  assertContains('tank size', prompt, 'tank size 50 L');
  assertContains('currentKm', prompt, '11250 km');
  assertContains('full-tank pairs (n)', prompt, '2 full-tank pairs');
  assertContains('consumptionPer100km', prompt, '8 L/100km');
  assertContains('lastFullTank date', prompt, '2026-04-15');
  assertContains('lastFullTank odo', prompt, '11000 km');
  assertContains('avgKmPerDayWindow', prompt, '(60 days)');
  assertContains('avgKmPerDay', prompt, '50 km/day');
  assertContains('tankRemainingLiters', prompt, '30 L');
  assertContains('daysRemaining', prompt, '7.5 days');
  assertContains('predictedDate iso', prompt, '2026-05-08');
}

// ---------------------------------------------------------------------------
console.log('\n[6] buildExplainPrompt — handles missing lastFullTank');
{
  const car = {
    make: 'Honda',
    model: 'Civic',
    year: 2019,
    currentKm: 50_000,
    tankSize: new Prisma.Decimal('45'),
    avgKmPerDay: new Prisma.Decimal('25'),
  };
  const prediction = {
    confidence: 'ok' as const,
    tankRemainingLiters: 20,
    daysRemaining: null,
    predictedDate: null,
    consumptionPer100km: 7.5,
    kmSinceLastFull: 0,
  };
  const ctx = {
    n: 0,
    avgKmPerDayWindow: '90 days',
    lastFullTank: null,
  };
  const prompt = buildExplainPrompt(car, prediction, ctx);
  assertContains('null lastFullTank → "unknown"', prompt, 'unknown');
  assertContains('null daysRemaining → "unknown"', prompt, 'unknown days');
  assertContains('null predictedDate → "unknown"', prompt, '→ unknown.');
}

// ---------------------------------------------------------------------------
console.log('\n[7] fallbackExplainMessage — interpolates real numbers');
{
  const car = {
    make: 'Toyota',
    model: 'Corolla',
    year: 2020,
    currentKm: 11_250,
    tankSize: new Prisma.Decimal('50.00'),
    avgKmPerDay: new Prisma.Decimal('50'),
  };
  const prediction = {
    confidence: 'ok' as const,
    tankRemainingLiters: 30,
    daysRemaining: 7.5,
    predictedDate: '2026-05-08T00:00:00.000Z',
    consumptionPer100km: 8,
    kmSinceLastFull: 250,
  };
  const out = fallbackExplainMessage(car, prediction, { n: 2 });
  // Format per spec §16-C fallback template wording.
  const expected =
    "Based on 2 full-tank fill-ups, your Toyota Corolla averages 8 L/100km. " +
    "You've driven 250 km since the last full tank. At your 50 km/day pace, " +
    "the tank should run dry in about 7.5 days, around 2026-05-08.";
  assertEq('fallback explanation', out, expected);
}

// ---------------------------------------------------------------------------
console.log('\n[8] fallbackExplainMessage — null daysRemaining renders gracefully');
{
  const car = {
    make: 'Mazda',
    model: '3',
    year: 2017,
    currentKm: 90_000,
    tankSize: new Prisma.Decimal('48'),
    avgKmPerDay: null,
  };
  const prediction = {
    confidence: 'ok' as const,
    tankRemainingLiters: 25,
    daysRemaining: null,
    predictedDate: null,
    consumptionPer100km: 7.2,
    kmSinceLastFull: 100,
  };
  const out = fallbackExplainMessage(car, prediction, { n: 2 });
  assertContains('null avgKmPerDay → 0 km/day', out, '0 km/day pace');
  assertContains('null daysRemaining → "unknown days"', out, 'unknown days');
  assertContains('null predictedDate → "around unknown"', out, 'around unknown.');
  assertNotContains('no NaN leaked', out, 'NaN');
}

// ---------------------------------------------------------------------------

console.log(`\n${'='.repeat(60)}`);
console.log(`  RESULTS: ${passed} passed, ${failed} failed`);
console.log('='.repeat(60));
if (failed > 0) process.exit(1);
process.exit(0);
