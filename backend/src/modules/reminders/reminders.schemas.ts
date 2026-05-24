import { z } from 'zod';

/**
 * Create-reminder body. At least one of `intervalKm` / `intervalMonths` must be
 * present so the projection (§6.2 / Phase 2 calendar projection) has something
 * to work with.
 */
export const createReminderSchema = z
  .object({
    serviceType: z.string().min(1).max(80).trim(),
    lastDoneKm: z.coerce.number().int().nonnegative(),
    lastDoneDate: z.coerce.date(),
    intervalKm: z.coerce.number().int().positive().optional(),
    intervalMonths: z.coerce.number().int().positive().optional(),
    isActive: z.coerce.boolean().optional().default(true),
  })
  .refine((v) => v.intervalKm != null || v.intervalMonths != null, {
    message: 'At least one of intervalKm or intervalMonths must be set',
    path: ['intervalKm'],
  });

/**
 * Patch body. We can't `.partial()` a refined schema cleanly, so re-state the
 * shape. Same refine rule when both intervals are explicitly set to null —
 * but a normal partial update can omit them entirely.
 */
export const updateReminderSchema = z
  .object({
    serviceType: z.string().min(1).max(80).trim().optional(),
    lastDoneKm: z.coerce.number().int().nonnegative().optional(),
    lastDoneDate: z.coerce.date().optional(),
    intervalKm: z.coerce.number().int().positive().nullable().optional(),
    intervalMonths: z.coerce.number().int().positive().nullable().optional(),
    isActive: z.coerce.boolean().optional(),
  })
  .refine(
    (v) => {
      // If the caller is explicitly clearing both intervals, that's invalid.
      const clearingKm = v.intervalKm === null;
      const clearingMonths = v.intervalMonths === null;
      if (clearingKm && clearingMonths) return false;
      return true;
    },
    {
      message: 'At least one of intervalKm or intervalMonths must remain set',
      path: ['intervalKm'],
    },
  );

/** Query for `GET /cars/:carId/reminders/due`. */
export const dueQuerySchema = z.object({
  // Mobile reminders-list screen passes 99999 to mean "all time". No upper
  // bound here — query is bounded by actual reminder rows, no DoS risk.
  withinDays: z.coerce.number().int().min(1).default(30),
});

export type CreateReminderInput = z.infer<typeof createReminderSchema>;
export type UpdateReminderInput = z.infer<typeof updateReminderSchema>;
export type DueQueryInput = z.infer<typeof dueQuerySchema>;
