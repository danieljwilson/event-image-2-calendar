import { buildDigestEmail } from './email';
import { issueAccessToken, verifyAccessToken, verifyDeviceSignature } from './security';
import { DeviceRecord, Env, EventPayload, StoredEventPayload } from './types';
import {
  isFreshTimestamp,
  jsonError,
  readJSONRequest,
  validateEventPayload,
  validateIssueTokenRequest,
  validateRegisterRequest,
} from './validation';

const DEVICE_PREFIX = 'device:';
const PENDING_PREFIX = 'pending:';
const SENT_PREFIX = 'sent:';
const RATE_LIMIT_PREFIX = 'ratelimit:';

const DEVICE_RECORD_TTL_SECONDS = 60 * 60 * 24 * 180;
const PENDING_EVENT_TTL_SECONDS = 60 * 60 * 24 * 30;
const SENT_EVENT_TTL_SECONDS = 60 * 60 * 24 * 7;

const MAX_DEVICE_EVENTS_PER_HOUR = 120;
const MAX_IP_EVENTS_PER_MINUTE = 30;

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

    if (request.method === 'POST' && url.pathname === '/events') {
      return handleEventPost(request, env);
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

  pending.sort((a, b) => Date.parse(a.event.startDate) - Date.parse(b.event.startDate));

  const chunkSize = 100;
  const totalChunks = Math.ceil(pending.length / chunkSize);

  for (let i = 0; i < totalChunks; i++) {
    const chunk = pending.slice(i * chunkSize, (i + 1) * chunkSize);
    const { subject, html } = buildDigestEmail(chunk.map((entry) => entry.event));
    const chunkSubject = totalChunks > 1 ? `${subject} [${i + 1}/${totalChunks}]` : subject;

    const sent = await sendDigestEmail(env, chunkSubject, html);
    if (!sent) {
      console.error('Digest email send failed at chunk', i + 1);
      return;
    }

    await archivePendingEntries(env, chunk);
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

async function sendDigestEmail(env: Env, subject: string, html: string): Promise<boolean> {
  const resendResponse = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: env.DIGEST_EMAIL_FROM,
      to: [env.DIGEST_EMAIL_TO],
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
