import { z } from 'zod';

/**
 * The four allowed document types — mirrors the `DocumentType` enum in
 * `prisma/schema.prisma`. Kept in sync manually because Prisma's generated
 * enum is also a runtime value, but using a Zod enum keeps validation errors
 * uniform with the rest of the API.
 */
const documentTypeSchema = z.enum(['insurance', 'mecanique', 'registration', 'other']);

/**
 * `createDocumentSchema` is parsed from `req.body` AFTER multer.single('file')
 * runs, so every field arrives as a string. We coerce the dates and lean on
 * z.string() for the type (the enum still rejects unknown values).
 */
export const createDocumentSchema = z.object({
  type: documentTypeSchema,
  issuedDate: z.coerce.date().optional(),
  expiryDate: z.coerce.date(),
  issuer: z.string().min(1).max(120).trim().optional(),
  notes: z.string().max(2000).optional(),
});

/** Metadata-only update — the file blob isn't touched in v1. */
export const updateDocumentSchema = createDocumentSchema.partial();

export const listQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(20),
});

export const expiringQuerySchema = z.object({
  withinDays: z.coerce.number().int().min(1).max(365).default(30),
});

export type CreateDocumentInput = z.infer<typeof createDocumentSchema>;
export type UpdateDocumentInput = z.infer<typeof updateDocumentSchema>;
export type ListQueryInput = z.infer<typeof listQuerySchema>;
export type ExpiringQueryInput = z.infer<typeof expiringQuerySchema>;
