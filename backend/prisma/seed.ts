/**
 * Database seed — runs via `npm run db:seed` (which invokes `tsx prisma/seed.ts`).
 *
 * Idempotent by design: every block is keyed on a stable natural key, so
 * running the seed twice produces the same database state. See spec §10
 * for the demo-data contract.
 *
 * Run: `cd backend && npx tsx prisma/seed.ts`
 *
 * Resulting state after a fresh run:
 *   - 1 demo user (demo@garage.app / demo1234)
 *   - 3 cars (one with rich history, two minimal)
 *   - ~12 fuel entries on the primary car spanning ~6 months, mix of
 *     full-tank and partial — triggers predict-next confidence='ok'
 *   - 6 maintenance records on primary, 2 on secondary
 *   - 4 service reminders with one overdue + one due-in-4-days (red + amber
 *     home-banner triggers)
 *   - 3 documents per primary car: insurance valid, registration valid,
 *     mécanique expiring in 11 days (red banner)
 *   - 10 gas stations near Beirut (Phase 5)
 */
import { promises as fs } from 'fs';
import path from 'path';

import { PrismaClient, Prisma } from '@prisma/client';
import bcrypt from 'bcryptjs';

import { env } from '../src/config/env';
import { recomputeAvgKmPerDay } from '../src/lib/avg-km-per-day';
import { buildDemoPdf } from './demo-pdf';

const prisma = new PrismaClient();

// ---------------------------------------------------------------------------
// Gas stations (Phase 5)
// ---------------------------------------------------------------------------

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

async function seedGasStations(): Promise<number> {
  for (const s of GAS_STATIONS) {
    const existing = await prisma.gasStation.findFirst({ where: { name: s.name } });
    if (existing) {
      await prisma.gasStation.update({
        where: { id: existing.id },
        data: { latitude: s.latitude, longitude: s.longitude, city: s.city },
      });
    } else {
      await prisma.gasStation.create({ data: s });
    }
  }
  return GAS_STATIONS.length;
}

// ---------------------------------------------------------------------------
// Demo user (Phase 6)
// ---------------------------------------------------------------------------

const DEMO_USER = {
  email: 'demo@garage.app',
  name: 'Demo User',
  phone: '+961 70 000 000',
  password: 'demo1234',
};

async function seedDemoUser(): Promise<string> {
  const passwordHash = await bcrypt.hash(DEMO_USER.password, 12);
  const user = await prisma.user.upsert({
    where: { email: DEMO_USER.email },
    create: {
      email: DEMO_USER.email,
      name: DEMO_USER.name,
      phone: DEMO_USER.phone,
      passwordHash,
    },
    update: {
      name: DEMO_USER.name,
      phone: DEMO_USER.phone,
      passwordHash,
    },
  });
  return user.id;
}

// ---------------------------------------------------------------------------
// Demo cars (Phase 6) — keyed by (userId, plate)
// ---------------------------------------------------------------------------

interface DemoCar {
  make: string;
  model: string;
  year: number;
  plate: string;
  color: string;
  currentKm: number;
  fuelType: 'gasoline' | 'diesel';
  tankSize: number;
}

const DEMO_CARS: DemoCar[] = [
  // Primary — gets 6mo of fuel + maint + reminders + docs
  {
    make: 'Range Rover', model: 'Sport', year: 2018, plate: 'B 12345',
    color: 'Black', currentKm: 175_400, fuelType: 'gasoline', tankSize: 85,
  },
  // Secondary — minimal data; useful for the multi-car switcher demo
  {
    make: 'Toyota', model: 'Prius', year: 2020, plate: 'B 24680',
    color: 'White', currentKm: 88_200, fuelType: 'gasoline', tankSize: 43,
  },
  // Tertiary — diesel, also minimal
  {
    make: 'Mercedes', model: 'GLE', year: 2017, plate: 'B 36912',
    color: 'Silver', currentKm: 142_000, fuelType: 'diesel', tankSize: 90,
  },
];

