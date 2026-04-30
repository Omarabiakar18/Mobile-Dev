/**
 * Phase 3 math sanity checks — runs the pure math helpers against hand-built
 * inputs and asserts known outputs. No DB writes, no network. Intended to be
 * documentation-as-code for the spec §6.1 / §6.2 algorithms.
 *
 * Run with: cd backend && npx tsx scripts/verify-phase3-math.ts
 *
 * Stub env vars BEFORE importing modules — `lib/prisma.ts` (transitively pulled
 * in by the service files) parses env at import time and would fail without
 * these. We never actually touch a DB; the values just need to satisfy zod.
 */
process.env.DATABASE_URL ??= 'postgresql://stub:stub@localhost:5432/stub';
process.env.JWT_ACCESS_SECRET ??= 'stub-access-secret-1234567890';
process.env.JWT_REFRESH_SECRET ??= 'stub-refresh-secret-1234567890';

import { Prisma } from '@prisma/client';
import { computeAvgKmPerDay } from '../src/lib/avg-km-per-day';
import { computePredictNext } from '../src/modules/fuel/fuel.service';
import { projectNextDate } from '../src/modules/reminders/reminders.service';

let passed = 0;
let failed = 0;

function assertEq(label: string, actual: unknown, expected: unknown, eps = 0): void {
  let ok: boolean;
  if (
    typeof actual === 'number' &&
    typeof expected === 'number' &&
    Number.isFinite(actual) &&
    Number.isFinite(expected)
  ) {
    ok = Math.abs(actual - expected) <= eps;
  } else {
    ok = actual === expected;
  }
  if (ok) {
    passed += 1;
    console.log(`  PASS  ${label}  ->  ${String(actual)}`);
  } else {
    failed += 1;
    console.error(
      `  FAIL  ${label}\n        expected: ${String(expected)}\n        actual:   ${String(actual)}`,
    );
  }
}

function assertTrue(label: string, cond: boolean): void {
  if (cond) {
    passed += 1;
    console.log(`  PASS  ${label}`);
  } else {
    failed += 1;
    console.error(`  FAIL  ${label}`);
  }
}

function daysAgo(n: number, base: Date): Date {
  return new Date(base.getTime() - n * 86_400_000);
}

// ---------------------------------------------------------------------------
console.log('\n[1] computeAvgKmPerDay — 60-day window, normal case');
{
  const today = new Date('2026-04-30T12:00:00Z');
  // 4 entries spanning 30 days, odometer climbed 3000 km → 100 km/day.
  const entries = [
    { odometer: 10_000, date: daysAgo(30, today) },
    { odometer: 11_000, date: daysAgo(20, today) },
    { odometer: 12_000, date: daysAgo(10, today) },
    { odometer: 13_000, date: today },
  ];
  const avg = computeAvgKmPerDay(entries, today);
  assertEq('avgKmPerDay', avg, 100, 0.01);
}

// ---------------------------------------------------------------------------
console.log('\n[2] computeAvgKmPerDay — falls back to 90d when 60d has only 1 entry');
{
  const today = new Date('2026-04-30T12:00:00Z');
  // Only one entry within 60d, but two within 90d.
  const entries = [
    { odometer: 10_000, date: daysAgo(80, today) },
    { odometer: 14_500, date: daysAgo(10, today) },
  ];
  const avg = computeAvgKmPerDay(entries, today);
  // 4500 km / 70 days = 64.2857… → 64.29
  assertEq('avgKmPerDay (90d window)', avg, 64.29, 0.01);
}

// ---------------------------------------------------------------------------
console.log('\n[3] computeAvgKmPerDay — returns null when <2 entries even at 180d');
{
  const today = new Date('2026-04-30T12:00:00Z');
  const entries = [{ odometer: 10_000, date: daysAgo(10, today) }];
  const avg = computeAvgKmPerDay(entries, today);
  assertEq('avgKmPerDay', avg, null);
}

// ---------------------------------------------------------------------------
console.log('\n[4] computePredictNext — bootstrap (<3 full tanks) returns insufficient_data');
{
  const today = new Date('2026-04-30T12:00:00Z');
  const car = {
    tankSize: new Prisma.Decimal('50.00'),
    currentKm: 12_000,
    avgKmPerDay: new Prisma.Decimal('100'),
  };
  const entries = [
    { odometer: 10_000, liters: new Prisma.Decimal('40'), isFullTank: true },
    { odometer: 11_000, liters: new Prisma.Decimal('38'), isFullTank: true },
  ];
  const r = computePredictNext(car, entries, today);
  assertEq('confidence', r.confidence, 'insufficient_data');
  assertEq('tankRemainingLiters', r.tankRemainingLiters, null);
}

