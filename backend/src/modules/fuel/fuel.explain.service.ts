/**
 * Spec §16-C — "Explain this prediction" endpoint.
 *
 * Loads the same data the deterministic predict-next algorithm uses, runs
 * the algorithm, then phrases the result for a human via the LLM. Three
 * branches:
 *
 *   - confidence: 'insufficient_data'  → fixed string, no LLM call.
 *   - confidence: 'data_inconsistent'  → fixed string, no LLM call.
 *   - confidence: 'ok'                 → LLM walk-through, with a deterministic
 *                                        fallback if the call fails.
 *
 * Caching: none. The Flutter side opens this on tap (per spec §16-C) and the
 * underlying numbers may have shifted since the last fuel entry. Re-run is
 * cheap — once per user-tap is bounded by the route rate-limit (30/day).
 */
import type { Car } from '@prisma/client';

import { env } from '../../config/env';
import { prisma } from '../../lib/prisma';
import { llm, llmOrFallback } from '../../services/llm';
import { assertOwnsCar } from '../cars/cars.service';
import { computePredictNext, type PredictNextResult } from './fuel.service';

export type ExplainParsedBy = 'llm' | 'fallback' | 'demo';

export interface ExplainResult {
  explanation: string;
  parsedBy: ExplainParsedBy;
  generatedAt: string;
}

const EXPLAIN_SYSTEM_PROMPT =
  'You are explaining a deterministic fuel prediction to the owner of the car. Use ONLY the numbers provided. Walk through the math in plain English in 2-3 short sentences. Do not invent numbers. Do not give advice.';

interface OkPrediction {
  confidence: 'ok';
  tankRemainingLiters: number;
  daysRemaining: number | null;
  predictedDate: string | null;
  consumptionPer100km: number;
  kmSinceLastFull: number;
}

interface ExplainCar
  extends Pick<
    Car,
    'make' | 'model' | 'year' | 'currentKm' | 'tankSize' | 'avgKmPerDay'
  > {}

interface FullTankSnapshot {
  date: Date;
  odometer: number;
}

/**
 * Pure prompt builder — exported so the verification script can hit it
 * without a network. Numbers are rounded to 1 decimal where natural so the
 * model never has to repeat 8.123456789 back to the user.
 */
export function buildExplainPrompt(
  car: ExplainCar,
  prediction: OkPrediction,
  context: {
    n: number;
    avgKmPerDayWindow: string;
    lastFullTank: FullTankSnapshot | null;
  },
): string {
  const tankSize = Number(car.tankSize.toString());
  const avg =
    car.avgKmPerDay == null ? 0 : Number(car.avgKmPerDay.toString());
  const avgRounded = Math.round(avg * 10) / 10;
  const consumption = Math.round(prediction.consumptionPer100km * 100) / 100;
  const tankRemaining = prediction.tankRemainingLiters;
  const daysRemaining =
    prediction.daysRemaining == null
      ? 'unknown'
      : String(prediction.daysRemaining);
  const predictedDate =
    prediction.predictedDate == null
      ? 'unknown'
      : prediction.predictedDate.slice(0, 10);
  const lastFullTankIso =
    context.lastFullTank == null
      ? 'unknown'
      : context.lastFullTank.date.toISOString().slice(0, 10);
  const lastFullTankOdo =
    context.lastFullTank == null ? 'unknown' : String(context.lastFullTank.odometer);

  return [
    `Car: ${car.year} ${car.make} ${car.model}, tank size ${tankSize} L, currently at ${car.currentKm} km.`,
    `Average consumption (from ${context.n} full-tank pairs): ${consumption} L/100km.`,
    `Last full tank: ${lastFullTankIso} at ${lastFullTankOdo} km.`,
    `Driving pace (${context.avgKmPerDayWindow}): ${avgRounded} km/day.`,
    `Estimated tank remaining: ${tankRemaining} L → ${daysRemaining} days → ${predictedDate}.`,
  ].join('\n');
}

/**
 * Hardcoded fallback paragraph used when the LLM fails or DEMO_MODE is on.
 * Interpolates the real numbers — never lies — so the user gets a coherent
 * explanation even on the demo loop with no internet.
 */
