/**
 * OCR field-parse strategies — pure functions, no I/O outside the LLM call.
 *
 * Two strategies are exposed:
 *   1. `parseFieldsWithLlm` — strict-JSON Gemini call (spec §16-A). Best on
 *      mixed-script Lebanese receipts; throws on parse/timeout failure.
 *   2. `parseFieldsWithRegex` — deterministic fallback (spec §7). Matches the
 *      common "$12.34 / 24.56 L / 0.502 /L" patterns. Always returns — sparse
 *      receipts just yield more nulls.
 *
 * Both return the same shape so the orchestrator (modules/ocr/ocr.service)
 * can tag the response with `parsedBy` after the fact.
 */
import { z } from 'zod';

import { llm } from './llm';

export interface ParsedFields {
  liters: number | null;
  pricePerLiter: number | null;
  totalCost: number | null;
  station: string | null;
  /** ISO date `YYYY-MM-DD`, or `null` if unparseable. */
  date: string | null;
}

/** Per-field 0..1 confidence. 1 = parser had a direct match; 0 = no match. */
export interface FieldConfidence {
  liters: number;
  pricePerLiter: number;
  totalCost: number;
  station: number;
  date: number;
}

export interface ParseResult {
  fields: ParsedFields;
  confidence: FieldConfidence;
}

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

// ---------------------------------------------------------------------------
// Regex parser
// ---------------------------------------------------------------------------

/**
 * Extract the first capture group's number from the first match across the
 * full text, normalizing European decimal commas to dots. Returns `null` when
 * no match. Used for liters / price / total below.
 */
function firstNumeric(text: string, regex: RegExp): number | null {
  const match = text.match(regex);
  if (!match || !match[1]) return null;
  const normalized = match[1].replace(',', '.');
  const value = Number(normalized);
  return Number.isFinite(value) ? value : null;
}

/**
 * Parse common date forms (`DD/MM/YYYY`, `D-M-YY`, `YYYY-MM-DD`) into ISO
 * `YYYY-MM-DD`. Two-digit years coerce to 20YY (the app is brand-new — no
 * 19xx receipts coming through). Returns `null` if the parse is ambiguous
 * or yields an invalid date.
 *
 * Note: we don't try to disambiguate `01/02/2026` between US and EU — Lebanon
 * uses DD/MM, so we always assume day-first. False positives here are recovered
 * by the user editing the field before submit.
 */
function parseFirstDate(text: string): string | null {
  // ISO first (least ambiguous): 2026-04-30
  const iso = text.match(/\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b/);
  if (iso) {
    const [, y, m, d] = iso;
    return formatIsoDate(Number(y), Number(m), Number(d));
  }

  // Then DD/MM/YYYY or DD-MM-YYYY (also accepts `.` separator, common in EU receipts)
  const dmy = text.match(/\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})\b/);
  if (dmy) {
    const [, d, m, yRaw] = dmy;
    let y = Number(yRaw);
    if (y < 100) y += 2000;
    return formatIsoDate(y, Number(m), Number(d));
  }

  return null;
}

function formatIsoDate(y: number, m: number, d: number): string | null {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  // Build via Date to catch impossible dates (Feb 30 etc.) — Date silently
  // overflows, so we round-trip and compare to flag invalid inputs.
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (
    dt.getUTCFullYear() !== y ||
    dt.getUTCMonth() !== m - 1 ||
    dt.getUTCDate() !== d
  ) {
    return null;
  }
  const mm = String(m).padStart(2, '0');
  const dd = String(d).padStart(2, '0');
  return `${y}-${mm}-${dd}`;
}

/**
 * Best-effort station-name guess: walk the lines, pick the first one that's
 * mostly letters and looks like a brand name (contains a vowel, ≥3 chars,
 * not a number-heavy line). Lebanon stations are typically printed loud at
 * the top: "TOTAL", "MEDCO", "COR-AL", "HYPCO" — letters dominate.
 */
function guessStation(text: string): string | null {
  const lines = text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  for (const line of lines.slice(0, 6)) {
    // Skip number-heavy lines (totals, dates, phone numbers) and anything too short.
    if (line.length < 3) continue;
    const letterCount = (line.match(/[A-Za-z]/g) ?? []).length;
    const digitCount = (line.match(/\d/g) ?? []).length;
    if (letterCount < 3) continue;
    if (digitCount > letterCount) continue;
    // Require at least one vowel — keeps "L L L" / "WWW.X" out.
    if (!/[AEIOUaeiou]/.test(line)) continue;
    // Strip trailing punctuation / receipt cruft like "TOTAL S.A.R.L. -- 1234".
    const cleaned = line.replace(/[*\-=_]{2,}.*$/, '').trim();
    return cleaned.slice(0, 60);
  }
  return null;
}

/**
 * Spec §7 contract: regex extraction. Matches:
 *   - total  → `\$` or `USD` followed by a number
 *   - liters → number followed by `L` (allows `LT`/`LTR`)
 *   - pricePerLiter → number followed by `/L`
 *   - date   → DD/MM/YYYY (and ISO + dotted variants)
 *   - station → first non-numeric line that looks like a name
 *
 * Per-field confidence is 1.0 on a hit, 0 on a miss. The orchestrator can
 * surface that to Flutter so missed fields show as orange "please confirm".
 */
