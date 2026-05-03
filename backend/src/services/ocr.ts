/**
 * OCR service — Google Cloud Vision wrapper + sharp preprocessing.
 *
 * Used by `modules/ocr/ocr.service.ts`. Kept framework-free so smoke tests can
 * call it directly with a `Buffer`. See spec §7 for the full pipeline.
 *
 * - `preprocess()` runs the sharp pipeline (greyscale, contrast bump, upscale
 *   if low-res, JPEG output) so Vision sees a normalized image regardless of
 *   what the user's camera produced.
 * - `extractText()` calls Vision's `textDetection`. The first annotation is
 *   the full document text; the remaining ones carry per-word confidence.
 *
 * Throws on Vision failure — callers (the module-level `ocr.service`) decide
 * how to fall back (empty fields, demo response, etc.).
 */
import { ImageAnnotatorClient } from '@google-cloud/vision';
import sharp from 'sharp';

import { logger } from '../lib/logger';

export interface ExtractTextResult {
  /** Full document text from Vision's first annotation. Empty string on no-text. */
  rawText: string;
  /** 0..1 — average per-annotation confidence (or 0.5 fallback). */
  confidence: number;
}

let _client: ImageAnnotatorClient | null = null;

/**
 * Lazy singleton Vision client. The constructor reads
 * `GOOGLE_APPLICATION_CREDENTIALS` automatically — we don't pass it explicitly
 * so the same client works in dev (local JSON) and on prod (workload identity).
 */
function getClient(): ImageAnnotatorClient {
  if (_client) return _client;
  _client = new ImageAnnotatorClient();
  return _client;
}

/**
 * Run the receipt through a fixed sharp pipeline:
 *   greyscale → linear contrast bump (~+30%) → modulate to flatten lighting →
 *   upscale to ≥1200px wide so faint print survives JPEG compression →
 *   JPEG (quality 90) for a stable hash + smaller upload.
 *
 * Returns the post-processed JPEG bytes. The caller hashes THIS buffer (not
 * the original) so two captures of the same receipt collapse into one cache
 * entry.
 */
export async function preprocess(imageBuffer: Buffer): Promise<Buffer> {
  // Probe the original size up-front so we can decide whether to upscale.
  // sharp's metadata is cheap (header read only).
  const meta = await sharp(imageBuffer).metadata();
  const width = meta.width ?? 0;

  let pipeline = sharp(imageBuffer)
    .rotate() // honor EXIF orientation (phones rotate via metadata, not pixels)
    .greyscale()
    // linear(a, b): out = a*in + b. a=1.3 → ~+30% contrast. b=-15 trims the
    // pedestal so paper doesn't bloom to pure white.
    .linear(1.3, -15)
    // modulate flattens uneven lighting from the camera flash.
    .modulate({ brightness: 1.05 });

  // Upscale only if the source is below the 1200px threshold — Vision's
  // text-detection accuracy falls off below ~300dpi-equivalent. Lanczos3 is
  // sharp's default for `withoutEnlargement: false` resizes.
  if (width > 0 && width < 1200) {
    pipeline = pipeline.resize({
      width: 1200,
      withoutEnlargement: false,
      kernel: sharp.kernel.lanczos3,
    });
  }

  return pipeline.jpeg({ quality: 90 }).toBuffer();
}

/**
 * Send a prepared image buffer to Vision and pull out the OCR text.
 *
 * Vision's `textDetection` response shape:
 *   - `textAnnotations[0]`     → the full block (no useful per-word confidence)
 *   - `textAnnotations[1..N]`  → individual words with optional `score`/`confidence`
 *   - `fullTextAnnotation.pages[*].blocks[*].confidence` → block-level confidence
 *
 * We use the first annotation's `description` for `rawText` and average the
 * page-level confidence across `fullTextAnnotation`. If Vision doesn't surface
 * a confidence (older API responses), we default to 0.5 — a neutral signal
 * that says "we got text, but be careful trusting individual fields".
 */
export async function extractText(imageBuffer: Buffer): Promise<ExtractTextResult> {
  const client = getClient();
  const [result] = await client.textDetection({ image: { content: imageBuffer } });

  const annotations = result.textAnnotations ?? [];
  const rawText = (annotations[0]?.description ?? '').trim();

  // Vision's per-annotation `confidence` field on textAnnotations is usually
  // null — the real confidence lives under fullTextAnnotation.pages.blocks.
  const blocks = result.fullTextAnnotation?.pages?.flatMap((p) => p.blocks ?? []) ?? [];
  const blockConfidences = blocks
    .map((b) => b.confidence)
    .filter((c): c is number => typeof c === 'number' && Number.isFinite(c));

  let confidence = 0.5;
  if (blockConfidences.length > 0) {
    confidence =
      blockConfidences.reduce((sum, c) => sum + c, 0) / blockConfidences.length;
  }

  logger.debug(
    { rawTextLength: rawText.length, blocks: blocks.length, confidence },
    'Vision text extraction complete',
  );

  return { rawText, confidence };
}
