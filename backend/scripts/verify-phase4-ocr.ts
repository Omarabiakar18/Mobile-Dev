/**
 * Phase 4 OCR sanity checks — runs `parseFieldsWithRegex` against three
 * hand-crafted receipt strings and asserts the extracted fields. No Vision
 * call, no LLM, no DB writes. Documents-as-code for the spec §7 regex
 * contract.
 *
 * Run with: cd backend && npx tsx scripts/verify-phase4-ocr.ts
 *
 * Stub env vars BEFORE importing modules — `services/llm.ts` (transitively
 * pulled in by `ocr-parse.ts`) parses env at import time. We never call the
 * LLM here, so empty stubs are fine; they just need to satisfy zod.
 */
process.env.DATABASE_URL ??= 'postgresql://stub:stub@localhost:5432/stub';
process.env.JWT_ACCESS_SECRET ??= 'stub-access-secret-1234567890';
process.env.JWT_REFRESH_SECRET ??= 'stub-refresh-secret-1234567890';

import { parseFieldsWithRegex } from '../src/services/ocr-parse';

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

// ---------------------------------------------------------------------------
console.log('\n[1] USD-only English receipt — all fields populated');
{
  // Plain-English Lebanese-style USD receipt. Every field expected to hit.
  const rawText = [
    'TOTAL Energy Station',
    'Jounieh, Lebanon',
    'Date: 28/04/2026  14:32',
    '',
    'Gasoline 95',
    '24.56 L  @ $1.25 /L',
    'TOTAL: $30.70',
    'Thank you for your visit',
  ].join('\n');

  const r = parseFieldsWithRegex(rawText);
  assertEq('liters', r.fields.liters, 24.56, 0.001);
  assertEq('pricePerLiter', r.fields.pricePerLiter, 1.25, 0.001);
  assertEq('totalCost', r.fields.totalCost, 30.7, 0.01);
  assertEq('date', r.fields.date, '2026-04-28');
  assertTrue(
    'station looks like TOTAL',
    typeof r.fields.station === 'string' && /total/i.test(r.fields.station),
  );
  // Confidence on every populated field should be 1.
  assertEq('confidence.liters', r.confidence.liters, 1);
  assertEq('confidence.pricePerLiter', r.confidence.pricePerLiter, 1);
  assertEq('confidence.totalCost', r.confidence.totalCost, 1);
  assertEq('confidence.date', r.confidence.date, 1);
}

// ---------------------------------------------------------------------------
console.log('\n[2] Mixed Arabic / French Lebanese-style receipt');
{
  // European decimal commas, French station name, Arabic header line. The
  // regex normalises commas → dots and ignores the Arabic glyphs, so we
  // still expect the numeric fields to hit. Station-guessing should walk
  // past the Arabic line (no ASCII letters) and land on the French name.
  const rawText = [
    'محطة المدكو',
    'STATION MEDCO Beyrouth',
    '01/03/2026 09:15',
    '',
    'Essence 98',
    '32,40 LT',
    '0,98 USD/LT',
    'TOTAL  31,75 USD',
  ].join('\n');

  const r = parseFieldsWithRegex(rawText);
  assertEq('liters', r.fields.liters, 32.4, 0.01);
  assertEq('pricePerLiter', r.fields.pricePerLiter, 0.98, 0.001);
  assertEq('totalCost', r.fields.totalCost, 31.75, 0.01);
  assertEq('date', r.fields.date, '2026-03-01');
  assertTrue(
    'station includes MEDCO',
    typeof r.fields.station === 'string' && /medco/i.test(r.fields.station),
  );
}

// ---------------------------------------------------------------------------
console.log('\n[3] Sparse receipt — only total line is readable');
{
  // Faded receipt: only the bottom total made it through OCR. Liters / price /
  // station / date should all be null with confidence 0; total should still
  // hit via the $-prefix branch.
  const rawText = [
    '##############',
    '   $42.00',
    '##############',
  ].join('\n');

  const r = parseFieldsWithRegex(rawText);
  assertEq('liters', r.fields.liters, null);
  assertEq('pricePerLiter', r.fields.pricePerLiter, null);
  assertEq('totalCost', r.fields.totalCost, 42, 0.01);
  assertEq('station', r.fields.station, null);
  assertEq('date', r.fields.date, null);

  assertEq('confidence.liters', r.confidence.liters, 0);
  assertEq('confidence.pricePerLiter', r.confidence.pricePerLiter, 0);
  assertEq('confidence.totalCost', r.confidence.totalCost, 1);
  assertEq('confidence.station', r.confidence.station, 0);
  assertEq('confidence.date', r.confidence.date, 0);
}

// ---------------------------------------------------------------------------
console.log('\n[4] Empty raw text — every field null, every confidence zero');
{
  const r = parseFieldsWithRegex('');
  assertEq('liters', r.fields.liters, null);
  assertEq('pricePerLiter', r.fields.pricePerLiter, null);
  assertEq('totalCost', r.fields.totalCost, null);
  assertEq('station', r.fields.station, null);
  assertEq('date', r.fields.date, null);
  assertEq('confidence.totalCost', r.confidence.totalCost, 0);
}

// ---------------------------------------------------------------------------

console.log(`\n${'='.repeat(60)}`);
console.log(`  RESULTS: ${passed} passed, ${failed} failed`);
console.log('='.repeat(60));
if (failed > 0) process.exit(1);
process.exit(0);
