/**
 * LLM service — Gemini-backed text + strict-JSON completions.
 *
 * Used by:
 *   - OCR (receipt field parsing — see spec §16-A)
 *   - Service reminders (AI-phrased messages — §16-B)
 *   - Fuel predict-next explainer (§16-C)
 *
 * All consumers must provide a non-LLM fallback. This service throws on
 * timeout / network / JSON-parse failures so the caller can branch.
 */
import { GoogleGenerativeAI, GenerativeModel } from '@google/generative-ai';
import { z } from 'zod';

import { env } from '../config/env';
import { logger } from '../lib/logger';

export interface LlmOptions {
  /** 0.0–1.0. Default 0.2 (deterministic-ish). */
  temperature?: number;
  /** Default 300. */
  maxTokens?: number;
  /** Optional system instruction. */
  systemPrompt?: string;
}

export interface LlmProvider {
  name: string;
  /** Strict-JSON completion. Validates response against the provided Zod schema. */
  json<T>(prompt: string, schema: z.ZodType<T>, options?: LlmOptions): Promise<T>;
  /** Free-text completion. */
  text(prompt: string, options?: LlmOptions): Promise<string>;
}

class GeminiProvider implements LlmProvider {
  readonly name = 'gemini';
  private client: GoogleGenerativeAI;

  constructor() {
    if (!env.GEMINI_API_KEY) {
      throw new Error('GEMINI_API_KEY is not set');
    }
    this.client = new GoogleGenerativeAI(env.GEMINI_API_KEY);
  }

  private model(options?: LlmOptions): GenerativeModel {
    return this.client.getGenerativeModel({
      model: env.LLM_MODEL,
      generationConfig: {
        temperature: options?.temperature ?? 0.2,
        maxOutputTokens: options?.maxTokens ?? 300,
      },
      ...(options?.systemPrompt && { systemInstruction: options.systemPrompt }),
    });
  }

  private withTimeout<T>(p: Promise<T>): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const t = setTimeout(
        () => reject(new Error(`LLM call timed out after ${env.LLM_TIMEOUT_MS}ms`)),
        env.LLM_TIMEOUT_MS,
      );
      p.then(
        (v) => {
          clearTimeout(t);
          resolve(v);
        },
        (e) => {
          clearTimeout(t);
          reject(e);
        },
      );
    });
  }

  async text(prompt: string, options?: LlmOptions): Promise<string> {
    const m = this.model(options);
    const result = await this.withTimeout(m.generateContent(prompt));
    return result.response.text();
  }

  async json<T>(prompt: string, schema: z.ZodType<T>, options?: LlmOptions): Promise<T> {
    // Force JSON output by appending a strict instruction. Many models honor this
    // better than relying on response_mime_type.
    const fullPrompt = `${prompt}\n\nReturn ONLY valid JSON. No markdown fences, no commentary.`;
    const raw = await this.text(fullPrompt, { ...options, temperature: options?.temperature ?? 0.1 });
    const trimmed = raw.trim().replace(/^```json\s*/i, '').replace(/```\s*$/i, '');

    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch (err) {
      logger.warn({ raw: trimmed.slice(0, 200) }, 'LLM JSON parse failed');
      throw new Error('LLM returned invalid JSON');
    }
    return schema.parse(parsed);
  }
}

let _provider: LlmProvider | null = null;

export function llm(): LlmProvider {
  if (_provider) return _provider;
  switch (env.LLM_PROVIDER) {
    case 'gemini':
      _provider = new GeminiProvider();
      return _provider;
    case 'openai':
    case 'anthropic':
      throw new Error(`LLM_PROVIDER=${env.LLM_PROVIDER} not implemented yet`);
    default:
      throw new Error(`Unknown LLM_PROVIDER: ${env.LLM_PROVIDER}`);
  }
}

/**
 * Helper: run an LLM call with a typed fallback so feature code stays clean.
 *
 *   const message = await llmOrFallback(
 *     () => llm().text(prompt),
 *     () => `${serviceType} due in ${days} days`,
 *   );
 */
export async function llmOrFallback<T>(
  call: () => Promise<T>,
  fallback: () => T,
): Promise<{ value: T; usedLlm: boolean }> {
  if (env.DEMO_MODE) {
    return { value: fallback(), usedLlm: false };
  }
  try {
    const value = await call();
    return { value, usedLlm: true };
  } catch (err) {
    logger.warn({ err }, 'LLM call failed; using fallback');
    return { value: fallback(), usedLlm: false };
  }
}
