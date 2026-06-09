/**
 * Seed Omar's account (abiakaromar18@outlook.com) with a full, demo-ready
 * dataset that exercises every feature in the spec:
 *   - 3 multi-car profiles (2 gasoline, 1 diesel) WITH photos
 *   - Fuel history over ~6 months on every car → predict-next confidence='ok'
 *   - Maintenance logs (oil / tires / brakes / filter / battery)
 *   - Documents (insurance / mécanique / registration) with varied expiry so
 *     each car triggers a different home banner severity (expired / urgent)
 *   - Service reminders tuned so each car has an overdue + a due-soon entry
 *
 * Idempotent: keyed on (userId, plate); child rows are wiped per car before
 * re-insert. Does NOT touch the user's password if the account already exists.
 *
 * Run: cd backend && npx tsx scripts/seed-omar.ts
 */
import fs from 'node:fs';
import path from 'node:path';

import { Prisma } from '@prisma/client';
import bcrypt from 'bcryptjs';

import { prisma } from '../src/lib/prisma';
import { recomputeAvgKmPerDay } from '../src/lib/avg-km-per-day';

const EMAIL = 'abiakaromar18@outlook.com';
const FALLBACK_PASSWORD = 'Garage1234!'; // only used if the account doesn't exist yet

const DAY = 86_400_000;
const NOW = Date.now();

const STATIONS = [
  'TOTAL Hazmieh', 'Medco Achrafieh', 'IPT Jounieh', 'Hypco Antelias',
  'TOTAL Dora', 'Medco Zalka', 'TOTAL Jounieh', 'Hypco Bauchrieh',
];

function rand(min: number, max: number) { return Math.random() * (max - min) + min; }
function round(n: number, d: number) { const f = 10 ** d; return Math.round(n * f) / f; }
function daysAgo(d: number) { return new Date(NOW - d * DAY); }
function inDays(d: number) { return new Date(NOW + d * DAY); }

// ---------------------------------------------------------------------------
// Car definitions. `photoFile` is set as photoUrl only if the file actually
// exists under backend/uploads/cars (downloaded separately, best-effort).
// ---------------------------------------------------------------------------
interface CarDef {
  make: string; model: string; year: number; plate: string; color: string;
  fuelType: 'gasoline' | 'diesel'; tankSize: number;
  photoFile: string;
  fuel: { startOdo: number; count: number; days: number; kmPerDay: number; consL100: number; priceMin: number; priceMax: number };
  gapToCurrentKm: number;
  maintenance: { daysAgo: number; km: number; type: string; description: string; cost: number }[];
  // documents/reminders are built relative to currentKm (computed after fuel)
  documents: (currentKm: number) => { type: string; expiryDate: Date; issuedDate?: Date; issuer: string }[];
  reminders: (currentKm: number) => { serviceType: string; lastDoneKm: number; daysAgoLastDone: number; intervalKm: number | null; intervalMonths: number | null }[];
}