async function seedCarsForUser(userId: string): Promise<{ primary: string; secondary: string; tertiary: string }> {
  const ids: Record<number, string> = {};
  for (let i = 0; i < DEMO_CARS.length; i++) {
    const c = DEMO_CARS[i];
    const existing = await prisma.car.findFirst({ where: { userId, plate: c.plate } });
    const data = {
      userId,
      make: c.make, model: c.model, year: c.year, plate: c.plate, color: c.color,
      currentKm: c.currentKm, fuelType: c.fuelType,
      tankSize: new Prisma.Decimal(c.tankSize),
    } as const;
    const car = existing
      ? await prisma.car.update({ where: { id: existing.id }, data })
      : await prisma.car.create({ data });
    ids[i] = car.id;
  }
  return { primary: ids[0], secondary: ids[1], tertiary: ids[2] };
}

// ---------------------------------------------------------------------------
// Fuel entries (Phase 6) — primary car only
// ---------------------------------------------------------------------------

interface DemoFuelEntry {
  daysAgo: number;
  odometer: number;
  liters: number;
  pricePerLiter: number;
  isFullTank: boolean;
  station: string;
}

/**
 * 12 entries spanning 180 days, ~50 km/day → arrives at currentKm 175400.
 * Mix of full / partial. ~11.6 L/100km consumption (Range Rover Sport-ish).
 * Engineered so predict-next returns confidence='ok'.
 */
const PRIMARY_FUEL: DemoFuelEntry[] = [
  { daysAgo: 175, odometer: 166_400, liters: 70, pricePerLiter: 1.30, isFullTank: true,  station: 'Total Jounieh' },
  { daysAgo: 160, odometer: 167_350, liters: 60, pricePerLiter: 1.32, isFullTank: false, station: 'Total Hazmieh' },
  { daysAgo: 145, odometer: 168_200, liters: 75, pricePerLiter: 1.35, isFullTank: true,  station: 'Total Jounieh' },
  { daysAgo: 130, odometer: 169_100, liters: 70, pricePerLiter: 1.35, isFullTank: true,  station: 'Medco Achrafieh' },
  { daysAgo: 115, odometer: 170_050, liters: 75, pricePerLiter: 1.40, isFullTank: true,  station: 'Total Hazmieh' },
  { daysAgo: 100, odometer: 171_000, liters: 50, pricePerLiter: 1.40, isFullTank: false, station: 'IPT Zalka' },
  { daysAgo:  85, odometer: 171_900, liters: 70, pricePerLiter: 1.42, isFullTank: true,  station: 'Total Jounieh' },
  { daysAgo:  70, odometer: 172_850, liters: 75, pricePerLiter: 1.42, isFullTank: true,  station: 'Hypco Antelias' },
  { daysAgo:  55, odometer: 173_700, liters: 65, pricePerLiter: 1.45, isFullTank: false, station: 'Total Dora' },
  { daysAgo:  40, odometer: 174_500, liters: 70, pricePerLiter: 1.45, isFullTank: true,  station: 'Total Hazmieh' },
  { daysAgo:  20, odometer: 175_100, liters: 80, pricePerLiter: 1.48, isFullTank: true,  station: 'Total Jounieh' },
  { daysAgo:   3, odometer: 175_400, liters: 35, pricePerLiter: 1.48, isFullTank: false, station: 'Medco Achrafieh' },
];

