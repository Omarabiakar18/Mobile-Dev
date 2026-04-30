import { z } from 'zod';

const fuelTypeSchema = z.enum(['gasoline', 'diesel']);

export const createFuelSchema = z.object({
  date: z.string().datetime({ offset: true }),
  odometer: z.coerce.number().int().nonnegative(),
  liters: z.coerce.number().positive(),
  pricePerLiter: z.coerce.number().positive(),
  totalCost: z.coerce.number().positive(),
  fuelType: fuelTypeSchema,
  station: z.string().max(120).trim().optional(),
  isFullTank: z.coerce.boolean().optional().default(false),
  latitude: z.coerce.number().min(-90).max(90).optional(),
  longitude: z.coerce.number().min(-180).max(180).optional(),
  notes: z.string().max(1000).optional(),
});

export const updateFuelSchema = createFuelSchema.partial();

export const listQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
});

export type CreateFuelInput = z.infer<typeof createFuelSchema>;
export type UpdateFuelInput = z.infer<typeof updateFuelSchema>;
export type ListFuelQuery = z.infer<typeof listQuerySchema>;
