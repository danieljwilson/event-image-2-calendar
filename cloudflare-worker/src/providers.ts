import { ExtractRequestBody } from './validation';
import { Env, TokenUsage, ModelPricing } from './types';

// ---------------------------------------------------------------------------
// Provider detection
// ---------------------------------------------------------------------------

export type Provider = 'anthropic' | 'openai';

export function detectProvider(model: string): Provider {
  if (
    model.startsWith('gpt-') ||
    model.startsWith('o1') ||
    model.startsWith('o3') ||
    model.startsWith('o4')
  ) {
    return 'openai';
  }
  return 'anthropic';
}

// ---------------------------------------------------------------------------
// Provider request / response types
// ---------------------------------------------------------------------------

export interface ProviderRequest {
  url: string;
  headers: Record<string, string>;
  body: string;
}

// ---------------------------------------------------------------------------
// Build outgoing request for the target provider
// ---------------------------------------------------------------------------

export function buildProviderRequest(extractBody: ExtractRequestBody, env: Env): ProviderRequest {
  const provider = detectProvider(extractBody.model);

  if (provider === 'openai') {
    return buildOpenAIRequest(extractBody, env);
  }
  return buildAnthropicRequest(extractBody, env);
}

// ---------------------------------------------------------------------------
// Anthropic — passthrough (existing behaviour)
// ---------------------------------------------------------------------------

const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_API_VERSION = '2023-06-01';

function buildAnthropicRequest(extractBody: ExtractRequestBody, env: Env): ProviderRequest {
  const payload: Record<string, unknown> = {
    model: extractBody.model,
    max_tokens: extractBody.max_tokens,
    system: extractBody.system,
    messages: extractBody.messages,
  };
  if (extractBody.tools) {
    payload.tools = extractBody.tools;
  }

  return {
    url: ANTHROPIC_API_URL,
    headers: {
      'Content-Type': 'application/json',
      'anthropic-version': ANTHROPIC_API_VERSION,
      'x-api-key': env.CLAUDE_API_KEY,
    },
    body: JSON.stringify(payload),
  };
}

// ---------------------------------------------------------------------------
// OpenAI — translate Claude format → Responses API
// ---------------------------------------------------------------------------

const OPENAI_RESPONSES_URL = 'https://api.openai.com/v1/responses';

function buildOpenAIRequest(extractBody: ExtractRequestBody, env: Env): ProviderRequest {
  const input = transformMessages(extractBody.messages);
  const tools = transformTools(extractBody.tools);

  // OpenAI's max_output_tokens includes tool execution tokens (web search
  // results, reasoning), unlike Claude where max_tokens only counts text
  // output. When web_search tools are present, use a higher budget so the
  // model can search AND produce the JSON response.
  const hasWebSearch = tools.some((t) => t.type === 'web_search');
  const maxOutputTokens = hasWebSearch ? 16384 : extractBody.max_tokens;

  const payload: Record<string, unknown> = {
    model: extractBody.model,
    instructions: extractBody.system,
    input,
    max_output_tokens: maxOutputTokens,
  };
  if (tools.length > 0) {
    payload.tools = tools;
  }

  return {
    url: OPENAI_RESPONSES_URL,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
    },
    body: JSON.stringify(payload),
  };
}

// ---------------------------------------------------------------------------
// Message transformation (Claude → OpenAI Responses API)
// ---------------------------------------------------------------------------

interface ClaudeContentBlock {
  type: string;
  text?: string;
  source?: { type: string; media_type?: string; data?: string };
  [key: string]: unknown;
}

interface ClaudeMessage {
  role: string;
  content: string | ClaudeContentBlock[];
}

interface OpenAIInputItem {
  type: string;
  role: string;
  content: OpenAIContentBlock[];
}

interface OpenAIContentBlock {
  type: string;
  text?: string;
  image_url?: string;
}

function transformMessages(messages: unknown[]): OpenAIInputItem[] {
  return messages.map((msg) => {
    const m = msg as ClaudeMessage;
    const role = m.role ?? 'user';
    let contentBlocks: OpenAIContentBlock[];

    if (typeof m.content === 'string') {
      contentBlocks = [{ type: 'input_text', text: m.content }];
    } else if (Array.isArray(m.content)) {
      contentBlocks = m.content.map(transformContentBlock);
    } else {
      contentBlocks = [{ type: 'input_text', text: String(m.content ?? '') }];
    }

    return { type: 'message', role, content: contentBlocks };
  });
}

function transformContentBlock(block: ClaudeContentBlock): OpenAIContentBlock {
  if (block.type === 'image' && block.source?.type === 'base64') {
    const mediaType = block.source.media_type ?? 'image/jpeg';
    const data = block.source.data ?? '';
    return {
      type: 'input_image',
      image_url: `data:${mediaType};base64,${data}`,
    };
  }

  if (block.type === 'text') {
    return { type: 'input_text', text: block.text ?? '' };
  }

  // Unknown block type — pass text if available, otherwise skip as empty text
  return { type: 'input_text', text: block.text ?? '' };
}