async function seedFuelEntries(carId: string): Promise<number> {
  // Idempotent: wipe existing demo fuel entries for this car, then re-insert.
  await prisma.fuelEntry.deleteMany({ where: { carId } });

  const now = Date.now();
  for (const e of PRIMARY_FUEL) {
    const date = new Date(now - e.daysAgo * 86_400_000);
    const totalCost = Math.round(e.liters * e.pricePerLiter * 100) / 100;
    await prisma.fuelEntry.create({
      data: {
        carId,
        date,
        odometer: e.odometer,
        liters: new Prisma.Decimal(e.liters),
        pricePerLiter: new Prisma.Decimal(e.pricePerLiter),
        totalCost: new Prisma.Decimal(totalCost),
        fuelType: 'gasoline',
        isFullTank: e.isFullTank,
        station: e.station,
      },
    });
  }
  return PRIMARY_FUEL.length;
}

// ---------------------------------------------------------------------------
// Maintenance entries (Phase 6) — primary car
// ---------------------------------------------------------------------------

const PRIMARY_MAINTENANCE = [
  { daysAgo: 240, km: 164_500, type: 'oil',     description: 'Oil + filter change',     cost: 95 },
  { daysAgo: 195, km: 166_000, type: 'tires',   description: 'Tire rotation',           cost: 30 },
  { daysAgo: 150, km: 168_400, type: 'brakes',  description: 'Front brake pads',        cost: 220 },
  { daysAgo: 100, km: 171_200, type: 'oil',     description: 'Oil + filter change',     cost: 95 },
  { daysAgo:  60, km: 172_900, type: 'filter',  description: 'Air filter replacement',  cost: 45 },
  { daysAgo:  20, km: 175_000, type: 'battery', description: 'Battery test + clean',    cost: 0 },
] as const;

async function seedMaintenance(carId: string): Promise<number> {
  await prisma.maintenanceEntry.deleteMany({ where: { carId } });
  const now = Date.now();
  for (const m of PRIMARY_MAINTENANCE) {
    await prisma.maintenanceEntry.create({
      data: {
        carId,
        date: new Date(now - m.daysAgo * 86_400_000),
        km: m.km,
        type: m.type as Prisma.MaintenanceEntryCreateInput['type'],
        description: m.description,
        cost: new Prisma.Decimal(m.cost),
      },
    });
  }
  return PRIMARY_MAINTENANCE.length;
}

// ---------------------------------------------------------------------------
// Service reminders (Phase 6) — designed to populate the dashboard banner
// ---------------------------------------------------------------------------

interface DemoReminder {
  serviceType: string;
  lastDoneKm: number;
  daysAgoLastDone: number;
  intervalKm: number | null;
  intervalMonths: number | null;
}

const PRIMARY_REMINDERS: DemoReminder[] = [
  // Overdue: oil due every 5000km, last at 171_200 → due at 176_200, currentKm 175_400 (close)
  // Plus calendar interval 6mo: lastDone 100 days ago + 6mo (~180d) = 80d future. Pick min → calendar lands later.
  // To make it overdue we tighten the interval:
  { serviceType: 'Oil change',     lastDoneKm: 171_200, daysAgoLastDone: 100, intervalKm: 4_000, intervalMonths: 3 },
  // Due in ~4 days: brake pads, last 150d ago, 6mo calendar = 30d future, but km-based hits sooner with 50 km/day
  { serviceType: 'Brake check',    lastDoneKm: 168_400, daysAgoLastDone: 150, intervalKm: null,  intervalMonths: 5 },
  // Due in ~6 weeks
  { serviceType: 'Tire rotation',  lastDoneKm: 166_000, daysAgoLastDone: 195, intervalKm: 10_000, intervalMonths: 8 },
  // Far future
  { serviceType: 'Annual inspection', lastDoneKm: 168_400, daysAgoLastDone: 150, intervalKm: null, intervalMonths: 12 },
];

async function seedReminders(carId: string): Promise<number> {
  await prisma.serviceReminder.deleteMany({ where: { carId } });
  const now = Date.now();
  for (const r of PRIMARY_REMINDERS) {
    await prisma.serviceReminder.create({
      data: {
        carId,
        serviceType: r.serviceType,
        lastDoneKm: r.lastDoneKm,
        lastDoneDate: new Date(now - r.daysAgoLastDone * 86_400_000),
        intervalKm: r.intervalKm,
        intervalMonths: r.intervalMonths,
        isActive: true,
      },
    });
  }
  return PRIMARY_REMINDERS.length;
}

