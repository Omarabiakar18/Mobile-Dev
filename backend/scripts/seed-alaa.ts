/**
 * Seed Alaa's account (alaahsn.gms@gmail.com) with ~25 realistic fuel entries
 * over the last ~6 months on their first car. Picks realistic numbers based
 * on the car's fuelType and tankSize so predict-next and avgKmPerDay produce
 * meaningful values.
 *
 * Idempotent: wipes existing fuel entries on the chosen car before inserting.
 * Run: cd backend && npx tsx scripts/seed-alaa.ts
 */
import { Prisma } from '@prisma/client';
import { prisma } from '../src/lib/prisma';
import { recomputeAvgKmPerDay } from '../src/lib/avg-km-per-day';

const EMAIL = 'alaahsn.gms@gmail.com';

const STATIONS = [
  'TOTAL Hazmieh',
  'Medco Achrafieh',
  'IPT Jounieh',
  'Hypco Antelias',
  'TOTAL Dora',
  'Medco Zalka',
];

function randBetween(min: number, max: number) {
  return Math.random() * (max - min) + min;
}

function round(n: number, decimals: number) {
  const f = 10 ** decimals;
  return Math.round(n * f) / f;
}

async function main() {
  const user = await prisma.user.findUnique({
    where: { email: EMAIL },
    include: { cars: { orderBy: { createdAt: 'asc' } } },
  });
  if (!user) throw new Error(`User not found: ${EMAIL}`);
  if (user.cars.length === 0) throw new Error('User has no cars yet — add one in the app first.');

  const car = user.cars[0];
  console.log(`Seeding fuel for: ${car.year} ${car.make} ${car.model} (id=${car.id})`);
  console.log(`  tankSize=${car.tankSize}, fuelType=${car.fuelType}, currentKm=${car.currentKm}`);

  // Wipe existing entries on this car (idempotency)
  const deleted = await prisma.fuelEntry.deleteMany({ where: { carId: car.id } });
  console.log(`  cleared ${deleted.count} existing fuel entries`);

  // Realistic profile per fuel type
  const isDiesel = car.fuelType === 'diesel';
  const consumptionPer100km = isDiesel ? randBetween(6.5, 7.5) : randBetween(8.5, 10.5);
  const pricePerLiter = isDiesel ? randBetween(0.95, 1.05) : randBetween(1.05, 1.15);
  const tankSize = Number(car.tankSize);

  // 25 entries over ~180 days, ~42 km/day average → ~7,560 km span
  const entriesCount = 25;
  const daysSpan = 180;
  const today = new Date();
  const startDate = new Date(today.getTime() - daysSpan * 86400000);

  // End the run with currentKm in the last entry; backfill odometer working
  // backward so the most recent fuel entry odometer is just under car.currentKm.
  const finalOdometer = Number(car.currentKm) - randBetween(50, 200); // leave a small km gap
  const startOdometer = finalOdometer - (daysSpan * 42); // ~42 km/day default

  type Pending = {
    date: Date;
    odometer: number;
    isFullTank: boolean;
    station: string;
  };

  const pending: Pending[] = [];
  for (let i = 0; i < entriesCount; i++) {
    // Spread the dates roughly evenly with a touch of jitter
    const ratio = i / (entriesCount - 1);
    const dateMs = startDate.getTime() + ratio * daysSpan * 86400000 + randBetween(-2, 2) * 86400000;
    const odo = startOdometer + ratio * (finalOdometer - startOdometer) + randBetween(-30, 30);
    pending.push({
      date: new Date(dateMs),
      odometer: Math.round(odo),
      // ~80% full tank, 20% partial
      isFullTank: Math.random() < 0.8,
      station: STATIONS[Math.floor(Math.random() * STATIONS.length)],
    });
  }

  // Sort ascending by odometer to keep things monotonic
  pending.sort((a, b) => a.odometer - b.odometer);

  // Build fuel entries with realistic liters between consecutive entries
  const inserts: Prisma.FuelEntryCreateManyInput[] = [];
  let prevOdo: number | null = null;
  for (let i = 0; i < pending.length; i++) {
    const p = pending[i];
    let liters: number;
    if (prevOdo === null) {
      // First entry: assume a near-full fill (random 80-100% of tank)
      liters = tankSize * randBetween(0.8, 1.0);
    } else {
      const kmSpan = p.odometer - prevOdo;
      const used = (kmSpan * consumptionPer100km) / 100;
      // Add small jitter (±5%) to vary fills
      liters = used * randBetween(0.95, 1.05);
      // Cap at tank size; floor at 5L
      liters = Math.min(Math.max(liters, 5), tankSize);
    }
    const litersRounded = round(liters, 2);
    const priceRounded = round(pricePerLiter * randBetween(0.97, 1.03), 3);
    const total = round(litersRounded * priceRounded, 2);

    inserts.push({
      carId: car.id,
      date: p.date,
      odometer: p.odometer,
      liters: new Prisma.Decimal(litersRounded),
      pricePerLiter: new Prisma.Decimal(priceRounded),
      totalCost: new Prisma.Decimal(total),
      fuelType: car.fuelType,
      station: p.station,
      isFullTank: p.isFullTank,
    });

    prevOdo = p.odometer;
  }

  // Insert and recompute avgKmPerDay in a transaction
  const result = await prisma.$transaction(async (tx) => {
    const r = await tx.fuelEntry.createMany({ data: inserts });
    await recomputeAvgKmPerDay(car.id, tx);
    return r;
  });
  console.log(`  inserted ${result.count} fuel entries`);

  // Re-read the car to confirm avgKmPerDay
  const refreshed = await prisma.car.findUnique({ where: { id: car.id } });
  console.log(`  avgKmPerDay now: ${refreshed?.avgKmPerDay ?? 'null'}`);

  // Print a quick summary
  const stats = await prisma.fuelEntry.aggregate({
    where: { carId: car.id },
    _sum: { liters: true, totalCost: true },
    _min: { date: true, odometer: true },
    _max: { date: true, odometer: true },
  });
  const kmSpan = Number(stats._max.odometer ?? 0) - Number(stats._min.odometer ?? 0);
  console.log(`  totals: ${stats._sum.liters} L over ${kmSpan} km, total spend $${stats._sum.totalCost}`);
  console.log('Done.');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
