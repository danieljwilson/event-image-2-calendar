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

export interface Env {
  EVENTS: KVNamespace;
  RESEND_API_KEY: string;
  DIGEST_EMAIL_TO: string;
  DIGEST_EMAIL_FROM: string;
  JWT_SIGNING_SECRET: string;
  CLAUDE_API_KEY: string;
}
