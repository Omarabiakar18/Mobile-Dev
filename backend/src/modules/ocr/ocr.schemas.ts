import { z } from 'zod';

import type { ParsedFields, FieldConfidence } from '../../services/ocr-parse';

/**
 * Optional query for the OCR endpoint. `force=true` skips the cache lookup so
 * an operator can force a re-extraction (useful when iterating on the LLM
 * prompt). The cache row is still updated with the fresh result.
 */
export const ocrQuerySchema = z.object({
  force: z
    .union([z.literal('true'), z.literal('false'), z.literal('1'), z.literal('0')])
    .optional()
    .transform((v) => v === 'true' || v === '1'),
});

export type OcrQuery = z.infer<typeof ocrQuerySchema>;

/**
 * Response shape returned to Flutter. Stable contract — see Phase 4 task
 * report. `parsedBy` lets the client render the right loader (cache hit is
 * instant; demo is hardcoded; failed means open an empty form).
 *
 * `photoUrl` is the public path of the post-preprocess JPEG that was used
 * for OCR. Flutter passes this URL through to `POST /cars/:carId/fuel` so
 * the saved fuel entry keeps a permanent link to the receipt image. `null`
 * on demo / failed paths since there's no real photo to surface.
 */
export interface OcrResponse {
  fields: ParsedFields;
  confidence: FieldConfidence;
  rawText: string;
  parsedBy: 'llm' | 'regex' | 'cache' | 'demo' | 'failed';
  photoUrl: string | null;
}