// ---------------------------------------------------------------------------
console.log('\n[5] computePredictNext — full algorithm (3 full tanks)');
{
  const today = new Date('2026-04-30T12:00:00Z');
  // Three full-tank fills, each 500km apart, each using exactly 40 liters.
  // → consumption = 40 / 500 * 100 = 8 L/100km, averaged across 2 pairs = 8.
  // currentKm is 250 km past the last full tank.
  // litersUsed = 250 * 8 / 100 = 20.0
  // tankRemainingLiters = max(0, 50 - 20) = 30.0
  // avgKmPerDay = 50 → daysRemaining = (30 / 8 * 100) / 50 = 7.5 days
  const car = {
    tankSize: new Prisma.Decimal('50.00'),
    currentKm: 11_250,
    avgKmPerDay: new Prisma.Decimal('50'),
  };
  const entries = [
    { odometer: 10_000, liters: new Prisma.Decimal('40'), isFullTank: true },
    { odometer: 10_500, liters: new Prisma.Decimal('40'), isFullTank: true },
    { odometer: 11_000, liters: new Prisma.Decimal('40'), isFullTank: true },
    // Throw in a partial fill — must be ignored by the algorithm.
    { odometer: 10_700, liters: new Prisma.Decimal('20'), isFullTank: false },
  ];
  const r = computePredictNext(car, entries, today);
  assertEq('confidence', r.confidence, 'ok');
  if (r.confidence === 'ok') {
    assertEq('consumptionPer100km', r.consumptionPer100km, 8, 0.001);
    assertEq('kmSinceLastFull', r.kmSinceLastFull, 250);
    assertEq('tankRemainingLiters', r.tankRemainingLiters, 30, 0.01);
    assertEq('daysRemaining', r.daysRemaining, 7.5, 0.01);
    assertTrue(
      'predictedDate is a valid ISO string ~7.5d in the future',
      typeof r.predictedDate === 'string' &&
        Math.abs(
          new Date(r.predictedDate).getTime() - today.getTime() - 7.5 * 86_400_000,
        ) < 1000,
    );
  }
}

// ---------------------------------------------------------------------------
console.log('\n[6] computePredictNext — data_inconsistent when currentKm < lastFullTank.odometer');
{
  const today = new Date('2026-04-30T12:00:00Z');
  const car = {
    tankSize: new Prisma.Decimal('50.00'),
    currentKm: 10_500, // less than the last full tank at 11_000
    avgKmPerDay: new Prisma.Decimal('50'),
  };
  const entries = [
    { odometer: 10_000, liters: new Prisma.Decimal('40'), isFullTank: true },
    { odometer: 10_500, liters: new Prisma.Decimal('40'), isFullTank: true },
    { odometer: 11_000, liters: new Prisma.Decimal('40'), isFullTank: true },
  ];
  const r = computePredictNext(car, entries, today);
  assertEq('confidence', r.confidence, 'data_inconsistent');
}

// ---------------------------------------------------------------------------
console.log('\n[7] computePredictNext — null avgKmPerDay returns ok with null daysRemaining');
{
  const today = new Date('2026-04-30T12:00:00Z');
  const car = {
    tankSize: new Prisma.Decimal('50.00'),
    currentKm: 11_250,
    avgKmPerDay: null,
  };
  const entries = [
    { odometer: 10_000, liters: new Prisma.Decimal('40'), isFullTank: true },
    { odometer: 10_500, liters: new Prisma.Decimal('40'), isFullTank: true },
    { odometer: 11_000, liters: new Prisma.Decimal('40'), isFullTank: true },
  ];
  const r = computePredictNext(car, entries, today);
  assertEq('confidence', r.confidence, 'ok');
  if (r.confidence === 'ok') {
    assertEq('tankRemainingLiters', r.tankRemainingLiters, 30, 0.01);
    assertEq('daysRemaining', r.daysRemaining, null);
    assertEq('predictedDate', r.predictedDate, null);
  }
}