// ---------------------------------------------------------------------------
// Documents (Phase 6) — one expiring soon to trigger the red banner
// ---------------------------------------------------------------------------

const PRIMARY_DOCUMENTS = [
  { type: 'insurance',    daysToExpiry: 165, issuer: 'Bankers Assurance', label: 'Insurance' },
  { type: 'registration', daysToExpiry: 220, issuer: 'NTVB Lebanon',      label: 'Registration' },
  { type: 'mecanique',    daysToExpiry: 11,  issuer: 'NTVB Lebanon',      label: 'Mecanique' }, // <-- red banner trigger
] as const;

/**
 * Materialize the stub PDF blobs the seeded documents point at. The mobile
 * "Open file" button launches `/uploads/demo/<type>.pdf`, so these files must
 * exist on disk — otherwise express.static returns a 404 that the error
 * handler surfaces as "Internal server error". We synthesize a tiny valid PDF
 * per type rather than committing binaries to git.
 */
async function writeDemoDocAssets(): Promise<void> {
  const dir = path.resolve(env.UPLOADS_DIR, 'demo');
  await fs.mkdir(dir, { recursive: true });
  for (const d of PRIMARY_DOCUMENTS) {
    const pdf = buildDemoPdf(`Garage Demo - ${d.label}`, `Issued by ${d.issuer}`);
    await fs.writeFile(path.join(dir, `${d.type}.pdf`), pdf);
  }
}

async function seedDocuments(carId: string): Promise<number> {
  await prisma.document.deleteMany({ where: { carId } });
  const now = Date.now();
  for (const d of PRIMARY_DOCUMENTS) {
    await prisma.document.create({
      data: {
        carId,
        type: d.type as Prisma.DocumentCreateInput['type'],
        expiryDate: new Date(now + d.daysToExpiry * 86_400_000),
        // Points at a stub blob materialized by writeDemoDocAssets() so the
        // mobile "Open file" button renders a real (placeholder) PDF.
        fileUrl: `/uploads/demo/${d.type}.pdf`,
        issuer: d.issuer,
      },
    });
  }
  return PRIMARY_DOCUMENTS.length;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  /* eslint-disable no-console */
  const stationCount = await seedGasStations();
  console.log(`Seeded ${stationCount} gas stations`);

  const userId = await seedDemoUser();
  console.log(`Seeded demo user: ${DEMO_USER.email}`);

  const { primary, secondary, tertiary } = await seedCarsForUser(userId);
  console.log(`Seeded 3 cars (primary=${primary})`);

  const fuelCount = await seedFuelEntries(primary);
  console.log(`Seeded ${fuelCount} fuel entries on primary`);

  // Triggers Car.avgKmPerDay recompute now that fuel history exists.
  await recomputeAvgKmPerDay(primary);
  console.log(`Recomputed avgKmPerDay for primary`);

  const maintCount = await seedMaintenance(primary);
  console.log(`Seeded ${maintCount} maintenance entries on primary`);

  const reminderCount = await seedReminders(primary);
  console.log(`Seeded ${reminderCount} service reminders on primary`);

  const docCount = await seedDocuments(primary);
  console.log(`Seeded ${docCount} documents on primary`);

  await writeDemoDocAssets();
  console.log(`Wrote ${PRIMARY_DOCUMENTS.length} demo document PDFs to uploads/demo/`);

  console.log('\nDemo data ready.');
  console.log(`  email:    ${DEMO_USER.email}`);
  console.log(`  password: ${DEMO_USER.password}`);
  console.log(`  cars:     ${primary} (primary), ${secondary}, ${tertiary}`);
  /* eslint-enable no-console */
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
