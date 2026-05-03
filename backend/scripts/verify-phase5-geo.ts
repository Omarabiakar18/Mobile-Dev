/**
 * Phase 5 geofencing math sanity checks — runs `haversineKm` against three
 * hand-picked coordinate pairs with known real-world distances. Mirrors the
 * style of `verify-phase3-math.ts`. No DB writes, no network.
 *
 * Run with: `cd backend && npx tsx scripts/verify-phase5-geo.ts`
 *
 * Stub env vars BEFORE importing modules — `lib/prisma.ts` (transitively
 * pulled in by the service) parses env at import time and would fail
 * without these. We never actually touch a DB here; haversineKm is pure
 * math, but the import path drags in the env loader.
 */
process.env.DATABASE_URL ??= 'postgresql://stub:stub@localhost:5432/stub';
process.env.JWT_ACCESS_SECRET ??= 'stub-access-secret-1234567890';
process.env.JWT_REFRESH_SECRET ??= 'stub-refresh-secret-1234567890';

import { haversineKm } from '../src/modules/gas-stations/gas-stations.service';

let passed = 0;
let failed = 0;

function assertNear(
  label: string,
  actual: number,
  expected: number,
  toleranceKm: number,
): void {
  const ok = Math.abs(actual - expected) <= toleranceKm;
  if (ok) {
    passed += 1;
    console.log(
      `  PASS  ${label}  ->  ${actual.toFixed(2)} km (expected ~${expected} km, ±${toleranceKm})`,
    );
  } else {
    failed += 1;
    console.error(
      `  FAIL  ${label}\n        expected: ${expected} km (±${toleranceKm})\n        actual:   ${actual.toFixed(2)} km`,
    );
  }
}

// Beirut city center (approx Place de l'Étoile).
const BEIRUT = { lat: 33.8959, lng: 35.4784 };
// Jounieh waterfront.
const JOUNIEH = { lat: 33.9806, lng: 35.6174 };
// Tripoli (city center).
const TRIPOLI = { lat: 34.4367, lng: 35.8497 };

// Note: the spec mentions Beirut→Jounieh as "~18 km" — that's the road
// distance. Haversine returns straight-line, which lands ~16 km. Same for
// Beirut→Tripoli (~85 km road, ~69 km straight). We assert against the
// straight-line truth here since that's what haversineKm computes; the
// tolerance is generous (±3 km) since haversine itself has small error too.

console.log('\n[1] haversineKm — Beirut to Jounieh (~16 km straight-line)');
{
  const d = haversineKm(BEIRUT.lat, BEIRUT.lng, JOUNIEH.lat, JOUNIEH.lng);
  assertNear('Beirut → Jounieh', d, 16, 2);
}

console.log('\n[2] haversineKm — Beirut to Tripoli (~69 km straight-line)');
{
  const d = haversineKm(BEIRUT.lat, BEIRUT.lng, TRIPOLI.lat, TRIPOLI.lng);
  assertNear('Beirut → Tripoli', d, 69, 2);
}

console.log('\n[3] haversineKm — identical points → 0 km');
{
  const d = haversineKm(BEIRUT.lat, BEIRUT.lng, BEIRUT.lat, BEIRUT.lng);
  assertNear('Beirut → Beirut', d, 0, 0.001);
}

console.log(`\n${'='.repeat(60)}`);
console.log(`  RESULTS: ${passed} passed, ${failed} failed`);
console.log('='.repeat(60));
if (failed > 0) process.exit(1);
process.exit(0);