// ---------------------------------------------------------------------------
console.log('\n[8] projectNextDate — picks calendar when km date is later');
{
  const now = new Date('2026-04-30T12:00:00Z');
  // Last done: 6 months ago at 60_000 km. Interval: 12 months OR 10_000 km.
  // Calendar leg → 6 more months from now (≈180 days).
  // Km leg with avg=20 km/day, currentKm=64_000 → kmRemaining=6_000 →
  // 6_000 / 20 = 300 days. So calendar wins (sooner).
  const lastDoneDate = new Date('2025-10-30T12:00:00Z');
  const reminder = {
    lastDoneKm: 60_000,
    lastDoneDate,
    intervalKm: 10_000,
    intervalMonths: 12,
  };
  const car = {
    currentKm: 64_000,
    avgKmPerDay: new Prisma.Decimal('20'),
  };
  const r = projectNextDate(reminder, car, now);
  assertTrue('projection produced', r !== null);
  if (r) {
    // Calendar = lastDoneDate + 12 months = 2026-10-30
    const expectedCalendar = new Date('2026-10-30T12:00:00Z');
    assertEq(
      'predictedDate is calendar (sooner)',
      r.predictedDate.toISOString(),
      expectedCalendar.toISOString(),
    );
    // ~183 days from 2026-04-30 to 2026-10-30
    assertTrue(
      'daysRemaining ≈ 183 (±2)',
      Math.abs(r.daysRemaining - 183) <= 2,
    );
  }
}

// ---------------------------------------------------------------------------
console.log('\n[9] projectNextDate — picks km when km date is earlier');
{
  const now = new Date('2026-04-30T12:00:00Z');
  // Calendar leg → 12 months from 6 months ago = 6 more months (≈180d).
  // Km leg with avg=100 km/day, kmRemaining=6_000 → 60 days. Km wins.
  const lastDoneDate = new Date('2025-10-30T12:00:00Z');
  const reminder = {
    lastDoneKm: 60_000,
    lastDoneDate,
    intervalKm: 10_000,
    intervalMonths: 12,
  };
  const car = {
    currentKm: 64_000,
    avgKmPerDay: new Prisma.Decimal('100'),
  };
  const r = projectNextDate(reminder, car, now);
  assertTrue('projection produced', r !== null);
  if (r) {
    // 60 days from now
    const expectedKm = new Date(now.getTime() + 60 * 86_400_000);
    assertTrue(
      'predictedDate ≈ now + 60 days (±1d)',
      Math.abs(r.predictedDate.getTime() - expectedKm.getTime()) <= 86_400_000,
    );
    assertEq('daysRemaining', r.daysRemaining, 60);
  }
}

// ---------------------------------------------------------------------------
console.log('\n[10] projectNextDate — returns null when neither leg is computable');
{
  const now = new Date('2026-04-30T12:00:00Z');
  const reminder = {
    lastDoneKm: 60_000,
    lastDoneDate: new Date('2025-10-30T12:00:00Z'),
    intervalKm: 10_000,
    intervalMonths: null,
  };
  const car = {
    currentKm: 64_000,
    avgKmPerDay: null, // no cached value → km leg blocked
  };
  const r = projectNextDate(reminder, car, now);
  assertEq('result', r, null);
}

// ---------------------------------------------------------------------------
console.log('\n[11] projectNextDate — overdue gives negative daysRemaining');
{
  const now = new Date('2026-04-30T12:00:00Z');
  // Calendar interval was 6 months from a year ago → already 6 months overdue.
  const reminder = {
    lastDoneKm: 60_000,
    lastDoneDate: new Date('2025-04-30T12:00:00Z'),
    intervalKm: null,
    intervalMonths: 6,
  };
  const car = {
    currentKm: 70_000,
    avgKmPerDay: new Prisma.Decimal('30'),
  };
  const r = projectNextDate(reminder, car, now);
  assertTrue('projection produced', r !== null);
  if (r) {
    assertTrue(
      'daysRemaining is negative (overdue)',
      r.daysRemaining < 0,
    );
  }
}

// ---------------------------------------------------------------------------

console.log(`\n${'='.repeat(60)}`);
console.log(`  RESULTS: ${passed} passed, ${failed} failed`);
console.log('='.repeat(60));
if (failed > 0) process.exit(1);
process.exit(0);
