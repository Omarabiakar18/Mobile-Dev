import { z } from 'zod';

const fuelTypeSchema = z.enum(['gasoline', 'diesel']);

export const createCarSchema = z
  .object({
    make: z.string().min(1).max(60).trim(),
    model: z.string().min(1).max(60).trim(),
    year: z.coerce
      .number()
      .int()
      .min(1900)
      .max(new Date().getFullYear() + 1),
    plate: z.string().min(1).max(20).trim(),
    color: z.string().max(30).optional(),
    currentKm: z.coerce.number().int().nonnegative().default(0),
    fuelType: fuelTypeSchema,
    tankSize: z.coerce.number().positive().max(500), // liters
    photoUrl: z.string().url().optional(),
  })
  .strict();

export const updateCarSchema = createCarSchema.partial().strict();

export type CreateCarInput = z.infer<typeof createCarSchema>;
export type UpdateCarInput = z.infer<typeof updateCarSchema>;
