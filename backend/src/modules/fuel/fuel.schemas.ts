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
  // Receipt-photo persistence (Phase 6 polish). The OCR endpoint returns
  // `photoUrl: "/uploads/ocr/<hash>.jpg"` and the mobile client passes it
  // back here so the saved fuel entry keeps a permanent link to the receipt
  // image. Capped at 2KB so the column can't be abused.
  receiptPhotoUrl: z.string().max(2048).optional(),
});

// PATCH-style: every field is optional AND nullable. Nullable so the mobile
// edit form can clear an optional field (station/notes/etc.) by sending null
// rather than having to omit it from the JSON body.
export const updateFuelSchema = createFuelSchema.partial().extend({
  station: z.string().max(120).trim().nullish(),
  notes: z.string().max(1000).nullish(),
  latitude: z.coerce.number().min(-90).max(90).nullish(),
  longitude: z.coerce.number().min(-180).max(180).nullish(),
  receiptPhotoUrl: z.string().max(2048).nullish(),
});

export const listQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
});

export type CreateFuelInput = z.infer<typeof createFuelSchema>;
export type UpdateFuelInput = z.infer<typeof updateFuelSchema>;
export type ListFuelQuery = z.infer<typeof listQuerySchema>;
