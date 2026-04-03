import { DevicePreferencesRequest, EventPayload, IssueTokenRequest, RegisterDeviceRequest } from './types';

export const MAX_BODY_CHARS = 32768;
export const MAX_EXTRACT_BODY_CHARS = 8 * 1024 * 1024; // 8 MB for base64 image payloads
const MAX_EVENT_DESCRIPTION_LENGTH = 4000;
const MAX_SHORT_TEXT_LENGTH = 200;
const MAX_URL_LENGTH = 2048;
const DEVICE_ID_REGEX = /^[A-Za-z0-9-]{16,64}$/;
const BASE64URL_REGEX = /^[A-Za-z0-9_-]+$/;

export async function readJSONRequest(
  request: Request,
  maxBodyChars: number = MAX_BODY_CHARS
): Promise<{ data: unknown } | { error: Response }> {
  const contentType = request.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().includes('application/json')) {
    return { error: jsonError(415, 'Content-Type must be application/json') };
  }

  let text: string;
  try {
    text = await request.text();
  } catch {
    return { error: jsonError(400, 'Invalid request body') };
  }

  if (text.length === 0) {
    return { error: jsonError(400, 'Request body is required') };
  }

  if (text.length > maxBodyChars) {
    return { error: jsonError(413, 'Request body too large') };
  }

  try {
    return { data: JSON.parse(text) };
  } catch {
    return { error: jsonError(400, 'Invalid JSON body') };
  }
}

export function validateRegisterRequest(input: unknown): RegisterDeviceRequest | null {
  if (!isRecord(input)) return null;

  const deviceId = asString(input.deviceId);
  const publicKey = asString(input.publicKey);
  const signature = asString(input.signature);
  const timestamp = asNumber(input.timestamp);

  if (!deviceId || !publicKey || !signature || timestamp == null) return null;
  if (!DEVICE_ID_REGEX.test(deviceId)) return null;
  if (!BASE64URL_REGEX.test(publicKey) || !BASE64URL_REGEX.test(signature)) return null;
  if (!Number.isFinite(timestamp)) return null;

  return { deviceId, publicKey, signature, timestamp };
}

export function validateIssueTokenRequest(input: unknown): IssueTokenRequest | null {
  if (!isRecord(input)) return null;

  const deviceId = asString(input.deviceId);
  const signature = asString(input.signature);
  const timestamp = asNumber(input.timestamp);

  if (!deviceId || !signature || timestamp == null) return null;
  if (!DEVICE_ID_REGEX.test(deviceId)) return null;
  if (!BASE64URL_REGEX.test(signature)) return null;
  if (!Number.isFinite(timestamp)) return null;

  return { deviceId, signature, timestamp };
}

export function validateEventPayload(input: unknown): EventPayload | null {
  if (!isRecord(input)) return null;

  const id = normalizeString(input.id, 1, 128);
  const title = normalizeString(input.title, 1, MAX_SHORT_TEXT_LENGTH);
  const startDate = normalizeString(input.startDate, 1, 64);
  const endDate = normalizeString(input.endDate, 1, 64);
  const venue = normalizeString(input.venue, 0, MAX_SHORT_TEXT_LENGTH);
  const address = normalizeString(input.address, 0, MAX_SHORT_TEXT_LENGTH);
  const description = normalizeString(input.description, 0, MAX_EVENT_DESCRIPTION_LENGTH);
  const createdAt = normalizeString(input.createdAt, 1, 64);
  const googleCalendarURL = normalizeString(input.googleCalendarURL, 0, MAX_URL_LENGTH);
  const isAllDay = asBoolean(input.isAllDay);
  const timezoneRaw = input.timezone;

  if (!id || !title || !startDate || !endDate || description == null || venue == null || address == null || !createdAt || googleCalendarURL == null || isAllDay == null) {
    return null;
  }

  const timezone = normalizeTimezone(timezoneRaw);
  if (timezoneRaw !== null && timezone == null) return null;

  const start = Date.parse(startDate);
  const end = Date.parse(endDate);
  const created = Date.parse(createdAt);

  if (!Number.isFinite(start) || !Number.isFinite(end) || !Number.isFinite(created)) {
    return null;
  }

  if (end < start) return null;

  const category = asString(input.category) ?? null;
  const city = asString(input.city) ?? null;
  const eventStatus = asString(input.eventStatus) ?? null;

  return {
    id,
    title,
    startDate,
    endDate,
    venue,
    address,
    description,
    timezone,
    isAllDay,
    googleCalendarURL,
    createdAt,
    category,
    city,
    eventStatus,
  };
}

const ALLOWED_MODELS = new Set([
  'claude-haiku-4-5',
  'gpt-5-nano', 'gpt-5-nano-2025-08-07',
  'gpt-5.4-nano', 'gpt-5.4-nano-2026-03-17',
]);
const MAX_EXTRACT_TOKENS = 4096;

export interface ExtractRequestBody {
  model: string;
  max_tokens: number;
  system: string;
  messages: unknown[];
  tools?: unknown[];
  modality?: string;
}

