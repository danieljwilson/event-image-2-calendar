export interface EventPayload {
  id: string;
  title: string;
  startDate: string;
  endDate: string;
  venue: string;
  address: string;
  description: string;
  timezone: string | null;
  isAllDay: boolean;
  googleCalendarURL: string;
  createdAt: string;
  category: string | null;
  city: string | null;
  eventStatus: string | null;
}

export interface StoredEventPayload extends EventPayload {
  deviceId: string;
}

export interface DeviceRecord {
  deviceId: string;
  publicKey: string;
  digestEmail?: string;
  createdAt: string;
  updatedAt: string;
}

export interface DevicePreferencesRequest {
  digestEmail: string | null;
}

export interface RegisterDeviceRequest {
  deviceId: string;
  publicKey: string;
  timestamp: number;
  signature: string;
}

export interface IssueTokenRequest {
  deviceId: string;
  timestamp: number;
  signature: string;
}

export interface AccessTokenClaims {
  sub: string;
  device_id: string;
  scope: string;
  iss: string;
  aud: string;
  iat: number;
  exp: number;
}

// ---------------------------------------------------------------------------
// Usage tracking
// ---------------------------------------------------------------------------

export interface TokenUsage {
  input_tokens: number;
  output_tokens: number;
}

export interface ModelPricing {
  input_per_million: number;   // USD per 1M input tokens
  output_per_million: number;  // USD per 1M output tokens
}

export interface DeviceUsageRecord {
  deviceId: string;
  totalInputTokens: number;
  totalOutputTokens: number;
  totalCostUsd: number;
  extractionCount: number;
  lastModel: string;
  updatedAt: string;
}

export interface GlobalUsageRecord {
  totalInputTokens: number;
  totalOutputTokens: number;
  totalCostUsd: number;
  extractionCount: number;
  updatedAt: string;
}

export interface ExtractionLog {
  id: string;
  timestamp: string;
  deviceId: string;
  model: string;
  provider: string;
  modality: string | null;
  inputTokens: number;
  outputTokens: number;
  inputCostUsd: number;
  outputCostUsd: number;
  totalCostUsd: number;
  processingTimeSec: number;
  success: boolean;
  errorDetail: string | null;
}

// ---------------------------------------------------------------------------
// Client error reports
// ---------------------------------------------------------------------------

export interface ClientErrorReport {
  id: string;
  timestamp: string;
  deviceId: string;
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

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

export interface Env {
  EVENTS: KVNamespace;
  RESEND_API_KEY: string;
  DIGEST_EMAIL_TO: string;
  DIGEST_EMAIL_FROM: string;
  JWT_SIGNING_SECRET: string;
  CLAUDE_API_KEY: string;
  OPENAI_API_KEY: string;
  ADMIN_DASHBOARD_KEY: string;
}
