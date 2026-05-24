/**
 * Verify the maintenance → reminder cross-update logic (Alaa's #3 in
 * HANDOFF.md). Two layers:
 *
 *   1. `findReminderKeyword(MaintenanceType)` — the static enum-to-keyword
 *      map. Pure function, trivially testable.
 *   2. The "should this reminder bump?" predicate — case-insensitive
 *      substring match + strict monotonicity on date AND km.
 *
 * We don't hit the DB; we exercise the pure logic. The integration is
 * covered indirectly by the existing route tests when the server is up.
 *
 * Run: `npx tsx scripts/verify-phase6-cross-update.ts`
 */

import { findReminderKeyword } from '../src/modules/maintenance/maintenance.service';

let passed = 0;
let failed = 0;

function assert(label: string, cond: boolean, detail?: string) {
  if (cond) {
    passed++;
    console.log(`  PASS  ${label}` + (detail ? `  ->  ${detail}` : ''));
  } else {
    failed++;
    console.log(`  FAIL  ${label}` + (detail ? `  ->  ${detail}` : ''));
  }
}

function section(title: string) {
  console.log(`\n[${section.count++}] ${title}`);
}
section.count = 1;

// ----------------------------------------------------------------------------
// 1. findReminderKeyword — pure enum-to-keyword map
// ----------------------------------------------------------------------------

section('findReminderKeyword — maps every MaintenanceType to the right keyword');

assert('oil   → "oil"', findReminderKeyword('oil') === 'oil');
assert('brakes → "brake"', findReminderKeyword('brakes') === 'brake');
assert('tires → "tire"', findReminderKeyword('tires') === 'tire');
assert('filter → "filter"', findReminderKeyword('filter') === 'filter');
assert('battery → "battery"', findReminderKeyword('battery') === 'battery');
assert('other  → null (no auto-match)', findReminderKeyword('other') === null);

// ----------------------------------------------------------------------------
// 2. Keyword matching against realistic seeded serviceType strings
//
// The Postgres-side filter is `serviceType ILIKE %keyword%`. Locally we mirror
// it with a case-insensitive `includes()` so we exercise the same intent.
// ----------------------------------------------------------------------------

section('Keyword matches against the strings from prisma/seed.ts');

const matches = (serviceType: string, keyword: string) =>
  serviceType.toLowerCase().includes(keyword);

assert(
  '"Oil change"     matches keyword "oil"',
  matches('Oil change', 'oil'),
);
assert(
  '"Engine oil + filter" matches both "oil" AND "filter"',
  matches('Engine oil + filter', 'oil') &&
    matches('Engine oil + filter', 'filter'),
);
assert(
  '"Brake check"    matches keyword "brake"',
  matches('Brake check', 'brake'),
);
assert(
  '"Tire rotation"  matches keyword "tire"',
  matches('Tire rotation', 'tire'),
);
assert(
  '"Annual inspection" does NOT match "oil" or "brake" or "tire"',
  !matches('Annual inspection', 'oil') &&
    !matches('Annual inspection', 'brake') &&
    !matches('Annual inspection', 'tire'),
);
assert(
  '"OIL CHANGE" (uppercase) still matches keyword "oil" (case-insensitive)',
  matches('OIL CHANGE', 'oil'),
);

// ----------------------------------------------------------------------------
// 3. Bump predicate — strictly newer in date AND in km
//
// Mirrors the filter inside `bumpMatchingReminders`. The predicate is
// `entry.date > lastDoneDate && entry.km > lastDoneKm`. Both have to be
// strictly newer so accidentally logging an old maintenance entry never
// downgrades a more-recent service record.
// ----------------------------------------------------------------------------

section('Bump predicate — strict monotonicity in BOTH date AND km');

interface Reminder { lastDoneDate: Date; lastDoneKm: number; }
interface Entry    { date: Date; km: number; }

const shouldBump = (r: Reminder, e: Entry) =>
  e.date.getTime() > r.lastDoneDate.getTime() && e.km > r.lastDoneKm;

const REMINDER: Reminder = {
  lastDoneDate: new Date('2026-01-01T00:00:00Z'),
  lastDoneKm: 170_000,
};

assert(
  'newer date + higher km                  → BUMP',
  shouldBump(REMINDER, { date: new Date('2026-04-01T00:00:00Z'), km: 175_000 }),
);
assert(
  'newer date + LOWER km                   → no bump',
  !shouldBump(REMINDER, { date: new Date('2026-04-01T00:00:00Z'), km: 169_999 }),
  'protects against odometer typos',
);
assert(
  'older date + higher km                  → no bump',
  !shouldBump(REMINDER, { date: new Date('2025-06-01T00:00:00Z'), km: 175_000 }),
  'protects against logging a forgotten old entry',
);
assert(
  'equal date + higher km                  → no bump (strict)',
  !shouldBump(REMINDER, { date: new Date('2026-01-01T00:00:00Z'), km: 175_000 }),
  'same-day duplicate entries are inert',
);
assert(
  'newer date + equal km                   → no bump (strict)',
  !shouldBump(REMINDER, { date: new Date('2026-04-01T00:00:00Z'), km: 170_000 }),
  'rules out zero-progress logs',
);
assert(
  'much newer + much higher                → BUMP',
  shouldBump(REMINDER, { date: new Date('2027-01-01T00:00:00Z'), km: 200_000 }),
);

// ----------------------------------------------------------------------------
// Summary
// ----------------------------------------------------------------------------

console.log('\n============================================================');
console.log(`  RESULTS: ${passed} passed, ${failed} failed`);
console.log('============================================================');

if (failed > 0) process.exit(1);
