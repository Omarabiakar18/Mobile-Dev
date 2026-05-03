/**
 * OCR orchestration — Gemini multimodal pipeline.
 *
 * Phase 4 originally chained Google Cloud Vision (text extraction) + Gemini
 * (JSON parse). Phase 6 simplified this: Gemini reads the image directly
 * (multimodal) and returns the structured fields in one call. No Vision
 * dependency, no GOOGLE_APPLICATION_CREDENTIALS, just a GEMINI_API_KEY.
 *
 * Flow:
 *   1. assertOwnsCar (defense-in-depth — route already did it)
 *   2. DEMO_MODE? Return hardcoded fields (parsedBy='demo'). Done.
 *   3. Preprocess buffer with sharp (greyscale + contrast + upscale).
 *   4. Hash post-preprocess buffer (sha256). Lookup OcrCache.
 *      Hit? Return with parsedBy='cache'.
 *   5. Send post-preprocess JPEG to Gemini multimodal → ParsedFields.
 *      Failure? Return empty fields with parsedBy='failed' (Flutter opens
 *      the form blank — no demo-tanking exception bubbles up).
 *   6. Insert OcrCache row.
 *   7. Return OcrResponse.
 */
import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import { env } from '../../config/env';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';
import { preprocess } from '../../services/ocr';
import {
  parseFieldsFromImageWithLlm,
  type FieldConfidence,
  type ParsedFields,
} from '../../services/ocr-parse';
import { assertOwnsCar } from '../cars/cars.service';

import type { OcrResponse } from './ocr.schemas';

const EMPTY_FIELDS: ParsedFields = {
  liters: null,
  pricePerLiter: null,
  totalCost: null,
  station: null,
  date: null,
};

const ZERO_CONFIDENCE: FieldConfidence = {
  liters: 0,
  pricePerLiter: 0,
  totalCost: 0,
  station: 0,
  date: 0,
};

/**
 * DEMO_MODE response — hardcoded but plausible. Picked so a no-key install
 * still has a working demo flow. Never updates the cache.
 */
const DEMO_FIELDS: ParsedFields = {
  liters: 32.4,
  pricePerLiter: 1.25,
  totalCost: 40.5,
  station: 'TOTAL Jounieh',
  date: new Date().toISOString().slice(0, 10),
};

const DEMO_CONFIDENCE: FieldConfidence = {
  liters: 0.95,
  pricePerLiter: 0.95,
  totalCost: 0.95,
  station: 0.9,
  date: 1,
};

/** Compute sha256 hex of a buffer. Used as the OcrCache primary lookup key. */
function hashBuffer(buf: Buffer): string {
  return createHash('sha256').update(buf).digest('hex');
}

/**
 * Save the post-preprocess JPEG to `<UPLOADS_DIR>/ocr/<hash>.jpg`. No-op when
 * the file already exists. Best-effort; never propagates errors.
 */
async function saveProcessedImage(buf: Buffer, hash: string): Promise<void> {
  const dir = path.resolve(env.UPLOADS_DIR, 'ocr');
  const diskPath = path.join(dir, `${hash}.jpg`);
  try {
    await fs.mkdir(dir, { recursive: true });
    try {
      await fs.access(diskPath);
    } catch {
      await fs.writeFile(diskPath, buf);
    }
  } catch (err) {
    logger.warn({ err, diskPath }, 'Failed to persist OCR image');
  }
}

interface ExtractOptions {
  /** When true, skips the cache lookup but still updates it with the fresh result. */
  force?: boolean;
}

/**
 * Run the full OCR pipeline for a fuel receipt. Caller is responsible for
 * authn (`requireAuth`) and ownership (we re-assert here as defense-in-depth).
 *
 * Returns an `OcrResponse` object — same shape regardless of which branch
 * fired. Never throws on LLM failure; returns sensible nulls.
 */
export async function extractFuelFields(
  userId: string,
  carId: string,
  fileBuffer: Buffer,
  options: ExtractOptions = {},
): Promise<OcrResponse> {
  await assertOwnsCar(userId, carId);

  // 1. DEMO_MODE short-circuit. Done BEFORE sharp/preprocess so a malformed
  //    image (or any error path) can never tank the live demo.
  if (env.DEMO_MODE) {
    logger.info('OCR in DEMO_MODE — returning hardcoded fields');
    return {
      fields: { ...DEMO_FIELDS },
      confidence: { ...DEMO_CONFIDENCE },
      rawText: '[demo-mode] hardcoded receipt fields',
      parsedBy: 'demo',
      photoUrl: null,
    };
  }

  // 2. Preprocess. We hash the *post*-preprocess bytes so two camera captures
  //    of the same receipt collapse into one cache row even if EXIF/quality
  //    differ slightly between shots.
  let processed: Buffer;
  try {
    processed = await preprocess(fileBuffer);
  } catch (err) {
    logger.warn({ err }, 'OCR preprocess failed (malformed image?)');
    return {
      fields: { ...EMPTY_FIELDS },
      confidence: { ...ZERO_CONFIDENCE },
      rawText: '',
      parsedBy: 'failed',
      photoUrl: null,
    };
  }
  const hash = hashBuffer(processed);
  // Build the public URL once. The static-file middleware in `index.ts`
  // serves `<UPLOADS_DIR>` at `/uploads`, so any file we drop under
  // `<UPLOADS_DIR>/ocr/<hash>.jpg` is reachable at this path.
  const photoUrl = `/uploads/ocr/${hash}.jpg`;

  // 3. Cache check.
  if (!options.force) {
    const cached = await prisma.ocrCache.findUnique({ where: { imageHash: hash } });
    if (cached) {
      logger.debug({ hash }, 'OCR cache hit');
      return {
        fields: cached.fields as unknown as ParsedFields,
        confidence: cached.confidence as unknown as FieldConfidence,
        rawText: cached.rawText,
        parsedBy: 'cache',
        photoUrl,
      };
    }
  }

  // Persist the processed image (best-effort, debug aid).
  await saveProcessedImage(processed, hash);

  // 4. Send the image to Gemini multimodal. The LLM does both the OCR AND
  //    the field extraction in one call.
  let parsed;
  try {
    parsed = await parseFieldsFromImageWithLlm(processed, 'image/jpeg');
  } catch (err) {
    logger.warn({ err }, 'Gemini multimodal OCR failed; returning empty fields');
    // Even on LLM failure the photo IS on disk (saveProcessedImage above
    // succeeded), so we still hand back the URL — the user can review the
    // image manually in the form even if the fields couldn't be extracted.
    return {
      fields: { ...EMPTY_FIELDS },
      confidence: { ...ZERO_CONFIDENCE },
      rawText: '',
      parsedBy: 'failed',
      photoUrl,
    };
  }

  // 5. Cache write.
  await prisma.ocrCache.upsert({
    where: { imageHash: hash },
    create: {
      imageHash: hash,
      fields: parsed.fields as unknown as object,
      confidence: parsed.confidence as unknown as object,
      rawText: '', // multimodal path has no intermediate rawText to surface
      provider: 'llm',
    },
    update: {
      fields: parsed.fields as unknown as object,
      confidence: parsed.confidence as unknown as object,
      rawText: '',
      provider: 'llm',
    },
  });

  return {
    fields: parsed.fields,
    confidence: parsed.confidence,
    rawText: '',
    parsedBy: 'llm',
    photoUrl,
  };
}
