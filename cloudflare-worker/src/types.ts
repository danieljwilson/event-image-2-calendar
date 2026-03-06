export interface EventPayload {
  id: string;
  title: string;
  startDate: string;
  endDate: string;
  venue: string;
  address: string;
  description: string;
  timezone: string | null;
  googleCalendarURL: string;
  createdAt: string;
}

export interface Env {
  EVENTS: KVNamespace;
  RESEND_API_KEY: string;
  DIGEST_EMAIL_TO: string;
  DIGEST_EMAIL_FROM: string;
  AUTH_TOKEN: string;
}