const CARS: CarDef[] = [
  // ---- Car 1: Kia Sportage (gasoline) — richest history. Banner: mécanique due in 9d.
  {
    make: 'Kia', model: 'Sportage', year: 2019, plate: 'G 145872', color: 'Graphite',
    fuelType: 'gasoline', tankSize: 62, photoFile: 'seed-car-1.jpg',
    fuel: { startOdo: 84_000, count: 14, days: 185, kmPerDay: 45, consL100: 9.4, priceMin: 1.30, priceMax: 1.50 },
    gapToCurrentKm: 80,
    maintenance: [
      { daysAgo: 250, km: 84_200, type: 'oil',     description: 'Oil + filter change',    cost: 65 },
      { daysAgo: 200, km: 86_500, type: 'tires',   description: 'Tire rotation',          cost: 25 },
      { daysAgo: 150, km: 88_900, type: 'brakes',  description: 'Front brake pads',       cost: 175 },
      { daysAgo:  95, km: 90_500, type: 'oil',     description: 'Oil + filter change',    cost: 65 },
      { daysAgo:  55, km: 91_300, type: 'filter',  description: 'Air + cabin filter',     cost: 35 },
      { daysAgo:  18, km: 92_000, type: 'battery', description: 'Battery test + clean',   cost: 0  },
    ],
    documents: () => [
      { type: 'insurance',    expiryDate: inDays(205), issuedDate: daysAgo(160), issuer: 'Bankers Assurance' },
      { type: 'registration', expiryDate: inDays(150), issuedDate: daysAgo(215), issuer: 'NTVB Lebanon' },
      { type: 'mecanique',    expiryDate: inDays(9),   issuedDate: daysAgo(356), issuer: 'NTVB Lebanon' }, // urgent banner
    ],
    reminders: () => [
      { serviceType: 'Oil change',        lastDoneKm: 86_500, daysAgoLastDone: 110, intervalKm: 5_000, intervalMonths: 4 },  // overdue
      { serviceType: 'Brake check',       lastDoneKm: 88_900, daysAgoLastDone: 150, intervalKm: null,  intervalMonths: 5 },  // due ~now
      { serviceType: 'Tire rotation',     lastDoneKm: 87_500, daysAgoLastDone: 200, intervalKm: 10_000, intervalMonths: 12 }, // far
      { serviceType: 'Annual inspection', lastDoneKm: 88_900, daysAgoLastDone: 150, intervalKm: null,  intervalMonths: 12 }, // far
    ],
  },
  // ---- Car 2: VW Golf (diesel). Banner: insurance EXPIRED (red) + registration soon.
  {
    make: 'Volkswagen', model: 'Golf', year: 2020, plate: 'J 230918', color: 'White',
    fuelType: 'diesel', tankSize: 50, photoFile: 'seed-car-2.jpg',
    fuel: { startOdo: 66_400, count: 12, days: 175, kmPerDay: 30, consL100: 6.9, priceMin: 1.10, priceMax: 1.25 },
    gapToCurrentKm: 60,
    maintenance: [
      { daysAgo: 220, km: 63_000, type: 'oil',    description: 'Oil + filter change', cost: 70 },
      { daysAgo: 140, km: 66_500, type: 'brakes', description: 'Rear brake pads',     cost: 160 },
      { daysAgo:  60, km: 68_500, type: 'oil',    description: 'Oil + filter change', cost: 70 },
      { daysAgo:  30, km: 70_000, type: 'filter', description: 'Diesel fuel filter',  cost: 40 },
    ],
    documents: () => [
      { type: 'insurance',    expiryDate: daysAgo(12), issuedDate: daysAgo(377), issuer: 'AXA Middle East' }, // EXPIRED -> red banner
      { type: 'mecanique',    expiryDate: inDays(120), issuedDate: daysAgo(245), issuer: 'NTVB Lebanon' },
      { type: 'registration', expiryDate: inDays(25),  issuedDate: daysAgo(340), issuer: 'NTVB Lebanon' },  // also within window
    ],
    reminders: () => [
      { serviceType: 'Oil change',    lastDoneKm: 68_500, daysAgoLastDone: 60,  intervalKm: 5_000, intervalMonths: 6 },  // due ~soon
      { serviceType: 'Tire rotation', lastDoneKm: 64_000, daysAgoLastDone: 200, intervalKm: null,  intervalMonths: 6 },  // overdue (calendar)
      { serviceType: 'Air filter',    lastDoneKm: 66_000, daysAgoLastDone: 120, intervalKm: 15_000, intervalMonths: 18 }, // far
    ],
  },
  // ---- Car 3: Toyota Corolla (gasoline) — older. Banner: registration due in 13d.
  {
    make: 'Toyota', model: 'Corolla', year: 2017, plate: 'B 487123', color: 'Silver',
    fuelType: 'gasoline', tankSize: 50, photoFile: 'seed-car-3.jpg',
    fuel: { startOdo: 127_000, count: 13, days: 180, kmPerDay: 38, consL100: 8.2, priceMin: 1.30, priceMax: 1.48 },
    gapToCurrentKm: 90,
    maintenance: [
      { daysAgo: 210, km: 126_200, type: 'oil',     description: 'Oil + filter change',  cost: 55 },
      { daysAgo: 150, km: 128_000, type: 'tires',   description: 'Tire rotation + balance', cost: 30 },
      { daysAgo:  70, km: 131_000, type: 'oil',     description: 'Oil + filter change',  cost: 55 },
      { daysAgo:  20, km: 133_500, type: 'battery', description: 'Battery replacement',  cost: 90 },
    ],
    documents: () => [
      { type: 'registration', expiryDate: inDays(13),  issuedDate: daysAgo(352), issuer: 'NTVB Lebanon' },  // urgent banner
      { type: 'insurance',    expiryDate: inDays(60),  issuedDate: daysAgo(305), issuer: 'Fidelity Assurance' }, // outside 30d window
      { type: 'mecanique',    expiryDate: inDays(300), issuedDate: daysAgo(65),  issuer: 'NTVB Lebanon' },
    ],
    reminders: () => [
      { serviceType: 'Oil change',    lastDoneKm: 128_000, daysAgoLastDone: 130, intervalKm: 5_000, intervalMonths: 5 }, // overdue
      { serviceType: 'Battery check', lastDoneKm: 133_500, daysAgoLastDone: 20,  intervalKm: null,  intervalMonths: 24 }, // far
    ],
  },
];

