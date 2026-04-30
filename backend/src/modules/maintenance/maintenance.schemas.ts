import { z } from 'zod';

const maintenanceTypeSchema = z.enum([
  'oil',
  'brakes',
  'tires',
  'filter',
  'battery',
  'other',
]);

export const createMaintenanceSchema = z.object({
  date: z.string().datetime({ offset: true }),
  km: z.coerce.number().int().nonnegative(),
  type: maintenanceTypeSchema,
  description: z.string().max(500).trim().optional(),
  cost: z.coerce.number().positive(),
  notes: z.string().max(1000).trim().optional(),
});

export const updateMaintenanceSchema = createMaintenanceSchema.partial();

export const listQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
});

export type CreateMaintenanceInput = z.infer<typeof createMaintenanceSchema>;
export type UpdateMaintenanceInput = z.infer<typeof updateMaintenanceSchema>;
export type ListMaintenanceQuery = z.infer<typeof listQuerySchema>;
