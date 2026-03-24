import { describe, expect, it } from 'vitest';
import { buildProviderRequest, calculateCost, detectProvider, extractUsage, transformOpenAIResponse } from '../src/providers';
import type { Env } from '../src/types';
import type { ExtractRequestBody } from '../src/validation';

const fakeEnv: Env = {
  EVENTS: {} as never,
  RESEND_API_KEY: 'test-resend',
  DIGEST_EMAIL_TO: 'test@example.com',
  DIGEST_EMAIL_FROM: 'from@example.com',
  JWT_SIGNING_SECRET: 'test-jwt-secret',
  CLAUDE_API_KEY: 'test-claude-key',
  OPENAI_API_KEY: 'test-openai-key',
  ADMIN_DASHBOARD_KEY: 'test-admin-key',
};

function buildExtractBody(overrides: Partial<ExtractRequestBody> = {}): ExtractRequestBody {
  return {
    model: 'claude-haiku-4-5',
    max_tokens: 4096,
    system: 'You are an event extractor.',
    messages: [{ role: 'user', content: 'Extract events.' }],
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// detectProvider
// ---------------------------------------------------------------------------

describe('detectProvider', () => {
  it('returns anthropic for claude models', () => {
    expect(detectProvider('claude-haiku-4-5')).toBe('anthropic');
    expect(detectProvider('claude-sonnet-4-6')).toBe('anthropic');
  });

  it('returns openai for gpt models', () => {
    expect(detectProvider('gpt-5-nano')).toBe('openai');
    expect(detectProvider('gpt-5-nano-2025-08-07')).toBe('openai');
    expect(detectProvider('gpt-5.4-nano')).toBe('openai');
    expect(detectProvider('gpt-5.4-nano-2026-03-17')).toBe('openai');
  });

  it('returns openai for o-series models', () => {
    expect(detectProvider('o1-mini')).toBe('openai');
    expect(detectProvider('o3-mini')).toBe('openai');
    expect(detectProvider('o4-mini')).toBe('openai');
  });

  it('defaults to anthropic for unknown models', () => {
    expect(detectProvider('unknown-model')).toBe('anthropic');
  });
});

// ---------------------------------------------------------------------------
// buildProviderRequest — Anthropic (passthrough)
// ---------------------------------------------------------------------------

describe('buildProviderRequest — Anthropic', () => {
  it('builds Anthropic request with correct URL and headers', () => {
    const body = buildExtractBody();
    const req = buildProviderRequest(body, fakeEnv);

    expect(req.url).toBe('https://api.anthropic.com/v1/messages');
    expect(req.headers['x-api-key']).toBe('test-claude-key');
    expect(req.headers['anthropic-version']).toBe('2023-06-01');
    expect(req.headers['Content-Type']).toBe('application/json');
  });

  it('passes through model, system, messages, and max_tokens', () => {
    const body = buildExtractBody();
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.model).toBe('claude-haiku-4-5');
    expect(parsed.system).toBe('You are an event extractor.');
    expect(parsed.max_tokens).toBe(4096);
    expect(parsed.messages).toEqual([{ role: 'user', content: 'Extract events.' }]);
  });

  it('includes tools when present', () => {
    const tools = [{ type: 'web_search_20250305', name: 'web_search', max_uses: 5 }];
    const body = buildExtractBody({ tools });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.tools).toEqual(tools);
  });

  it('omits tools when not present', () => {
    const body = buildExtractBody();
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.tools).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// buildProviderRequest — OpenAI
// ---------------------------------------------------------------------------

describe('buildProviderRequest — OpenAI', () => {
  it('builds OpenAI request with correct URL and headers', () => {
    const body = buildExtractBody({ model: 'gpt-5-nano-2025-08-07' });
    const req = buildProviderRequest(body, fakeEnv);

    expect(req.url).toBe('https://api.openai.com/v1/responses');
    expect(req.headers['Authorization']).toBe('Bearer test-openai-key');
    expect(req.headers['Content-Type']).toBe('application/json');
  });

  it('maps system to instructions and max_tokens to max_output_tokens', () => {
    const body = buildExtractBody({ model: 'gpt-5-nano' });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.instructions).toBe('You are an event extractor.');
    expect(parsed.max_output_tokens).toBe(4096);
    expect(parsed.system).toBeUndefined();
    expect(parsed.max_tokens).toBeUndefined();
  });

  it('transforms string message content to input_text', () => {
    const body = buildExtractBody({
      model: 'gpt-5-nano',
      messages: [{ role: 'user', content: 'Hello' }],
    });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.input).toEqual([
      {
        type: 'message',
        role: 'user',
        content: [{ type: 'input_text', text: 'Hello' }],
      },
    ]);
  });

  it('transforms image content blocks', () => {
    const body = buildExtractBody({
      model: 'gpt-5-nano',
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: { type: 'base64', media_type: 'image/jpeg', data: 'ABCD1234' },
            },
            { type: 'text', text: 'What is this?' },
          ],
        },
      ],
    });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.input[0].content).toEqual([
      { type: 'input_image', image_url: 'data:image/jpeg;base64,ABCD1234' },
      { type: 'input_text', text: 'What is this?' },
    ]);
  });

  it('increases max_output_tokens when web_search tools are present', () => {
    const tools = [{ type: 'web_search_20250305', name: 'web_search', max_uses: 5 }];
    const body = buildExtractBody({ model: 'gpt-5-nano', max_tokens: 4096, tools });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.max_output_tokens).toBe(16384);
  });

  it('uses client max_tokens as max_output_tokens when no web_search tools', () => {
    const body = buildExtractBody({ model: 'gpt-5-nano', max_tokens: 2048 });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.max_output_tokens).toBe(2048);
  });

  it('transforms web_search tool', () => {
    const tools = [
      {
        type: 'web_search_20250305',
        name: 'web_search',
        max_uses: 5,
        user_location: { type: 'approximate', timezone: 'Europe/Paris', country: 'FR' },
      },
    ];
    const body = buildExtractBody({ model: 'gpt-5-nano', tools });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.tools).toEqual([
      {
        type: 'web_search',
        user_location: { type: 'approximate', timezone: 'Europe/Paris', country: 'FR' },
      },
    ]);
  });

  it('drops non-web-search tools', () => {
    const tools = [{ type: 'some_other_tool', name: 'other' }];
    const body = buildExtractBody({ model: 'gpt-5-nano', tools });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.tools).toBeUndefined();
  });

  it('omits tools when none provided', () => {
    const body = buildExtractBody({ model: 'gpt-5-nano' });
    const req = buildProviderRequest(body, fakeEnv);
    const parsed = JSON.parse(req.body);

    expect(parsed.tools).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// transformOpenAIResponse
// ---------------------------------------------------------------------------

describe('transformOpenAIResponse', () => {
  it('extracts text from output_text blocks', () => {
    const openaiResponse = {
      id: 'resp_123',
      status: 'completed',
      output: [
        { type: 'web_search_call', id: 'ws_1', status: 'completed' },
        {
          type: 'message',
          role: 'assistant',
          status: 'completed',
          content: [
            { type: 'output_text', text: '{"title": "Test Event"}', annotations: [] },
          ],
        },
      ],
    };

    const result = transformOpenAIResponse(openaiResponse);
    expect(result).not.toBeNull();
    expect(result!.content).toEqual([{ type: 'text', text: '{"title": "Test Event"}' }]);
    expect(result!.stop_reason).toBe('end_turn');
  });

  it('concatenates multiple output_text blocks', () => {
    const openaiResponse = {
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [
            { type: 'output_text', text: 'part1' },
            { type: 'output_text', text: 'part2' },
          ],
        },
      ],
    };

    const result = transformOpenAIResponse(openaiResponse);
    expect(result!.content).toEqual([
      { type: 'text', text: 'part1' },
      { type: 'text', text: 'part2' },
    ]);
  });

  it('skips non-message output items (reasoning, web_search_call)', () => {
    const openaiResponse = {
      status: 'completed',
      output: [
        { type: 'reasoning', content: [], summary: [] },
        { type: 'web_search_call', id: 'ws_1', status: 'completed' },
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'result' }],
        },
      ],
    };

    const result = transformOpenAIResponse(openaiResponse);
    expect(result!.content).toEqual([{ type: 'text', text: 'result' }]);
  });

  it('maps incomplete status with max_output_tokens to max_tokens', () => {
    const openaiResponse = {
      status: 'incomplete',
      incomplete_details: { reason: 'max_output_tokens' },
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'truncated' }],
        },
      ],
    };

    const result = transformOpenAIResponse(openaiResponse);
    expect(result!.stop_reason).toBe('max_tokens');
  });

  it('maps incomplete status without max_output_tokens to end_turn', () => {
    const openaiResponse = {
      status: 'incomplete',
      incomplete_details: { reason: 'content_filter' },
      output: [
        {
          type: 'message',
          content: [{ type: 'output_text', text: 'filtered' }],
        },
      ],
    };

    const result = transformOpenAIResponse(openaiResponse);
    expect(result!.stop_reason).toBe('end_turn');
  });

  it('returns empty content array when no message items in output', () => {
    const openaiResponse = {
      status: 'completed',
      output: [
        { type: 'web_search_call', id: 'ws_1', status: 'completed' },
      ],
    };

    const result = transformOpenAIResponse(openaiResponse);
    expect(result!.content).toEqual([]);
  });

  it('returns null for non-object input', () => {
    expect(transformOpenAIResponse(null)).toBeNull();
    expect(transformOpenAIResponse('string')).toBeNull();
    expect(transformOpenAIResponse(42)).toBeNull();
  });

  it('returns null when output is not an array', () => {
    expect(transformOpenAIResponse({ status: 'completed', output: 'not-array' })).toBeNull();
    expect(transformOpenAIResponse({ status: 'completed' })).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// extractUsage
// ---------------------------------------------------------------------------

describe('extractUsage', () => {
  it('extracts usage from OpenAI response', () => {
    const response = {
      id: 'resp_123',
      status: 'completed',
      usage: { input_tokens: 1500, output_tokens: 300, total_tokens: 1800 },
      output: [],
    };
    expect(extractUsage(response)).toEqual({ input_tokens: 1500, output_tokens: 300 });
  });

  it('extracts usage from Anthropic response', () => {
    const response = {
      id: 'msg_123',
      content: [{ type: 'text', text: 'hello' }],
      usage: { input_tokens: 2000, output_tokens: 500 },
      stop_reason: 'end_turn',
    };
    expect(extractUsage(response)).toEqual({ input_tokens: 2000, output_tokens: 500 });
  });

  it('returns null when usage is missing', () => {
    expect(extractUsage({ id: 'resp_123', output: [] })).toBeNull();
  });

  it('returns null when usage fields are not numbers', () => {
    expect(extractUsage({ usage: { input_tokens: 'bad', output_tokens: 100 } })).toBeNull();
  });

  it('returns null for non-object input', () => {
    expect(extractUsage(null)).toBeNull();
    expect(extractUsage(undefined)).toBeNull();
    expect(extractUsage('string')).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// calculateCost
// ---------------------------------------------------------------------------

describe('calculateCost', () => {
  it('calculates cost for gpt-5-nano', () => {
    const cost = calculateCost('gpt-5-nano-2025-08-07', { input_tokens: 1_000_000, output_tokens: 1_000_000 });
    // $0.05 input + $0.40 output = $0.45
    expect(cost).toBeCloseTo(0.45, 4);
  });

  it('calculates cost for gpt-5.4-nano', () => {
    const cost = calculateCost('gpt-5.4-nano-2026-03-17', { input_tokens: 1_000_000, output_tokens: 1_000_000 });
    // $0.20 input + $1.25 output = $1.45
    expect(cost).toBeCloseTo(1.45, 4);
  });

  it('calculates cost for claude-haiku-4-5', () => {
    const cost = calculateCost('claude-haiku-4-5', { input_tokens: 1_000_000, output_tokens: 1_000_000 });
    // $1.00 input + $5.00 output = $6.00
    expect(cost).toBeCloseTo(6.0, 4);
  });

  it('returns 0 for unknown model', () => {
    expect(calculateCost('unknown-model', { input_tokens: 1000, output_tokens: 500 })).toBe(0);
  });

  it('handles small token counts correctly', () => {
    const cost = calculateCost('gpt-5-nano-2025-08-07', { input_tokens: 1500, output_tokens: 300 });
    // (1500 * 0.05 + 300 * 0.40) / 1_000_000 = (75 + 120) / 1_000_000 = 0.000195
    expect(cost).toBeCloseTo(0.000195, 6);
  });
});