export function fallbackExplainMessage(
  car: ExplainCar,
  prediction: OkPrediction,
  context: { n: number },
): string {
  const consumption = Math.round(prediction.consumptionPer100km * 100) / 100;
  const avg =
    car.avgKmPerDay == null ? 0 : Number(car.avgKmPerDay.toString());
  const avgRounded = Math.round(avg * 10) / 10;
  const daysRemaining =
    prediction.daysRemaining == null ? 'unknown' : prediction.daysRemaining;
  const predictedDate =
    prediction.predictedDate == null
      ? 'unknown'
      : prediction.predictedDate.slice(0, 10);

  return (
    `Based on ${context.n} full-tank fill-ups, your ${car.make} ${car.model} averages ` +
    `${consumption} L/100km. You've driven ${prediction.kmSinceLastFull} km since the last ` +
    `full tank. At your ${avgRounded} km/day pace, the tank should run dry in about ` +
    `${daysRemaining} days, around ${predictedDate}.`
  );
}

/**
 * The full pipeline: load car + entries, run the deterministic algorithm,
 * branch on confidence, and either return a fixed string or call the LLM.
 */
export async function explainPredictNext(
  userId: string,
  carId: string,
): Promise<ExplainResult> {
  const car = await assertOwnsCar(userId, carId);
  const entries = await prisma.fuelEntry.findMany({
    where: { carId },
    orderBy: { odometer: 'asc' },
    select: { date: true, odometer: true, liters: true, isFullTank: true },
  });

  const prediction: PredictNextResult = computePredictNext(car, entries);
  const generatedAt = new Date().toISOString();

  if (prediction.confidence !== 'ok') {
    if (prediction.confidence === 'insufficient_data') {
      return {
        explanation:
          'Add at least 2 full-tank fill-ups to enable predictions.',
        parsedBy: 'fallback',
        generatedAt,
      };
    }
    // data_inconsistent
    return {
      explanation:
        'Your current odometer reading is lower than the last recorded full tank. ' +
        'Check your odometer entries — one of them is likely wrong.',
      parsedBy: 'fallback',
      generatedAt,
    };
  }

  // After the guard above TS narrows `prediction` to the 'ok' variant, which
  // is structurally identical to OkPrediction.
  // confidence === 'ok' — assemble the context the prompt needs.
  const fullTanks = entries.filter((e) => e.isFullTank);
  const validPairCount = fullTanks
    .slice(1)
    .filter((curr, i) => curr.odometer - fullTanks[i].odometer > 0).length;
  const lastFullTank = fullTanks[fullTanks.length - 1] ?? null;
  const ctx = {
    n: validPairCount,
    // The window label is informational — `recomputeAvgKmPerDay` walks 60d
    // → 90d → 180d. Without storing which window won we surface the most
    // common outcome ("60 days") and accept the small lossiness.
    avgKmPerDayWindow: '60 days',
    lastFullTank: lastFullTank
      ? { date: lastFullTank.date, odometer: lastFullTank.odometer }
      : null,
  };

  const prompt = buildExplainPrompt(car, prediction, ctx);
  const result = await llmOrFallback(
    () =>
      llm().text(prompt, {
        temperature: 0.3,
        maxTokens: 200,
        systemPrompt: EXPLAIN_SYSTEM_PROMPT,
      }),
    () => fallbackExplainMessage(car, prediction, { n: ctx.n }),
  );

  // `parsedBy === 'demo'` is meaningful to the Flutter UI (renders a small
  // badge "demo data"). DEMO_MODE always routes through the fallback branch
  // inside llmOrFallback, so we re-derive the label here. We can't tell
  // post-hoc whether `usedLlm: false` came from DEMO or from a real failure;
  // the env flag is the source of truth.
  let parsedBy: ExplainParsedBy;
  if (result.usedLlm) {
    parsedBy = 'llm';
  } else {
    parsedBy = env.DEMO_MODE ? 'demo' : 'fallback';
  }

  return {
    explanation: result.value.trim(),
    parsedBy,
    generatedAt,
  };
}