// ---------------------------------------------------------------------------
function genFuel(def: CarDef): { entries: Prisma.FuelEntryCreateManyInput[]; lastOdo: number } {
  const { startOdo, count, days, kmPerDay, consL100, priceMin, priceMax } = def.fuel;
  const span = days * kmPerDay;
  const step = span / (count - 1);

  // Build strictly-increasing odometers + descending daysAgo (oldest first).
  const rows: { date: Date; odo: number; full: boolean; station: string }[] = [];
  let prev = -1;
  for (let i = 0; i < count; i++) {
    const t = i / (count - 1);
    let odo = Math.round(startOdo + i * step + rand(-step * 0.18, step * 0.18));
    if (odo <= prev) odo = prev + 5; // enforce monotonic
    prev = odo;
    const dAgo = days * (1 - t) + 3 * t; // from `days` ago down to ~3 days ago
    rows.push({
      date: daysAgo(dAgo),
      odo,
      full: i === 0 || i === count - 1 ? true : Math.random() < 0.75, // ~75% full, ends/starts full
      station: STATIONS[Math.floor(Math.random() * STATIONS.length)],
    });
  }

  const entries: Prisma.FuelEntryCreateManyInput[] = [];
  let prevOdo: number | null = null;
  for (const r of rows) {
    let liters: number;
    if (prevOdo === null) {
      liters = def.tankSize * rand(0.82, 0.98);
    } else {
      const km = r.odo - prevOdo;
      liters = (km * consL100) / 100 * rand(0.95, 1.06);
      liters = Math.min(Math.max(liters, 8), def.tankSize);
    }
    const litersR = round(liters, 2);
    const priceR = round(rand(priceMin, priceMax), 3);
    entries.push({
      carId: '', // filled after the car is created
      date: r.date,
      odometer: r.odo,
      liters: new Prisma.Decimal(litersR),
      pricePerLiter: new Prisma.Decimal(priceR),
      totalCost: new Prisma.Decimal(round(litersR * priceR, 2)),
      fuelType: def.fuelType,
      station: r.station,
      isFullTank: r.full,
    });
    prevOdo = r.odo;
  }
  return { entries, lastOdo: prev };
}