export function validateExtractRequest(input: unknown): ExtractRequestBody | null {
  if (!isRecord(input)) return null;

  const model = asString(input.model);
  if (!model || !ALLOWED_MODELS.has(model)) return null;

  const maxTokens = asNumber(input.max_tokens);
  if (maxTokens == null || maxTokens < 1 || maxTokens > MAX_EXTRACT_TOKENS) return null;

  const system = asString(input.system);
  if (!system || system.length === 0) return null;

  if (!Array.isArray(input.messages) || input.messages.length === 0) return null;

  const result: ExtractRequestBody = {
    model,
    max_tokens: maxTokens,
    system,
    messages: input.messages,
  };

  if (input.tools !== undefined) {
    if (!Array.isArray(input.tools)) return null;
    result.tools = input.tools;
  }

  const VALID_MODALITIES = new Set(['image', 'url', 'text', 'social']);
  if (input.modality !== undefined) {
    const modality = asString(input.modality);
    if (modality && VALID_MODALITIES.has(modality)) {
      result.modality = modality;
    }
  }

  return result;
}

// ---------------------------------------------------------------------------
// Client error report validation
// ---------------------------------------------------------------------------

const VALID_ERROR_SOURCE_TYPES = new Set(['image', 'url', 'text', 'social']);

export interface ErrorReportBody {
  eventId: string;
  errorType: string;
  errorMessage: string;
  sourceType: string;
  imageSizeBytes: number | null;
  attemptCount: number;
  elapsedSeconds: number;
  isRetryable: boolean;
  appVersion: string;
  buildNumber: string;
  deviceModel: string;
  iOSVersion: string;
}

export function validateErrorReport(input: unknown): ErrorReportBody | null {
  if (!isRecord(input)) return null;

  const eventId = normalizeString(input.eventId, 1, 128);
  const errorType = normalizeString(input.errorType, 1, 100);
  const errorMessage = normalizeString(input.errorMessage, 1, 1000);
  const sourceType = asString(input.sourceType);
  const attemptCount = asNumber(input.attemptCount);
  const elapsedSeconds = asNumber(input.elapsedSeconds);
  const isRetryable = asBoolean(input.isRetryable);
  const appVersion = normalizeString(input.appVersion, 1, 20);
  const buildNumber = normalizeString(input.buildNumber, 1, 20);
  const deviceModel = normalizeString(input.deviceModel, 1, 100);
  const iOSVersion = normalizeString(input.iOSVersion, 1, 20);

  if (!eventId || !errorType || !errorMessage || !sourceType || !appVersion || !buildNumber || !deviceModel || !iOSVersion) return null;
  if (!VALID_ERROR_SOURCE_TYPES.has(sourceType)) return null;
  if (attemptCount == null || attemptCount < 1 || attemptCount > 10) return null;
  if (elapsedSeconds == null || elapsedSeconds < 0 || elapsedSeconds > 600) return null;
  if (isRetryable == null) return null;

  const imageSizeBytes = asNumber(input.imageSizeBytes) ?? null;

  return {
    eventId,
    errorType,
    errorMessage,
    sourceType,
    imageSizeBytes,
    attemptCount,
    elapsedSeconds,
    isRetryable,
    appVersion,
    buildNumber,
    deviceModel,
    iOSVersion,
  };
}

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function validateDevicePreferences(input: unknown): DevicePreferencesRequest | null {
  if (!isRecord(input)) return null;

  const digestEmail = input.digestEmail;
  if (digestEmail === null) {
    return { digestEmail: null };
  }

  const emailStr = asString(digestEmail);
  if (!emailStr) return null;
  const trimmed = emailStr.trim();
  if (trimmed.length === 0) return { digestEmail: null };
  if (trimmed.length > 320) return null;
  if (!EMAIL_REGEX.test(trimmed)) return null;

  return { digestEmail: trimmed };
}

export function isFreshTimestamp(timestamp: number, maxSkewSeconds = 300): boolean {
  if (!Number.isFinite(timestamp)) return false;
  const now = Math.floor(Date.now() / 1000);
  return Math.abs(now - Math.floor(timestamp)) <= maxSkewSeconds;
}

export function jsonError(status: number, error: string): Response {
  return new Response(JSON.stringify({ error }), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function normalizeTimezone(input: unknown): string | null {
  if (input === null || input === undefined) return null;
  const value = normalizeString(input, 1, 64);
  if (!value) return null;

  try {
    Intl.DateTimeFormat('en-US', { timeZone: value });
    return value;
  } catch {
    return null;
  }
}

function normalizeString(input: unknown, minLength: number, maxLength: number): string | null {
  const value = asString(input);
  if (value == null) return null;
  const trimmed = value.trim();
  if (trimmed.length < minLength) return null;
  if (trimmed.length > maxLength) return null;
  return trimmed;
}

function asString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === 'number' ? value : null;
}

function asBoolean(value: unknown): boolean | null {
  return typeof value === 'boolean' ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