export function parseFieldsWithRegex(rawText: string): ParseResult {
  if (!rawText || !rawText.trim()) {
    return { fields: { ...EMPTY_FIELDS }, confidence: { ...ZERO_CONFIDENCE } };
  }

  const text = rawText;

  // Liters: e.g. "24.56 L", "24,56 LT", "24.56LTR". Anchor on a digit-bearing
  // numeric token immediately followed by L/LT/LTR with optional whitespace,
  // but exclude the "/L" suffix that belongs to pricePerLiter — otherwise
  // a "0.98 USD/LT" line eats the liters slot.
  const liters = firstNumeric(text, /(\d{1,4}(?:[.,]\d{1,3})?)\s*(?<!\/)\s*L(?:T|TR)?\b(?!\s*\/)/i);

  // Price per liter: e.g. "$0.502 /L", "0,502/LT", "0,98 USD/LT". The unit
  // suffix can be "/L", "/LT", "/LTR" with optional currency text in between.
  const pricePerLiter = firstNumeric(
    text,
    /(\d{1,3}(?:[.,]\d{1,4})?)\s*(?:\$|€|£|USD|EUR)?\s*\/\s*L(?:T|TR)?\b/i,
  );

  // Total cost: a labeled "TOTAL <amount>" wins over an unlabeled `$NN.NN`,
  // since price lines also tend to carry `$` or `USD`. Prefer the explicit
  // TOTAL/TTL label first; only fall back to currency-prefixed numbers if no
  // labeled total appears (e.g. on a sparse receipt where only `$42.00`
  // survives — see test case 3).
  let totalCost = firstNumeric(
    text,
    /\bT(?:O?TA?L|TL)\b[^\d\n]{0,12}(?:\$|USD)?\s*(\d{1,5}(?:[.,]\d{1,2})?)\s*(?:\$|USD)?/i,
  );
  if (totalCost === null) {
    totalCost = firstNumeric(text, /\$\s*(\d{1,5}(?:[.,]\d{1,2})?)\b/);
  }
  if (totalCost === null) {
    // "NN.NN USD" — but reject matches that are part of a "/L" suffix
    // (those are prices per liter, not totals).
    totalCost = firstNumeric(text, /(\d{1,5}(?:[.,]\d{1,2})?)\s*USD\b(?!\s*\/)/i);
  }

  const date = parseFirstDate(text);
  const station = guessStation(text);

  return {
    fields: { liters, pricePerLiter, totalCost, station, date },
    confidence: {
      liters: liters !== null ? 1 : 0,
      pricePerLiter: pricePerLiter !== null ? 1 : 0,
      totalCost: totalCost !== null ? 1 : 0,
      station: station !== null ? 1 : 0,
      date: date !== null ? 1 : 0,
    },
  };
}

// ---------------------------------------------------------------------------
// LLM parser
// ---------------------------------------------------------------------------

/**
 * Zod shape the LLM is forced to return. The model is supposed to emit
 * `number | null` for numeric fields per the prompt, but Gemini occasionally
 * stringifies them. We accept either and normalize manually after parse
 * (zod transforms on a union widen the output type in zod 3 and break TS
 * narrowing — manual normalization keeps `ParseResult` strictly typed).
 */
const llmReceiptSchema = z.object({
  liters: z.union([z.number(), z.string(), z.null()]),
  pricePerLiter: z.union([z.number(), z.string(), z.null()]),
  totalCost: z.union([z.number(), z.string(), z.null()]),
  station: z.string().min(1).nullable(),
  date: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD')
    .nullable(),
  confidence: z.coerce.number().min(0).max(1),
});

/** Coerce a number-or-string-or-null to `number | null`. */
function toNumberOrNull(v: number | string | null): number | null {
  if (v === null || v === '') return null;
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

const PROMPT_TEMPLATE = `You are extracting fields from a gas station receipt. Return ONLY valid JSON
matching this exact shape — no commentary, no markdown:
{ "liters": number|null, "pricePerLiter": number|null, "totalCost": number|null,
  "station": string|null, "date": "YYYY-MM-DD"|null, "confidence": number }

Currency is USD. If a field is unclear or absent, use null. \`confidence\` is your
own 0.0-1.0 estimate of how sure you are about the overall extraction.

Receipt text:
"""
{rawText}
"""`;

/**
 * Spec §16-A LLM-parsed receipts. Builds the strict-JSON prompt, runs it
 * through `llm().json()` (Zod-validated), and translates the model's overall
 * confidence into per-field scores. Throws on timeout / parse failure / schema
 * violation so the caller can fall through to `parseFieldsWithRegex`.
 */
export async function parseFieldsWithLlm(rawText: string): Promise<ParseResult> {
  if (!rawText || !rawText.trim()) {
    // Don't bother spending tokens on an empty image.
    return { fields: { ...EMPTY_FIELDS }, confidence: { ...ZERO_CONFIDENCE } };
  }

  const prompt = PROMPT_TEMPLATE.replace('{rawText}', rawText);
  const parsed = await llm().json(prompt, llmReceiptSchema, {
    temperature: 0.1,
    maxTokens: 300,
  });

  // Normalize numeric fields after Zod parse — `liters/pricePerLiter/totalCost`
  // come out as `number | string | null` and we want strict `number | null`.
  const liters = toNumberOrNull(parsed.liters);
  const pricePerLiter = toNumberOrNull(parsed.pricePerLiter);
  const totalCost = toNumberOrNull(parsed.totalCost);

  const overall = parsed.confidence;
  // Per-field confidence: model's overall score where the field is filled,
  // 0 where it returned null. Gives Flutter a usable per-field signal even
  // though the LLM itself only emits a single rating.
  const fieldConf = (v: unknown): number => (v === null ? 0 : overall);

  return {
    fields: {
      liters,
      pricePerLiter,
      totalCost,
      station: parsed.station,
      date: parsed.date,
    },
    confidence: {
      liters: fieldConf(liters),
      pricePerLiter: fieldConf(pricePerLiter),
      totalCost: fieldConf(totalCost),
      station: fieldConf(parsed.station),
      date: fieldConf(parsed.date),
    },
  };
}
