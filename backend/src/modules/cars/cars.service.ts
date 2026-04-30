import type { Car } from '@prisma/client';

import { prisma } from '../../lib/prisma';
import { ForbiddenError, NotFoundError } from '../../lib/errors';
import { recomputeAvgKmPerDay } from '../../lib/avg-km-per-day';
import type { CreateCarInput, UpdateCarInput } from './cars.schemas';

/**
 * Throws ForbiddenError if the car doesn't belong to the user (or NotFound if
 * it doesn't exist). Use at the top of every car-scoped handler.
 */
export async function assertOwnsCar(userId: string, carId: string): Promise<Car> {
  const car = await prisma.car.findUnique({ where: { id: carId } });
  if (!car) throw new NotFoundError('Car not found');
  if (car.userId !== userId) throw new ForbiddenError('You do not own this car');
  return car;
}

export function listForUser(userId: string) {
  return prisma.car.findMany({
    where: { userId },
    orderBy: { createdAt: 'desc' },
  });
}

export async function getById(userId: string, carId: string) {
  return assertOwnsCar(userId, carId);
}

export function create(userId: string, input: CreateCarInput) {
  return prisma.car.create({
    data: {
      userId,
      make: input.make,
      model: input.model,
      year: input.year,
      plate: input.plate,
      color: input.color ?? null,
      currentKm: input.currentKm,
      fuelType: input.fuelType,
      tankSize: input.tankSize,
      photoUrl: input.photoUrl ?? null,
    },
  });
}

export async function update(userId: string, carId: string, input: UpdateCarInput) {
  await assertOwnsCar(userId, carId);

  // If currentKm changed we must recompute avgKmPerDay because predict-next
  // and reminder projection both read it from the cached column. Wrap in a
  // transaction so the cached value never lags the source of truth.
  if (input.currentKm !== undefined) {
    return prisma.$transaction(async (tx) => {
      const car = await tx.car.update({ where: { id: carId }, data: input });
      await recomputeAvgKmPerDay(carId, tx);
      return tx.car.findUnique({ where: { id: car.id } }) as Promise<Car>;
    });
  }

  return prisma.car.update({ where: { id: carId }, data: input });
}

export async function remove(userId: string, carId: string) {
  await assertOwnsCar(userId, carId);
  await prisma.car.delete({ where: { id: carId } });
}
