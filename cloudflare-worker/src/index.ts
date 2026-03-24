import { buildDashboardHTML } from './dashboard';
import { buildDigestEmail } from './email';
import { buildProviderRequest, calculateCost, calculateCostBreakdown, detectProvider, extractUsage, transformOpenAIResponse } from './providers';
import { issueAccessToken, verifyAccessToken, verifyDeviceSignature } from './security';
import { DeviceRecord, DeviceUsageRecord, Env, EventPayload, ExtractionLog, GlobalUsageRecord, StoredEventPayload, TokenUsage } from './types';

import {
  isFreshTimestamp,
  jsonError,
  MAX_EXTRACT_BODY_CHARS,
  readJSONRequest,
  validateDevicePreferences,
  validateEventPayload,
  validateExtractRequest,
  validateIssueTokenRequest,
  validateRegisterRequest,
} from './validation';

const DEVICE_PREFIX = 'device:';
const PENDING_PREFIX = 'pending:';
const SENT_PREFIX = 'sent:';
const RATE_LIMIT_PREFIX = 'ratelimit:';
const USAGE_DEVICE_PREFIX = 'usage:device:';
const USAGE_GLOBAL_KEY = 'usage:global';
const EXTRACT_LOG_PREFIX = 'extractlog:';
const EXTRACT_LOG_TTL_SECONDS = 60 * 60 * 24 * 90; // 90 days

const DEVICE_RECORD_TTL_SECONDS = 60 * 60 * 24 * 180;
const PENDING_EVENT_TTL_SECONDS = 60 * 60 * 24 * 30;
const SENT_EVENT_TTL_SECONDS = 60 * 60 * 24 * 7;

const MAX_DEVICE_EVENTS_PER_HOUR = 120;
const MAX_IP_EVENTS_PER_MINUTE = 30;

// --- Extraction quotas (adjust these to change free/paid tier limits) ---
const FREE_TIER_DAILY_EXTRACTIONS = 20;
const MAX_IP_EXTRACTIONS_PER_MINUTE = 10;

// Provider API URLs and versions are managed in providers.ts

export interface PendingEventEntry {
  key: string;
  raw: string;
  event: EventPayload;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/auth/register') {
      return handleRegisterDevice(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/auth/token') {
      return handleIssueToken(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/extract') {
      return handleExtract(request, env);
    }

    if (request.method === 'POST' && url.pathname === '/events') {
      return handleEventPost(request, env);
    }

    if (request.method === 'PUT' && url.pathname === '/device/preferences') {
      return handleDevicePreferences(request, env);
    }

    if (request.method === 'DELETE' && url.pathname.startsWith('/events/')) {
      return handleEventDelete(request, env, url.pathname);
    }

    if (request.method === 'GET' && url.pathname === '/usage') {
      return handleGetUsage(request, env);
    }

    if (request.method === 'GET' && url.pathname === '/admin/dashboard') {
      return handleDashboard(url, env);
    }

    if (request.method === 'GET' && url.pathname === '/health') {
      return new Response('OK', { status: 200 });
    }

    return new Response('Not Found', { status: 404 });
  },

  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(sendDailyDigest(env));
  },
};

