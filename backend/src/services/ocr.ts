/**
 * OCR preprocessing — sharp pipeline only.
 *
 * The Vision API was removed in favor of Gemini's multimodal endpoint (it
 * reads images directly). The remaining job here is just to normalize the
 * image: orient via EXIF, greyscale, contrast bump, upscale low-res so the
 * model sees a stable input regardless of camera, EXIF, or lighting.
 *
 * Used by `modules/ocr/ocr.service.ts`. Kept framework-free so smoke tests
 * can call it directly with a `Buffer`.
 */
import sharp from 'sharp';

// Cap memory usage so a worst-case 8MB JPEG can't decode to an OOM-sized
// raw image while sharp is processing it. Set once at module load.
sharp.cache({ files: 0 });
sharp.concurrency(1);

/**
 * Run the receipt through a fixed sharp pipeline:
 *   greyscale → linear contrast bump (~+30%) → modulate to flatten lighting →
 *   upscale to ≥1200px wide so faint print survives JPEG compression →
 *   JPEG (quality 90) for a stable hash + smaller upload.
 *
 * Returns the post-processed JPEG bytes. The caller hashes THIS buffer (not
 * the original) so two captures of the same receipt collapse into one cache
 * entry. Throws if the input isn't a decodable image.
 */
export async function preprocess(imageBuffer: Buffer): Promise<Buffer> {
  // Probe the original size up-front so we can decide whether to upscale.
  // sharp's metadata is cheap (header read only) and surfaces a clean error
  // if the buffer isn't a real image.
  const meta = await sharp(imageBuffer).metadata();
  const width = meta.width ?? 0;
  const height = meta.height ?? 0;

  // Defense against decode-bomb images: refuse anything whose decoded size
  // would blow past ~50 megapixels.
  if (width * height > 50_000_000) {
    throw new Error(
      `Image too large to preprocess (${width}x${height}, ${width * height} px)`,
    );
  }

  let pipeline = sharp(imageBuffer)
    .rotate() // honor EXIF orientation (phones rotate via metadata, not pixels)
    .greyscale()
    // linear(a, b): out = a*in + b. a=1.3 → ~+30% contrast. b=-15 trims the
    // pedestal so paper doesn't bloom to pure white.
    .linear(1.3, -15)
    // modulate flattens uneven lighting from the camera flash.
    .modulate({ brightness: 1.05 });

  // Upscale only if the source is below the 1200px threshold — small images
  // give the LLM less to work with on faint thermal print.
  if (width > 0 && width < 1200) {
    pipeline = pipeline.resize({
      width: 1200,
      withoutEnlargement: false,
      kernel: sharp.kernel.lanczos3,
    });
  }

  return pipeline.jpeg({ quality: 90 }).toBuffer();
}
