/**
 * LLM service — text + strict-JSON + multimodal completions.
 *
 * Used by:
 *   - OCR (receipt field parsing — see spec §16-A)
 *   - Service reminders (AI-phrased messages — §16-B)
 *   - Fuel predict-next explainer (§16-C)
 *
 * Providers: Gemini (default), OpenAI. Selected at boot via env.LLM_PROVIDER.
 * All consumers must provide a non-LLM fallback. This service throws on
 * timeout / network / JSON-parse failures so the caller can branch.
 */
import { GoogleGenerativeAI, GenerativeModel } from '@google/generative-ai';
import OpenAI from 'openai';
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

export interface LlmImageInput {
  /** Raw image bytes (e.g. JPEG buffer post-sharp-preprocess). */
  data: Buffer;
  /** MIME type — `image/jpeg` or `image/png`. */
  mimeType: string;
}

export interface LlmProvider {
  name: string;
  /** Strict-JSON completion from a text prompt. */
  json<T>(prompt: string, schema: z.ZodType<T>, options?: LlmOptions): Promise<T>;
  /** Free-text completion from a text prompt. */
  text(prompt: string, options?: LlmOptions): Promise<string>;
  /**
   * Multimodal strict-JSON completion: prompt + an image. Used by OCR
   * (§16-A) so we don't need a separate Vision API — Gemini reads the
   * receipt directly and returns the structured fields.
   */
  imageJson<T>(
    prompt: string,
    image: LlmImageInput,
    schema: z.ZodType<T>,
    options?: LlmOptions,
  ): Promise<T>;
}

function withTimeout<T>(p: Promise<T>): Promise<T> {
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

  async text(prompt: string, options?: LlmOptions): Promise<string> {
    const m = this.model(options);
    const result = await withTimeout(m.generateContent(prompt));
    return result.response.text();
  }

  async json<T>(prompt: string, schema: z.ZodType<T>, options?: LlmOptions): Promise<T> {
    // Force JSON output by appending a strict instruction. Many models honor this
    // better than relying on response_mime_type.
    const fullPrompt = `${prompt}\n\nReturn ONLY valid JSON. No markdown fences, no commentary.`;
    const raw = await this.text(fullPrompt, { ...options, temperature: options?.temperature ?? 0.1 });
    return parseJsonResponse(raw, schema);
  }

  async imageJson<T>(
    prompt: string,
    image: LlmImageInput,
    schema: z.ZodType<T>,
    options?: LlmOptions,
  ): Promise<T> {
    const m = this.model({ ...options, temperature: options?.temperature ?? 0.1 });
    const fullPrompt = `${prompt}\n\nReturn ONLY valid JSON. No markdown fences, no commentary.`;
    const result = await withTimeout(
      m.generateContent([
        {
          inlineData: {
            mimeType: image.mimeType,
            data: image.data.toString('base64'),
          },
        },
        fullPrompt,
      ]),
    );
    return parseJsonResponse(result.response.text(), schema);
  }
}

class OpenAiProvider implements LlmProvider {
  readonly name = 'openai';
  private client: OpenAI;

  constructor() {
    if (!env.OPENAI_API_KEY) {
      throw new Error('OPENAI_API_KEY is not set');
    }
    this.client = new OpenAI({ apiKey: env.OPENAI_API_KEY });
  }

  async text(prompt: string, options?: LlmOptions): Promise<string> {
    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [];
    if (options?.systemPrompt) {
      messages.push({ role: 'system', content: options.systemPrompt });
    }
    messages.push({ role: 'user', content: prompt });

    const result = await withTimeout(
      this.client.chat.completions.create({
        model: env.OPENAI_MODEL,
        messages,
        temperature: options?.temperature ?? 0.2,
        max_tokens: options?.maxTokens ?? 300,
      }),
    );
    return result.choices[0]?.message?.content ?? '';
  }

  async json<T>(prompt: string, schema: z.ZodType<T>, options?: LlmOptions): Promise<T> {
    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [];
    if (options?.systemPrompt) {
      messages.push({ role: 'system', content: options.systemPrompt });
    }
    messages.push({
      role: 'user',
      content: `${prompt}\n\nReturn ONLY valid JSON. No markdown fences, no commentary.`,
    });

    const result = await withTimeout(
      this.client.chat.completions.create({
        model: env.OPENAI_MODEL,
        messages,
        temperature: options?.temperature ?? 0.1,
        max_tokens: options?.maxTokens ?? 300,
        response_format: { type: 'json_object' },
      }),
    );
    return parseJsonResponse(result.choices[0]?.message?.content ?? '', schema);
  }

  async imageJson<T>(
    prompt: string,
    image: LlmImageInput,
    schema: z.ZodType<T>,
    options?: LlmOptions,
  ): Promise<T> {
    const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [];
    if (options?.systemPrompt) {
      messages.push({ role: 'system', content: options.systemPrompt });
    }
    messages.push({
      role: 'user',
      content: [
        {
          type: 'text',
          text: `${prompt}\n\nReturn ONLY valid JSON. No markdown fences, no commentary.`,
        },
        {
          type: 'image_url',
          image_url: {
            url: `data:${image.mimeType};base64,${image.data.toString('base64')}`,
          },
        },
      ],
    });

    const result = await withTimeout(
      this.client.chat.completions.create({
        model: env.OPENAI_MODEL,
        messages,
        temperature: options?.temperature ?? 0.1,
        max_tokens: options?.maxTokens ?? 400,
        response_format: { type: 'json_object' },
      }),
    );
    return parseJsonResponse(result.choices[0]?.message?.content ?? '', schema);
  }
}

/**
 * Strip common JSON-in-fenced-codeblock wrappers and validate against a Zod
 * schema. Throws if the model returned non-JSON or shape-mismatched JSON so
 * the caller can fall through to whatever non-LLM path it has.
 */
function parseJsonResponse<T>(raw: string, schema: z.ZodType<T>): T {
  const trimmed = raw
    .trim()
    .replace(/^```json\s*/i, '')
    .replace(/^```\s*/i, '')
    .replace(/```\s*$/i, '');

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    logger.warn({ raw: trimmed.slice(0, 200) }, 'LLM JSON parse failed');
    throw new Error('LLM returned invalid JSON');
  }
  return schema.parse(parsed);
}

let _provider: LlmProvider | null = null;

export function llm(): LlmProvider {
  if (_provider) return _provider;
  switch (env.LLM_PROVIDER) {
    case 'gemini':
      _provider = new GeminiProvider();
      return _provider;
    case 'openai':
      _provider = new OpenAiProvider();
      return _provider;
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
