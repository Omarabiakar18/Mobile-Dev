import { Prisma } from '@prisma/client';

import { prisma } from '../../lib/prisma';
import { NotFoundError } from '../../lib/errors';
import { assertOwnsCar } from '../cars/cars.service';
import type { CreateFuelInput, UpdateFuelInput } from './fuel.schemas';

const DEFAULT_PAGE_SIZE = 50;

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
  return prisma.fuelEntry.create({
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
    },
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

  return prisma.fuelEntry.update({ where: { id: fuelId }, data });
}

export async function remove(userId: string, fuelId: string) {
  const existing = await prisma.fuelEntry.findUnique({ where: { id: fuelId } });
  if (!existing) throw new NotFoundError('Fuel entry not found');
  await assertOwnsCar(userId, existing.carId);
  await prisma.fuelEntry.delete({ where: { id: fuelId } });
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

/**
 * Phase 3 will implement the full predictive next fill-up algorithm.
 * TODO(phase 3): see spec §6.1 — needs ≥3 full-tank entries, computes
 * consumptionPer100km from pairs, projects tankRemaining + daysRemaining
 * using cached `Car.avgKmPerDay`.
 */
export async function predictNext(userId: string, carId: string) {
  await assertOwnsCar(userId, carId);
  return {
    confidence: 'insufficient_data' as const,
    tankRemainingLiters: null,
    daysRemaining: null,
    predictedDate: null,
  };
}

function toNumber(v: Prisma.Decimal | number | null | undefined): number {
  if (v == null) return 0;
  if (typeof v === 'number') return v;
  return Number(v.toString());
}
