import { describe, expect, it } from 'vitest';
import { validateExtractRequest } from '../src/validation';

function buildValidExtractRequest() {
  return {
    model: 'claude-haiku-4-5',
    max_tokens: 4096,
    system: 'You are an event extractor.',
    messages: [
      {
        role: 'user',
        content: 'Extract events from this image.',
      },
    ],
    tools: [
      {
        type: 'web_search_20250305',
        name: 'web_search',
        max_uses: 5,
      },
    ],
  };
}

describe('validateExtractRequest', () => {
  it('accepts a valid extraction request', () => {
    const result = validateExtractRequest(buildValidExtractRequest());
    expect(result).not.toBeNull();
    expect(result!.model).toBe('claude-haiku-4-5');
    expect(result!.max_tokens).toBe(4096);
  });

  it('accepts a request without tools', () => {
    const req = buildValidExtractRequest();
    delete (req as Record<string, unknown>).tools;
    const result = validateExtractRequest(req);
    expect(result).not.toBeNull();
    expect(result!.tools).toBeUndefined();
  });

  it('rejects disallowed model', () => {
    const req = buildValidExtractRequest();
    req.model = 'random-model-123';
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('accepts gpt-5-nano model', () => {
    const req = buildValidExtractRequest();
    req.model = 'gpt-5-nano';
    const result = validateExtractRequest(req);
    expect(result).not.toBeNull();
    expect(result!.model).toBe('gpt-5-nano');
  });

  it('accepts gpt-5-nano dated snapshot', () => {
    const req = buildValidExtractRequest();
    req.model = 'gpt-5-nano-2025-08-07';
    const result = validateExtractRequest(req);
    expect(result).not.toBeNull();
    expect(result!.model).toBe('gpt-5-nano-2025-08-07');
  });

  it('accepts gpt-5.4-nano model', () => {
    const req = buildValidExtractRequest();
    req.model = 'gpt-5.4-nano';
    const result = validateExtractRequest(req);
    expect(result).not.toBeNull();
  });

  it('accepts gpt-5.4-nano dated snapshot', () => {
    const req = buildValidExtractRequest();
    req.model = 'gpt-5.4-nano-2026-03-17';
    const result = validateExtractRequest(req);
    expect(result).not.toBeNull();
  });

  it('rejects empty model', () => {
    const req = buildValidExtractRequest();
    req.model = '';
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects max_tokens exceeding limit', () => {
    const req = buildValidExtractRequest();
    req.max_tokens = 10000;
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects max_tokens of zero', () => {
    const req = buildValidExtractRequest();
    req.max_tokens = 0;
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects negative max_tokens', () => {
    const req = buildValidExtractRequest();
    req.max_tokens = -1;
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects empty system prompt', () => {
    const req = buildValidExtractRequest();
    req.system = '';
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects missing system prompt', () => {
    const req = buildValidExtractRequest();
    delete (req as Record<string, unknown>).system;
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects empty messages array', () => {
    const req = buildValidExtractRequest();
    req.messages = [];
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects non-array messages', () => {
    const req = buildValidExtractRequest();
    (req as Record<string, unknown>).messages = 'not an array';
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects non-array tools', () => {
    const req = buildValidExtractRequest();
    (req as Record<string, unknown>).tools = 'not an array';
    expect(validateExtractRequest(req)).toBeNull();
  });

  it('rejects non-object input', () => {
    expect(validateExtractRequest(null)).toBeNull();
    expect(validateExtractRequest('string')).toBeNull();
    expect(validateExtractRequest(42)).toBeNull();
    expect(validateExtractRequest([])).toBeNull();
  });

  it('passes through messages and tools without deep validation', () => {
    const req = buildValidExtractRequest();
    req.messages = [{ role: 'user', content: [{ type: 'image', source: { type: 'base64', data: 'abc' } }] }];
    const result = validateExtractRequest(req);
    expect(result).not.toBeNull();
    expect(result!.messages).toEqual(req.messages);
  });
});
