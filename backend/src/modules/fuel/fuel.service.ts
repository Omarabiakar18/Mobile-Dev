import { Prisma } from '@prisma/client';

import { prisma } from '../../lib/prisma';
import { NotFoundError } from '../../lib/errors';
import { recomputeAvgKmPerDay } from '../../lib/avg-km-per-day';
import { assertOwnsCar } from '../cars/cars.service';
import type { CreateFuelInput, UpdateFuelInput } from './fuel.schemas';

const DEFAULT_PAGE_SIZE = 50;
const MS_PER_DAY = 86_400_000;

export async function listForCar(
  userId: string,
  carId: string,
  page = 1,
  limit = DEFAULT_PAGE_SIZE,
) {
  await assertOwnsCar(userId, carId);
  const safePage = Math.max(1, page);
  const safeLimit = Math.max(1, Math.min(100, limit));

  const [entries, total] = await Promise.all([
    prisma.fuelEntry.findMany({
      where: { carId },
      orderBy: { date: 'desc' },
      skip: (safePage - 1) * safeLimit,
      take: safeLimit,
    }),
    prisma.fuelEntry.count({ where: { carId } }),
  ]);

  return {
    entries,
    page: safePage,
    limit: safeLimit,
    total,
  };
}

export async function getOne(userId: string, fuelId: string) {
  const entry = await prisma.fuelEntry.findUnique({ where: { id: fuelId } });
  if (!entry) throw new NotFoundError('Fuel entry not found');
  await assertOwnsCar(userId, entry.carId);
  return entry;
}

export async function create(userId: string, carId: string, input: CreateFuelInput) {
  await assertOwnsCar(userId, carId);
  // Wrap insert + avgKmPerDay recompute in a single tx so the cached value on
  // Car never lags the underlying entries (spec §6.2).
  return prisma.$transaction(async (tx) => {
    const entry = await tx.fuelEntry.create({
      data: {
        carId,
        date: new Date(input.date),
        odometer: input.odometer,
        liters: new Prisma.Decimal(input.liters),
        pricePerLiter: new Prisma.Decimal(input.pricePerLiter),
        totalCost: new Prisma.Decimal(input.totalCost),
        fuelType: input.fuelType,
        station: input.station ?? null,
        isFullTank: input.isFullTank ?? false,
        latitude: input.latitude ?? null,
        longitude: input.longitude ?? null,
        notes: input.notes ?? null,
        receiptPhotoUrl: input.receiptPhotoUrl ?? null,
      },
    });
    await recomputeAvgKmPerDay(carId, tx);
    return entry;
  });
}

export async function update(userId: string, fuelId: string, input: UpdateFuelInput) {
  const existing = await prisma.fuelEntry.findUnique({ where: { id: fuelId } });
  if (!existing) throw new NotFoundError('Fuel entry not found');
  await assertOwnsCar(userId, existing.carId);

  const data: Prisma.FuelEntryUpdateInput = {};
  if (input.date !== undefined) data.date = new Date(input.date);
  if (input.odometer !== undefined) data.odometer = input.odometer;
  if (input.liters !== undefined) data.liters = new Prisma.Decimal(input.liters);
  if (input.pricePerLiter !== undefined)
    data.pricePerLiter = new Prisma.Decimal(input.pricePerLiter);
  if (input.totalCost !== undefined) data.totalCost = new Prisma.Decimal(input.totalCost);
  if (input.fuelType !== undefined) data.fuelType = input.fuelType;
  if (input.station !== undefined) data.station = input.station;
  if (input.isFullTank !== undefined) data.isFullTank = input.isFullTank;
  if (input.latitude !== undefined) data.latitude = input.latitude;
  if (input.longitude !== undefined) data.longitude = input.longitude;
  if (input.notes !== undefined) data.notes = input.notes;
  if (input.receiptPhotoUrl !== undefined)
    data.receiptPhotoUrl = input.receiptPhotoUrl;

  return prisma.$transaction(async (tx) => {
    const entry = await tx.fuelEntry.update({ where: { id: fuelId }, data });
    await recomputeAvgKmPerDay(existing.carId, tx);
    return entry;
  });
}