async function main() {
  /* eslint-disable no-console */
  // 1) Resolve the user WITHOUT overwriting their password if it already exists.
  let user = await prisma.user.findUnique({ where: { email: EMAIL } });
  if (!user) {
    const passwordHash = await bcrypt.hash(FALLBACK_PASSWORD, 12);
    user = await prisma.user.create({
      data: { email: EMAIL, name: 'Omar Abi Akar', phone: '+961 71 000 000', passwordHash },
    });
    console.log(`Created user ${EMAIL} (password: ${FALLBACK_PASSWORD})`);
  } else {
    console.log(`Found existing user ${EMAIL} — leaving password untouched.`);
  }

  const uploadsCars = path.resolve(process.cwd(), 'uploads', 'cars');

  for (const def of CARS) {
    // 2) Upsert car by (userId, plate).
    const existing = await prisma.car.findFirst({ where: { userId: user.id, plate: def.plate } });
    const photoPath = path.join(uploadsCars, def.photoFile);
    const photoUrl = fs.existsSync(photoPath) ? `/uploads/cars/${def.photoFile}` : null;

    const baseData = {
      userId: user.id,
      make: def.make, model: def.model, year: def.year, plate: def.plate, color: def.color,
      fuelType: def.fuelType, tankSize: new Prisma.Decimal(def.tankSize),
      photoUrl,
    };

    // Generate fuel first so currentKm can sit just above the latest odometer.
    const { entries, lastOdo } = genFuel(def);
    const currentKm = lastOdo + def.gapToCurrentKm;

    const car = existing
      ? await prisma.car.update({ where: { id: existing.id }, data: { ...baseData, currentKm } })
      : await prisma.car.create({ data: { ...baseData, currentKm } });

    // 3) Wipe child rows for idempotency.
    await prisma.$transaction([
      prisma.fuelEntry.deleteMany({ where: { carId: car.id } }),
      prisma.maintenanceEntry.deleteMany({ where: { carId: car.id } }),
      prisma.document.deleteMany({ where: { carId: car.id } }),
      prisma.serviceReminder.deleteMany({ where: { carId: car.id } }),
    ]);

    // 4) Fuel + avg recompute.
    await prisma.fuelEntry.createMany({ data: entries.map((e) => ({ ...e, carId: car.id })) });
    await recomputeAvgKmPerDay(car.id);

    // 5) Maintenance.
    await prisma.maintenanceEntry.createMany({
      data: def.maintenance.map((m) => ({
        carId: car.id,
        date: daysAgo(m.daysAgo),
        km: m.km,
        type: m.type as Prisma.MaintenanceEntryCreateManyInput['type'],
        description: m.description,
        cost: new Prisma.Decimal(m.cost),
      })),
    });

    // 6) Documents.
    await prisma.document.createMany({
      data: def.documents(currentKm).map((d) => ({
        carId: car.id,
        type: d.type as Prisma.DocumentCreateManyInput['type'],
        expiryDate: d.expiryDate,
        issuedDate: d.issuedDate ?? null,
        issuer: d.issuer,
        fileUrl: `/uploads/demo/${d.type}.pdf`,
      })),
    });

    // 7) Reminders.
    await prisma.serviceReminder.createMany({
      data: def.reminders(currentKm).map((r) => ({
        carId: car.id,
        serviceType: r.serviceType,
        lastDoneKm: r.lastDoneKm,
        lastDoneDate: daysAgo(r.daysAgoLastDone),
        intervalKm: r.intervalKm,
        intervalMonths: r.intervalMonths,
        isActive: true,
      })),
    });

    const refreshed = await prisma.car.findUnique({ where: { id: car.id } });
    console.log(
      `✓ ${def.year} ${def.make} ${def.model} [${def.plate}] currentKm=${currentKm} ` +
      `avgKmPerDay=${refreshed?.avgKmPerDay ?? 'null'} photo=${photoUrl ? 'yes' : 'no'} ` +
      `(fuel=${entries.length}, maint=${def.maintenance.length}, docs=3, reminders=${def.reminders(currentKm).length})`,
    );
  }

  console.log('\nDone. Pull-to-refresh on the tablet to load the data.');
  /* eslint-enable no-console */
}

main()
  .catch((e) => { console.error('Seed failed:', e); process.exit(1); })
  .finally(() => prisma.$disconnect());
