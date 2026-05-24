/**
 * Generates a synthetic Lebanese-style gas-pump receipt JPEG that the
 * Garage app can OCR cleanly. Writes to backend/uploads/test/receipt.jpg
 * so we can `adb push` it to the phone in one step.
 *
 * Run: cd backend && npx tsx scripts/make-test-receipt.ts
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from 'sharp';

const OUT_DIR = path.resolve(__dirname, '..', 'uploads', 'test');
const OUT_PATH = path.join(OUT_DIR, 'receipt.jpg');

// Receipt-card SVG. Wide enough that the OCR upscale step never has to
// stretch it, and the text is generously sized so Gemini reads cleanly.
const svg = `
<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1440">
  <rect width="100%" height="100%" fill="#F7F1E3"/>
  <rect x="0" y="0" width="100%" height="120" fill="#1F3A5F"/>
  <text x="540" y="76" font-family="Helvetica, Arial, sans-serif" font-size="56"
        font-weight="700" fill="white" text-anchor="middle" letter-spacing="2">
    TOTAL JOUNIEH
  </text>

  <text x="540" y="200" font-family="Helvetica" font-size="32" fill="#2C3E50"
        text-anchor="middle">
    Highway · Jounieh · Lebanon
  </text>
  <text x="540" y="244" font-family="Helvetica" font-size="32" fill="#2C3E50"
        text-anchor="middle">
    Tel: 09-123456 · VAT: 12345
  </text>

  <line x1="80" y1="300" x2="1000" y2="300" stroke="#2C3E50" stroke-width="2" stroke-dasharray="10,8"/>

  <text x="120" y="380" font-family="Helvetica" font-size="38" fill="#1F3A5F" font-weight="600">DATE</text>
  <text x="960" y="380" font-family="Helvetica" font-size="38" fill="#1F3A5F" text-anchor="end">2026-05-24</text>

  <text x="120" y="440" font-family="Helvetica" font-size="38" fill="#1F3A5F" font-weight="600">TIME</text>
  <text x="960" y="440" font-family="Helvetica" font-size="38" fill="#1F3A5F" text-anchor="end">14:32</text>

  <text x="120" y="500" font-family="Helvetica" font-size="38" fill="#1F3A5F" font-weight="600">PUMP</text>
  <text x="960" y="500" font-family="Helvetica" font-size="38" fill="#1F3A5F" text-anchor="end">3</text>

  <text x="120" y="560" font-family="Helvetica" font-size="38" fill="#1F3A5F" font-weight="600">PRODUCT</text>
  <text x="960" y="560" font-family="Helvetica" font-size="38" fill="#1F3A5F" text-anchor="end">Gasoline 95</text>

  <line x1="80" y1="620" x2="1000" y2="620" stroke="#2C3E50" stroke-width="2"/>

  <text x="120" y="710" font-family="Helvetica" font-size="48" fill="#1F3A5F" font-weight="600">LITERS</text>
  <text x="960" y="710" font-family="Helvetica" font-size="48" fill="#1F3A5F" text-anchor="end" font-weight="600">45.20 L</text>

  <text x="120" y="790" font-family="Helvetica" font-size="48" fill="#1F3A5F" font-weight="600">PRICE / L</text>
  <text x="960" y="790" font-family="Helvetica" font-size="48" fill="#1F3A5F" text-anchor="end" font-weight="600">$ 1.10</text>

  <text x="120" y="870" font-family="Helvetica" font-size="48" fill="#1F3A5F" font-weight="600">SUBTOTAL</text>
  <text x="960" y="870" font-family="Helvetica" font-size="48" fill="#1F3A5F" text-anchor="end" font-weight="600">$ 49.72</text>

  <line x1="80" y1="940" x2="1000" y2="940" stroke="#2C3E50" stroke-width="3"/>

  <text x="120" y="1030" font-family="Helvetica" font-size="60" fill="#C13B2E" font-weight="800">TOTAL</text>
  <text x="960" y="1030" font-family="Helvetica" font-size="60" fill="#C13B2E" text-anchor="end" font-weight="800">$ 49.72</text>

  <line x1="80" y1="1100" x2="1000" y2="1100" stroke="#2C3E50" stroke-width="2" stroke-dasharray="10,8"/>

  <text x="540" y="1180" font-family="Helvetica" font-size="32" fill="#2C3E50" text-anchor="middle">
    Card · **** 4242
  </text>
  <text x="540" y="1230" font-family="Helvetica" font-size="32" fill="#2C3E50" text-anchor="middle">
    Auth: 008832
  </text>

  <text x="540" y="1350" font-family="Helvetica" font-size="36" fill="#2C3E50" text-anchor="middle" font-style="italic">
    Thank you · Merci · شكراً
  </text>
</svg>
`;

async function main() {
  await fs.mkdir(OUT_DIR, { recursive: true });
  await sharp(Buffer.from(svg))
    .jpeg({ quality: 92 })
    .toFile(OUT_PATH);
  const stat = await fs.stat(OUT_PATH);
  console.log(`wrote ${OUT_PATH} (${(stat.size / 1024).toFixed(1)} KB)`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