export async function remove(userId: string, fuelId: string) {
  const existing = await prisma.fuelEntry.findUnique({ where: { id: fuelId } });
  if (!existing) throw new NotFoundError('Fuel entry not found');
  await assertOwnsCar(userId, existing.carId);
  await prisma.$transaction(async (tx) => {
    await tx.fuelEntry.delete({ where: { id: fuelId } });
    await recomputeAvgKmPerDay(existing.carId, tx);
  });
}

interface WindowTotals {
  liters: number;
  cost: number;
  fillCount: number;
}

async function windowTotals(carId: string, sinceDays: number): Promise<WindowTotals> {
  const since = new Date(Date.now() - sinceDays * 24 * 60 * 60 * 1000);
  const agg = await prisma.fuelEntry.aggregate({
    where: { carId, date: { gte: since } },
    _sum: { liters: true, totalCost: true },
    _count: { _all: true },
  });
  return {
    liters: toNumber(agg._sum.liters),
    cost: toNumber(agg._sum.totalCost),
    fillCount: agg._count._all,
  };
}

/**
 * Avg L/100km from consecutive (full-tank → full-tank) pairs in odometer order.
 * Returns null if fewer than 2 full-tank entries exist (per spec §6.1 bootstrap).
 */
function avgConsumptionFromFullTankPairs(
  fullTanks: { odometer: number; liters: Prisma.Decimal }[],
): number | null {
  if (fullTanks.length < 2) return null;
  const sorted = [...fullTanks].sort((a, b) => a.odometer - b.odometer);

  let total = 0;
  let pairs = 0;
  for (let i = 1; i < sorted.length; i++) {
    const prev = sorted[i - 1];
    const curr = sorted[i];
    const km = curr.odometer - prev.odometer;
    if (km <= 0) continue;
    // Liters that filled the tank back up to full on the *current* fill-up
    // approximate the liters consumed since the previous full tank.
    const liters = toNumber(curr.liters);
    total += (liters / km) * 100;
    pairs += 1;
  }

  return pairs > 0 ? total / pairs : null;
}

export async function stats(userId: string, carId: string) {
  await assertOwnsCar(userId, carId);

  const [agg, fullTanks, last30, last90] = await Promise.all([
    prisma.fuelEntry.aggregate({
      where: { carId },
      _sum: { liters: true, totalCost: true },
      _max: { odometer: true },
      _min: { odometer: true },
      _count: { _all: true },
    }),
    prisma.fuelEntry.findMany({
      where: { carId, isFullTank: true },
      orderBy: { odometer: 'asc' },
      select: { odometer: true, liters: true },
    }),
    windowTotals(carId, 30),
    windowTotals(carId, 90),
  ]);

  const totalKm =
    agg._max.odometer != null && agg._min.odometer != null
      ? agg._max.odometer - agg._min.odometer
      : 0;

  return {
    totalLiters: toNumber(agg._sum.liters),
    totalCost: toNumber(agg._sum.totalCost),
    totalKm,
    fillCount: agg._count._all,
    avgConsumptionPer100km: avgConsumptionFromFullTankPairs(fullTanks),
    last30,
    last90,
  };
}

export type PredictNextResult =
  | {
      confidence: 'insufficient_data' | 'data_inconsistent';
      tankRemainingLiters: null;
      daysRemaining: null;
      predictedDate: null;
    }
  | {
      confidence: 'ok';
      tankRemainingLiters: number;
      daysRemaining: number | null;
      predictedDate: string | null;
      consumptionPer100km: number;
      kmSinceLastFull: number;
    };

interface PredictNextCar {
  tankSize: Prisma.Decimal | number;
  currentKm: number;
  avgKmPerDay: Prisma.Decimal | number | null;
}

interface PredictNextEntry {
  odometer: number;
  liters: Prisma.Decimal | number;
  isFullTank: boolean;
}

