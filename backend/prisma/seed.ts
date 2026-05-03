/**
 * Database seed — runs via `npm run db:seed` (which invokes `tsx prisma/seed.ts`).
 *
 * Idempotent by design: every upsert is keyed by a stable natural key, so
 * running the seed twice produces the same database state. Add new seed
 * blocks here as the demo grows (per spec §10) — the gas-station block
 * below is Phase 5.
 *
 * Run: `cd backend && npx tsx prisma/seed.ts`
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Ten real, recognizable gas stations across greater Beirut. Coordinates
 * are accurate to within a few hundred meters (well under the spec's
 * ±0.01° tolerance — see §8). Brands deliberately mixed (Total / Medco /
 * IPT / Hypco) so the demo "list of nearby stations" looks realistic
 * rather than uniform.
 *
 * Order is roughly south → north along the coast, then inland — useful
 * when eyeballing the seed output during demo prep.
 */
const GAS_STATIONS: Array<{
  name: string;
  city: string;
  latitude: number;
  longitude: number;
}> = [
  { name: 'Total Hazmieh',         city: 'Hazmieh',        latitude: 33.8552, longitude: 35.5380 },
  { name: 'Medco Achrafieh',       city: 'Achrafieh',      latitude: 33.8869, longitude: 35.5198 },
  { name: 'IPT Beirut Port',       city: 'Beirut',         latitude: 33.9011, longitude: 35.5189 },
  { name: 'Hypco Bourj Hammoud',   city: 'Bourj Hammoud',  latitude: 33.8929, longitude: 35.5408 },
  { name: 'Total Dora',            city: 'Dora',           latitude: 33.8959, longitude: 35.5547 },
  { name: 'Medco Bauchrieh',       city: 'Bauchrieh',      latitude: 33.8861, longitude: 35.5567 },
  { name: 'IPT Zalka',             city: 'Zalka',          latitude: 33.9023, longitude: 35.5739 },
  { name: 'Hypco Antelias',        city: 'Antelias',       latitude: 33.9136, longitude: 35.5878 },
  { name: 'Total Jounieh',         city: 'Jounieh',        latitude: 33.9806, longitude: 35.6174 },
  { name: 'Medco Adma',            city: 'Adma',           latitude: 34.0078, longitude: 35.6361 },
];

/**
 * Seeds the GasStation table. Idempotent: keyed by `name` (the schema has
 * no unique constraint on (lat,lng), and station names are distinct in our
 * curated list). Uses raw findFirst+update/create rather than `upsert` so
 * we don't need a schema migration to add a `@@unique` constraint.
 */
async function seedGasStations(): Promise<number> {
  for (const s of GAS_STATIONS) {
    const existing = await prisma.gasStation.findFirst({
      where: { name: s.name },
    });
    if (existing) {
      await prisma.gasStation.update({
        where: { id: existing.id },
        data: {
          latitude: s.latitude,
          longitude: s.longitude,
          city: s.city,
        },
      });
    } else {
      await prisma.gasStation.create({ data: s });
    }
  }
  return GAS_STATIONS.length;
}

async function main() {
  const stationCount = await seedGasStations();
  // eslint-disable-next-line no-console
  console.log(`Seeded ${stationCount} gas stations`);
}

main()
  .catch((err) => {
    // eslint-disable-next-line no-console
    console.error('Seed failed:', err);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
