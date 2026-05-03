/**
 * OCR orchestration — ties the Vision client (`services/ocr.ts`) and the
 * field parsers (`services/ocr-parse.ts`) into the pipeline described in
 * spec §7. The route layer (`ocr.routes.ts`) calls `extractFuelFields()`
 * after `requireAuth` and `assertOwnsCar`.
 *
 * Flow (preserved exactly from spec §7):
 *   1. Preprocess buffer with sharp
 *   2. Hash post-preprocess buffer (sha256). Lookup OcrCache.
 *   3. Cache hit? Return with parsedBy='cache'.
 *   4. Demo mode? Return hardcoded fields with parsedBy='demo'.
 *   5. Vision -> rawText. Vision throw? parsedBy='failed', empty fields.
 *   6. LLM parse on rawText. Success → parsedBy='llm'.
 *   7. LLM failure → regex parse → parsedBy='regex'.
 *   8. Insert OcrCache row (skip in demo mode).
 *   9. Return OcrResponse.
 */
import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import { env } from '../../config/env';
import { logger } from '../../lib/logger';
import { prisma } from '../../lib/prisma';
import { extractText, preprocess } from '../../services/ocr';
import {
  parseFieldsWithLlm,
  parseFieldsWithRegex,
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
 * DEMO_MODE response — hardcoded but plausible. Picked so the demo flow
 * (spec §10) shows realistic Lebanese-USD numbers without any external calls.
 * Never updates the cache (the operator might flip DEMO_MODE off later and
 * we don't want this sentinel polluting real cache rows).
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
 * the file already exists (a previous request hashed identically — same
 * receipt). Returns the public-facing URL or `null` if the write failed
 * (the OCR result is still useful even without the saved blob, so we don't
 * propagate file-write errors).
 */
async function saveProcessedImage(buf: Buffer, hash: string): Promise<string | null> {
  const dir = path.resolve(env.UPLOADS_DIR, 'ocr');
  const diskPath = path.join(dir, `${hash}.jpg`);
  try {
    await fs.mkdir(dir, { recursive: true });
    // Only write if missing — the hash makes the filename idempotent.
    try {
      await fs.access(diskPath);
    } catch {
      await fs.writeFile(diskPath, buf);
    }
    return `/uploads/ocr/${hash}.jpg`;
  } catch (err) {
    logger.warn({ err, diskPath }, 'Failed to persist OCR image');
    return null;
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
 * Returns an `OcrResponse` object — the same shape regardless of which branch
 * fired. Never throws on Vision/LLM failure; returns sensible nulls instead.
 */
export async function extractFuelFields(
  userId: string,
  carId: string,
  fileBuffer: Buffer,
  options: ExtractOptions = {},
): Promise<OcrResponse> {
  // Defense-in-depth: even though the route already called assertOwnsCar,
  // re-running it here means a future direct caller can't bypass it.
  await assertOwnsCar(userId, carId);

  // 1. DEMO_MODE short-circuit. Done BEFORE sharp/preprocess so a malformed
  //    image (or any error path) can never tank the live demo. The whole
  //    point of DEMO_MODE is the response is bulletproof — keep it pure.
  if (env.DEMO_MODE) {
    logger.info('OCR in DEMO_MODE — returning hardcoded fields');
    return {
      fields: { ...DEMO_FIELDS },
      confidence: { ...DEMO_CONFIDENCE },
      rawText: '[demo-mode] hardcoded receipt fields',
      parsedBy: 'demo',
    };
  }

  // 2. Preprocess. We hash the *post*-preprocess bytes so two camera captures
  //    of the same receipt collapse into one cache row even if EXIF/quality
  //    differ slightly between shots.
  const processed = await preprocess(fileBuffer);
  const hash = hashBuffer(processed);

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
      };
    }
  }

  // Persist the processed image so a debug UI / support tool can pull it up
  // by hash later. Best-effort; we don't fail the request if disk is full.
  await saveProcessedImage(processed, hash);

  // 4. Vision call. If it throws, the user gets an empty form back —
  //    Flutter just opens the fuel-entry form blank rather than erroring.
  let rawText = '';
  let visionConfidence = 0.5;
  try {
    const result = await extractText(processed);
    rawText = result.rawText;
    visionConfidence = result.confidence;
  } catch (err) {
    logger.warn({ err }, 'Vision text extraction failed; returning empty fields');
    return {
      fields: { ...EMPTY_FIELDS },
      confidence: { ...ZERO_CONFIDENCE },
      rawText: '',
      parsedBy: 'failed',
    };
  }

  // 5. LLM-first parse (spec §16-A). Falls through to regex on any failure.
  let parsed;
  let parsedBy: 'llm' | 'regex';
  try {
    parsed = await parseFieldsWithLlm(rawText);
    parsedBy = 'llm';
  } catch (err) {
    logger.warn({ err }, 'LLM receipt parse failed; falling back to regex');
    parsed = parseFieldsWithRegex(rawText);
    parsedBy = 'regex';
  }

  // Tighten the confidence floor: if Vision itself was low-confidence, no
  // downstream parse can be high-confidence. Multiply per-field by the
  // Vision score so the user sees orange highlights on shaky scans.
  const fields = parsed.fields;
  const confidence: FieldConfidence = {
    liters: parsed.confidence.liters * visionConfidence,
    pricePerLiter: parsed.confidence.pricePerLiter * visionConfidence,
    totalCost: parsed.confidence.totalCost * visionConfidence,
    station: parsed.confidence.station * visionConfidence,
    date: parsed.confidence.date * visionConfidence,
  };

  // 6. Cache write. `upsert` so a `force=true` re-run overwrites the old row.
  //    JSON columns mean we can stash arbitrary extra metadata later without
  //    a migration.
  await prisma.ocrCache.upsert({
    where: { imageHash: hash },
    create: {
      imageHash: hash,
      fields: fields as unknown as object,
      confidence: confidence as unknown as object,
      rawText,
      provider: parsedBy,
    },
    update: {
      fields: fields as unknown as object,
      confidence: confidence as unknown as object,
      rawText,
      provider: parsedBy,
    },
  });

  return { fields, confidence, rawText, parsedBy };
}