/**
 * Pure §6.1 implementation — exported so the math can be smoke-tested without
 * a DB. The async wrapper below loads the same shape and forwards.
 *
 * Bootstrap requires ≥3 full-tank entries (spec §6.1). Fewer is unreliable.
 * If `currentKm < lastFullTank.odometer`, returns `data_inconsistent` so the
 * Flutter UI can prompt the user to fix their odometer entries.
 */
export function computePredictNext(
  car: PredictNextCar,
  entries: PredictNextEntry[],
  today: Date = new Date(),
): PredictNextResult {
  const fullTanks = entries
    .filter((e) => e.isFullTank)
    .sort((a, b) => a.odometer - b.odometer);

  // Bootstrap on valid pairs, not raw full-tank count. Three full tanks with a
  // duplicate odometer reading produce only one usable pair, and the algorithm
  // averages across pairs — so require ≥2 valid pairs to match the spec's
  // intent (smoother consumption signal).
  const validPairs: { liters: number; kmLeg: number }[] = [];
  for (let i = 1; i < fullTanks.length; i++) {
    const kmLeg = fullTanks[i].odometer - fullTanks[i - 1].odometer;
    if (kmLeg > 0) {
      validPairs.push({ liters: toNumber(fullTanks[i].liters), kmLeg });
    }
  }

  if (validPairs.length < 2) {
    return {
      confidence: 'insufficient_data',
      tankRemainingLiters: null,
      daysRemaining: null,
      predictedDate: null,
    };
  }

  const lastFullTank = fullTanks[fullTanks.length - 1];
  if (car.currentKm < lastFullTank.odometer) {
    return {
      confidence: 'data_inconsistent',
      tankRemainingLiters: null,
      daysRemaining: null,
      predictedDate: null,
    };
  }

  // Avg L/100km across every valid (full-tank, full-tank) pair. The liters on
  // entry[i] are what filled the tank back to full, which approximates what
  // was consumed over the (odo[i-1] → odo[i]) leg.
  const consumptionPer100km =
    validPairs.reduce((acc, p) => acc + (p.liters / p.kmLeg) * 100, 0) / validPairs.length;

  const kmSinceLastFull = car.currentKm - lastFullTank.odometer;
  const litersUsed = (kmSinceLastFull * consumptionPer100km) / 100;
  const tankSizeNum = toNumber(car.tankSize);
  const tankRemainingLitersRaw = Math.max(0, tankSizeNum - litersUsed);
  const tankRemainingLiters = Math.round(tankRemainingLitersRaw * 10) / 10;

  const avg = car.avgKmPerDay == null ? 0 : toNumber(car.avgKmPerDay);
  if (avg <= 0) {
    return {
      confidence: 'ok',
      tankRemainingLiters,
      daysRemaining: null,
      predictedDate: null,
      consumptionPer100km,
      kmSinceLastFull,
    };
  }

  // daysRemaining = (km of fuel left) / (km/day driven)
  // km of fuel left = tankRemainingLiters / consumptionPer100km * 100
  const daysRemainingRaw =
    ((tankRemainingLitersRaw / consumptionPer100km) * 100) / avg;
  const daysRemaining = Math.round(daysRemainingRaw * 10) / 10;
  const predictedDate = new Date(
    today.getTime() + daysRemainingRaw * MS_PER_DAY,
  ).toISOString();

  return {
    confidence: 'ok',
    tankRemainingLiters,
    daysRemaining,
    predictedDate,
    consumptionPer100km,
    kmSinceLastFull,
  };
}

/**
 * Predictive next fill-up — spec §6.1. Loads the car + every fuel entry, then
 * delegates to `computePredictNext`. Response shape matches what the Flutter
 * "Explain this prediction" modal renders (§16-C).
 */
export async function predictNext(
  userId: string,
  carId: string,
): Promise<PredictNextResult> {
  const car = await assertOwnsCar(userId, carId);
  const entries = await prisma.fuelEntry.findMany({
    where: { carId },
    orderBy: { odometer: 'asc' },
    select: { odometer: true, liters: true, isFullTank: true },
  });
  return computePredictNext(car, entries);
}

function toNumber(v: Prisma.Decimal | number | null | undefined): number {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  return Number(v.toString());
}