// ---------------------------------------------------------------------------
// Tool transformation (Claude → OpenAI Responses API)
// ---------------------------------------------------------------------------

interface OpenAITool {
  type: string;
  user_location?: unknown;
}

function transformTools(tools?: unknown[]): OpenAITool[] {
  if (!tools || !Array.isArray(tools)) return [];

  const result: OpenAITool[] = [];

  for (const tool of tools) {
    const t = tool as Record<string, unknown>;
    if (typeof t.type === 'string' && t.type.startsWith('web_search')) {
      const openaiTool: OpenAITool = { type: 'web_search' };
      if (t.user_location) {
        openaiTool.user_location = t.user_location;
      }
      result.push(openaiTool);
    }
    // Other Claude-specific tools are dropped (no OpenAI equivalent)
  }

  return result;
}

// ---------------------------------------------------------------------------
// Response transformation (OpenAI → Claude format)
// ---------------------------------------------------------------------------

interface ClaudeFormatResponse {
  content: Array<{ type: string; text: string }>;
  stop_reason: string;
}

/**
 * Transform an OpenAI Responses API JSON body into the Claude Messages API
 * shape that the iOS client expects (`ClaudeResponse`).
 *
 * Returns `null` if the response is not in the expected OpenAI format
 * (caller should fall back to passing the raw body through).
 */
export function transformOpenAIResponse(body: unknown): ClaudeFormatResponse | null {
  if (!body || typeof body !== 'object') return null;

  const resp = body as Record<string, unknown>;
  const output = resp.output;
  if (!Array.isArray(output)) return null;

  const textBlocks: Array<{ type: string; text: string }> = [];

  for (const item of output) {
    const entry = item as Record<string, unknown>;
    if (entry.type !== 'message') continue;

    const content = entry.content;
    if (!Array.isArray(content)) continue;

    for (const block of content) {
      const b = block as Record<string, unknown>;
      if (b.type === 'output_text' && typeof b.text === 'string') {
        textBlocks.push({ type: 'text', text: b.text });
      }
    }
  }

  // Map OpenAI status to Claude stop_reason
  let stopReason = 'end_turn';
  const status = resp.status as string | undefined;
  if (status === 'incomplete') {
    const incompleteDetails = resp.incomplete_details as Record<string, unknown> | undefined;
    if (incompleteDetails?.reason === 'max_output_tokens') {
      stopReason = 'max_tokens';
    }
  }

  return { content: textBlocks, stop_reason: stopReason };
}

// ---------------------------------------------------------------------------
// Model pricing — update when prices change, then wrangler deploy
// Source: https://platform.openai.com/docs/pricing
//         https://docs.anthropic.com/en/docs/about-claude/pricing
// ---------------------------------------------------------------------------

export const MODEL_PRICING: Record<string, ModelPricing> = {
  'gpt-5-nano':              { input_per_million: 0.05, output_per_million: 0.40 },
  'gpt-5-nano-2025-08-07':   { input_per_million: 0.05, output_per_million: 0.40 },
  'gpt-5.4-nano':            { input_per_million: 0.20, output_per_million: 1.25 },
  'gpt-5.4-nano-2026-03-17': { input_per_million: 0.20, output_per_million: 1.25 },
  'claude-haiku-4-5':        { input_per_million: 1.00, output_per_million: 5.00 },
};

// ---------------------------------------------------------------------------
// Usage extraction — works for both OpenAI and Anthropic responses
// Both use { usage: { input_tokens, output_tokens } }
// ---------------------------------------------------------------------------

export function extractUsage(body: unknown): TokenUsage | null {
  if (!body || typeof body !== 'object') return null;
  const resp = body as Record<string, unknown>;
  const usage = resp.usage as Record<string, unknown> | undefined;
  if (!usage) return null;
  const input = usage.input_tokens;
  const output = usage.output_tokens;
  if (typeof input !== 'number' || typeof output !== 'number') return null;
  return { input_tokens: input, output_tokens: output };
}

export function calculateCost(model: string, usage: TokenUsage): number {
  const costs = calculateCostBreakdown(model, usage);
  return costs.total;
}

export function calculateCostBreakdown(
  model: string,
  usage: TokenUsage
): { input: number; output: number; total: number } {
  const pricing = MODEL_PRICING[model];
  if (!pricing) return { input: 0, output: 0, total: 0 };
  const input = (usage.input_tokens * pricing.input_per_million) / 1_000_000;
  const output = (usage.output_tokens * pricing.output_per_million) / 1_000_000;
  return { input, output, total: input + output };
}