async function handleRegisterDevice(request: Request, env: Env): Promise<Response> {
  const parsed = await readJSONRequest(request);
  if ('error' in parsed) return parsed.error;

  const payload = validateRegisterRequest(parsed.data);
  if (!payload) {
    return jsonError(400, 'Invalid register payload');
  }

  if (!isFreshTimestamp(payload.timestamp)) {
    return jsonError(401, 'Expired registration signature');
  }

  const message = `register:${payload.deviceId}:${Math.floor(payload.timestamp)}`;
  const isValidSignature = await verifyDeviceSignature(payload.publicKey, message, payload.signature);
  if (!isValidSignature) {
    return jsonError(401, 'Invalid registration signature');
  }

  const key = deviceKey(payload.deviceId);
  const existingRaw = await env.EVENTS.get(key);
  let existing: DeviceRecord | null = null;

  if (existingRaw) {
    try {
      existing = JSON.parse(existingRaw) as DeviceRecord;
      if (existing.publicKey !== payload.publicKey) {
        return jsonError(409, 'Device key mismatch');
      }
    } catch {
      existing = null;
    }
  }

  const now = new Date().toISOString();
  const nextRecord: DeviceRecord = {
    deviceId: payload.deviceId,
    publicKey: payload.publicKey,
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
  };

  await env.EVENTS.put(key, JSON.stringify(nextRecord), {
    expirationTtl: DEVICE_RECORD_TTL_SECONDS,
  });

  return new Response(JSON.stringify({ registered: true }), {
    status: existing ? 200 : 201,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleIssueToken(request: Request, env: Env): Promise<Response> {
  const parsed = await readJSONRequest(request);
  if ('error' in parsed) return parsed.error;

  const payload = validateIssueTokenRequest(parsed.data);
  if (!payload) {
    return jsonError(400, 'Invalid token payload');
  }

  if (!isFreshTimestamp(payload.timestamp)) {
    return jsonError(401, 'Expired token signature');
  }

  const key = deviceKey(payload.deviceId);
  const existingRaw = await env.EVENTS.get(key);
  if (!existingRaw) {
    return jsonError(401, 'Device not registered');
  }

  let deviceRecord: DeviceRecord;
  try {
    deviceRecord = JSON.parse(existingRaw) as DeviceRecord;
  } catch {
    return jsonError(500, 'Invalid device record');
  }

  const message = `token:${payload.deviceId}:${Math.floor(payload.timestamp)}`;
  const isValidSignature = await verifyDeviceSignature(deviceRecord.publicKey, message, payload.signature);
  if (!isValidSignature) {
    return jsonError(401, 'Invalid token signature');
  }

  const token = await issueAccessToken(env, payload.deviceId);
  deviceRecord.updatedAt = new Date().toISOString();

  await env.EVENTS.put(key, JSON.stringify(deviceRecord), {
    expirationTtl: DEVICE_RECORD_TTL_SECONDS,
  });

  return new Response(
    JSON.stringify({
      accessToken: token.token,
      expiresAt: token.expiresAt,
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}

// ---------------------------------------------------------------------------
// Usage tracking
// ---------------------------------------------------------------------------

async function recordUsage(
  env: Env,
  deviceId: string,
  model: string,
  usage: TokenUsage
): Promise<void> {
  const now = new Date().toISOString();
  const cost = calculateCost(model, usage);

  // Update per-device aggregate
  const deviceKey = `${USAGE_DEVICE_PREFIX}${deviceId}`;
  const deviceRaw = await env.EVENTS.get(deviceKey);
  const deviceRecord: DeviceUsageRecord = deviceRaw
    ? JSON.parse(deviceRaw)
    : { deviceId, totalInputTokens: 0, totalOutputTokens: 0, totalCostUsd: 0, extractionCount: 0, lastModel: model, updatedAt: now };
  deviceRecord.totalInputTokens += usage.input_tokens;
  deviceRecord.totalOutputTokens += usage.output_tokens;
  deviceRecord.totalCostUsd += cost;
  deviceRecord.extractionCount += 1;
  deviceRecord.lastModel = model;
  deviceRecord.updatedAt = now;

  // Update global aggregate
  const globalRaw = await env.EVENTS.get(USAGE_GLOBAL_KEY);
  const globalRecord: GlobalUsageRecord = globalRaw
    ? JSON.parse(globalRaw)
    : { totalInputTokens: 0, totalOutputTokens: 0, totalCostUsd: 0, extractionCount: 0, updatedAt: now };
  globalRecord.totalInputTokens += usage.input_tokens;
  globalRecord.totalOutputTokens += usage.output_tokens;
  globalRecord.totalCostUsd += cost;
  globalRecord.extractionCount += 1;
  globalRecord.updatedAt = now;

  await Promise.all([
    env.EVENTS.put(deviceKey, JSON.stringify(deviceRecord), { expirationTtl: DEVICE_RECORD_TTL_SECONDS }),
    env.EVENTS.put(USAGE_GLOBAL_KEY, JSON.stringify(globalRecord)),
  ]);
}

async function recordExtractionLog(
  env: Env,
  opts: {
    deviceId: string;
    model: string;
    provider: string;
    modality: string | null;
    usage: TokenUsage | null;
    processingTimeSec: number;
    success: boolean;
    errorDetail: string | null;
  }
): Promise<void> {
  const id = crypto.randomUUID();
  const now = new Date();
  const dateStr = now.toISOString().slice(0, 10); // YYYY-MM-DD
  const costs = opts.usage
    ? calculateCostBreakdown(opts.model, opts.usage)
    : { input: 0, output: 0, total: 0 };

  const log: ExtractionLog = {
    id,
    timestamp: now.toISOString(),
    deviceId: opts.deviceId,
    model: opts.model,
    provider: opts.provider,
    modality: opts.modality,
    inputTokens: opts.usage?.input_tokens ?? 0,
    outputTokens: opts.usage?.output_tokens ?? 0,
    inputCostUsd: costs.input,
    outputCostUsd: costs.output,
    totalCostUsd: costs.total,
    processingTimeSec: opts.processingTimeSec,
    success: opts.success,
    errorDetail: opts.errorDetail,
  };

  const key = `${EXTRACT_LOG_PREFIX}${dateStr}:${id}`;
  await env.EVENTS.put(key, JSON.stringify(log), { expirationTtl: EXTRACT_LOG_TTL_SECONDS });
}

// ---------------------------------------------------------------------------
// Extraction handler
// ---------------------------------------------------------------------------

async function handleExtract(request: Request, env: Env): Promise<Response> {
  const claims = await authenticateEventRequest(request, env);
  if (!claims) {
    return jsonError(401, 'Unauthorized');
  }

  const dailyLimitOK = await enforceRateLimit(
    env,
    `extractdaily:${claims.device_id}`,
    FREE_TIER_DAILY_EXTRACTIONS,
    60 * 60 * 24
  );
  if (!dailyLimitOK) {
    return jsonError(429, 'Daily extraction limit reached');
  }

  const ipAddress = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const ipLimitOK = await enforceRateLimit(env, `extractip:${ipAddress}`, MAX_IP_EXTRACTIONS_PER_MINUTE, 60);
  if (!ipLimitOK) {
    return jsonError(429, 'IP rate limit exceeded');
  }

  const parsed = await readJSONRequest(request, MAX_EXTRACT_BODY_CHARS);
  if ('error' in parsed) return parsed.error;

  const extractBody = validateExtractRequest(parsed.data);
  if (!extractBody) {
    return jsonError(400, 'Invalid extraction request');
  }

  const providerReq = buildProviderRequest(extractBody, env);
  const provider = detectProvider(extractBody.model);
  const modality = extractBody.modality ?? null;

  const startTime = Date.now();
  let providerResponse: Response;
  try {
    providerResponse = await fetch(providerReq.url, {
      method: 'POST',
      headers: providerReq.headers,
      body: providerReq.body,
    });
  } catch {
    const elapsed = (Date.now() - startTime) / 1000;
    await recordExtractionLog(env, {
      deviceId: claims.device_id, model: extractBody.model, provider, modality,
      usage: null, processingTimeSec: elapsed, success: false, errorDetail: 'Failed to reach extraction provider',
    });
    return jsonError(502, 'Failed to reach extraction provider');
  }
  const processingTimeSec = (Date.now() - startTime) / 1000;

  // Anthropic: deserialize to capture usage, then pass through to iOS
  if (provider === 'anthropic') {
    if (!providerResponse.ok) {
      const errorBody = await providerResponse.text();
      await recordExtractionLog(env, {
        deviceId: claims.device_id, model: extractBody.model, provider, modality,
        usage: null, processingTimeSec, success: false, errorDetail: `HTTP ${providerResponse.status}: ${errorBody.slice(0, 200)}`,
      });
      return new Response(errorBody, {
        status: providerResponse.status,
        headers: { 'Content-Type': providerResponse.headers.get('Content-Type') ?? 'application/json' },
      });
    }

    let responseJSON: unknown;
    try {
      responseJSON = await providerResponse.json();
    } catch {
      await recordExtractionLog(env, {
        deviceId: claims.device_id, model: extractBody.model, provider, modality,
        usage: null, processingTimeSec, success: false, errorDetail: 'Invalid JSON from extraction provider',
      });
      return jsonError(502, 'Invalid JSON from extraction provider');
    }

    const usage = extractUsage(responseJSON);
    if (usage) {
      await recordUsage(env, claims.device_id, extractBody.model, usage);
    }
    await recordExtractionLog(env, {
      deviceId: claims.device_id, model: extractBody.model, provider, modality,
      usage, processingTimeSec, success: true, errorDetail: null,
    });

    return new Response(JSON.stringify(responseJSON), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // OpenAI: transform to Claude format, capture usage, inject into response
  if (!providerResponse.ok) {
    const errorBody = await providerResponse.text();
    await recordExtractionLog(env, {
      deviceId: claims.device_id, model: extractBody.model, provider, modality,
      usage: null, processingTimeSec, success: false, errorDetail: `HTTP ${providerResponse.status}: ${errorBody.slice(0, 200)}`,
    });
    return new Response(errorBody, {
      status: providerResponse.status,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let responseJSON: unknown;
  try {
    responseJSON = await providerResponse.json();
  } catch {
    await recordExtractionLog(env, {
      deviceId: claims.device_id, model: extractBody.model, provider, modality,
      usage: null, processingTimeSec, success: false, errorDetail: 'Invalid JSON from extraction provider',
    });
    return jsonError(502, 'Invalid JSON from extraction provider');
  }

  const usage = extractUsage(responseJSON);
  if (usage) {
    await recordUsage(env, claims.device_id, extractBody.model, usage);
  }
  await recordExtractionLog(env, {
    deviceId: claims.device_id, model: extractBody.model, provider, modality,
    usage, processingTimeSec, success: true, errorDetail: null,
  });

  const transformed = transformOpenAIResponse(responseJSON);
  if (!transformed) {
    return jsonError(502, 'Unexpected response format from extraction provider');
  }

  // Inject usage into transformed response so iOS can read it
  const responseBody: Record<string, unknown> = { ...transformed };
  if (usage) {
    responseBody.usage = usage;
  }

  return new Response(JSON.stringify(responseBody), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleGetUsage(request: Request, env: Env): Promise<Response> {
  const claims = await authenticateEventRequest(request, env);
  if (!claims) {
    return jsonError(401, 'Unauthorized');
  }

  const [deviceRaw, globalRaw] = await Promise.all([
    env.EVENTS.get(`${USAGE_DEVICE_PREFIX}${claims.device_id}`),
    env.EVENTS.get(USAGE_GLOBAL_KEY),
  ]);

  return new Response(
    JSON.stringify({
      device: deviceRaw ? JSON.parse(deviceRaw) : null,
      global: globalRaw ? JSON.parse(globalRaw) : null,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
}

async function handleDashboard(url: URL, env: Env): Promise<Response> {
  const key = url.searchParams.get('key');
  if (!key || key !== env.ADMIN_DASHBOARD_KEY) {
    return new Response('Unauthorized', { status: 401 });
  }

  const daysParam = parseInt(url.searchParams.get('days') ?? '7', 10);
  const days = Number.isFinite(daysParam) && daysParam > 0 ? Math.min(daysParam, 90) : 7;

  // List extraction log keys for the date range
  const logs: ExtractionLog[] = [];
  const startDate = new Date();
  startDate.setUTCDate(startDate.getUTCDate() - days);

  let cursor: string | undefined;
  do {
    const result = await env.EVENTS.list({
      prefix: EXTRACT_LOG_PREFIX,
      limit: 1000,
      cursor,
    });

    // Fetch values in parallel batches of 50
    const keys = result.keys;
    for (let i = 0; i < keys.length; i += 50) {
      const batch = keys.slice(i, i + 50);
      const values = await Promise.all(batch.map((k) => env.EVENTS.get(k.name)));
      for (const raw of values) {
        if (!raw) continue;
        try {
          const log = JSON.parse(raw) as ExtractionLog;
          if (new Date(log.timestamp) >= startDate) {
            logs.push(log);
          }
        } catch { /* skip malformed */ }
      }
    }

    cursor = result.list_complete ? undefined : result.cursor;
  } while (cursor);

  let html = buildDashboardHTML(logs, days);
  // Replace key placeholder in filter links
  html = html.replace(/KEY_PLACEHOLDER/g, encodeURIComponent(key));

  return new Response(html, {
    status: 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

async function handleEventPost(request: Request, env: Env): Promise<Response> {
  const claims = await authenticateEventRequest(request, env);
  if (!claims) {
    return jsonError(401, 'Unauthorized');
  }

  const deviceLimitOK = await enforceRateLimit(
    env,
    `device:${claims.device_id}`,
    MAX_DEVICE_EVENTS_PER_HOUR,
    60 * 60
  );
  if (!deviceLimitOK) {
    return jsonError(429, 'Device rate limit exceeded');
  }

  const ipAddress = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  const ipLimitOK = await enforceRateLimit(env, `ip:${ipAddress}`, MAX_IP_EVENTS_PER_MINUTE, 60);
  if (!ipLimitOK) {
    return jsonError(429, 'IP rate limit exceeded');
  }

  const parsed = await readJSONRequest(request);
  if ('error' in parsed) return parsed.error;

  const event = validateEventPayload(parsed.data);
  if (!event) {
    return jsonError(400, 'Invalid event payload');
  }

  const key = pendingEventKey(claims.device_id, event.id);

  const storedEvent: StoredEventPayload = {
    ...event,
    deviceId: claims.device_id,
  };

  await env.EVENTS.put(key, JSON.stringify(storedEvent), {
    expirationTtl: PENDING_EVENT_TTL_SECONDS,
  });

  return new Response(JSON.stringify({ success: true, key }), {
    status: 201,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleEventDelete(request: Request, env: Env, pathname: string): Promise<Response> {
  const claims = await authenticateEventRequest(request, env);
  if (!claims) {
    return jsonError(401, 'Unauthorized');
  }

  const eventId = pathname.replace('/events/', '');
  if (!eventId) {
    return jsonError(400, 'Missing event ID');
  }

  const key = pendingEventKey(claims.device_id, eventId);
  await env.EVENTS.delete(key);

  return new Response(JSON.stringify({ success: true, key }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleDevicePreferences(request: Request, env: Env): Promise<Response> {
  const claims = await authenticateEventRequest(request, env);
  if (!claims) {
    return jsonError(401, 'Unauthorized');
  }

  const parsed = await readJSONRequest(request);
  if ('error' in parsed) return parsed.error;

  const prefs = validateDevicePreferences(parsed.data);
  if (!prefs) {
    return jsonError(400, 'Invalid preferences payload');
  }

  const key = deviceKey(claims.device_id);
  const existingRaw = await env.EVENTS.get(key);
  if (!existingRaw) {
    return jsonError(404, 'Device not registered');
  }

  let deviceRecord: DeviceRecord;
  try {
    deviceRecord = JSON.parse(existingRaw) as DeviceRecord;
  } catch {
    return jsonError(500, 'Invalid device record');
  }

  if (prefs.digestEmail === null) {
    delete deviceRecord.digestEmail;
  } else {
    deviceRecord.digestEmail = prefs.digestEmail;
  }
  deviceRecord.updatedAt = new Date().toISOString();

  await env.EVENTS.put(key, JSON.stringify(deviceRecord), {
    expirationTtl: DEVICE_RECORD_TTL_SECONDS,
  });

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function authenticateEventRequest(request: Request, env: Env) {
  const authHeader = request.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return null;
  const token = authHeader.slice('Bearer '.length).trim();
  if (!token) return null;
  return verifyAccessToken(env, token);
}

export async function sendDailyDigest(env: Env): Promise<void> {
  const pending = await listPendingEvents(env);
  if (pending.length === 0) return;

  // Group events by deviceId
  const byDevice = new Map<string, PendingEventEntry[]>();
  for (const entry of pending) {
    // Extract deviceId from key: "pending:{deviceId}:{eventId}"
    const parts = entry.key.split(':');
    const deviceId = parts.length >= 3 ? parts[1] : 'unknown';
    const list = byDevice.get(deviceId) ?? [];
    list.push(entry);
    byDevice.set(deviceId, list);
  }

  for (const [deviceId, deviceEvents] of byDevice) {
    // Look up device record for digest email
    let recipientEmail = env.DIGEST_EMAIL_TO; // fallback
    if (deviceId !== 'unknown') {
      const deviceRaw = await env.EVENTS.get(deviceKey(deviceId));
      if (deviceRaw) {
        try {
          const record = JSON.parse(deviceRaw) as DeviceRecord;
          if (record.digestEmail) {
            recipientEmail = record.digestEmail;
          }
        } catch {
          // use fallback
        }
      }
    }

    deviceEvents.sort((a, b) => Date.parse(a.event.startDate) - Date.parse(b.event.startDate));

    const chunkSize = 100;
    const totalChunks = Math.ceil(deviceEvents.length / chunkSize);

    for (let i = 0; i < totalChunks; i++) {
      const chunk = deviceEvents.slice(i * chunkSize, (i + 1) * chunkSize);
      const { subject, html } = buildDigestEmail(chunk.map((entry) => entry.event));
      const chunkSubject = totalChunks > 1 ? `${subject} [${i + 1}/${totalChunks}]` : subject;

      const sent = await sendDigestEmail(env, chunkSubject, html, recipientEmail);
      if (!sent) {
        console.error(`Digest email send failed for device ${deviceId} at chunk ${i + 1}`);
        break;
      }

      await archivePendingEntries(env, chunk);
    }
  }
}

export async function listPendingEvents(env: Env): Promise<PendingEventEntry[]> {
  const entries: PendingEventEntry[] = [];
  let cursor: string | undefined;

  do {
    const page = await env.EVENTS.list({
      prefix: PENDING_PREFIX,
      limit: 1000,
      cursor,
    });

    for (const key of page.keys) {
      const raw = await env.EVENTS.get(key.name);
      if (!raw) continue;

      let parsed: unknown;
      try {
        parsed = JSON.parse(raw);
      } catch {
        continue;
      }

      const event = validateEventPayload(parsed);
      if (!event) continue;

      entries.push({ key: key.name, raw, event });
    }

    cursor = page.list_complete ? undefined : page.cursor;
  } while (cursor);

  return entries;
}

async function sendDigestEmail(env: Env, subject: string, html: string, recipient?: string): Promise<boolean> {
  const to = recipient ?? env.DIGEST_EMAIL_TO;
  const resendResponse = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: env.DIGEST_EMAIL_FROM,
      to: [to],
      subject,
      html,
    }),
  });

  if (!resendResponse.ok) {
    const detail = await resendResponse.text();
    console.error('Resend failure', resendResponse.status, detail);
    return false;
  }

  return true;
}

async function archivePendingEntries(env: Env, entries: PendingEventEntry[]): Promise<void> {
  for (const item of entries) {
    const sentKey = item.key.replace(PENDING_PREFIX, SENT_PREFIX);
    await env.EVENTS.put(sentKey, item.raw, { expirationTtl: SENT_EVENT_TTL_SECONDS });
    await env.EVENTS.delete(item.key);
  }
}

async function enforceRateLimit(
  env: Env,
  key: string,
  limit: number,
  windowSeconds: number
): Promise<boolean> {
  const now = Math.floor(Date.now() / 1000);
  const bucket = Math.floor(now / windowSeconds);
  const counterKey = `${RATE_LIMIT_PREFIX}${key}:${bucket}`;

  const currentCount = Number((await env.EVENTS.get(counterKey)) ?? '0');
  if (!Number.isFinite(currentCount) || currentCount >= limit) {
    return false;
  }

  await env.EVENTS.put(counterKey, String(currentCount + 1), {
    expirationTtl: windowSeconds + 60,
  });

  return true;
}

function deviceKey(deviceId: string): string {
  return `${DEVICE_PREFIX}${deviceId}`;
}

export function pendingEventKey(deviceId: string, eventId: string): string {
  return `${PENDING_PREFIX}${deviceId}:${eventId}`;
}
