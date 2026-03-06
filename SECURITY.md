# Security Posture (March 6, 2026)

This document describes the current security state of the Event Image 2 Calendar project and operational expectations.

## System Overview

- iOS app captures event data and posts event payloads to a Cloudflare Worker endpoint.
- Cloudflare Worker stores pending events in KV, sends a daily digest via Resend, and moves processed items to a sent namespace prefix.
- Authentication now uses short-lived JWT access tokens issued by the Worker after device key signature verification.

## Current Security Controls

### 1. Auth and Identity

- Shared static `X-Auth-Token` app secret has been removed from the client and Worker.
- iOS now generates and stores a per-install P-256 signing key in Keychain and signs auth messages.
- Worker exposes:
  - `POST /auth/register` for device public key registration.
  - `POST /auth/token` for access token issuance after signature verification.
- `POST /events` requires `Authorization: Bearer <jwt>`.
- JWTs are:
  - HMAC-SHA256 signed with Worker secret `JWT_SIGNING_SECRET`.
  - Short-lived (10 minutes).
  - Scope-limited (`events:write`) and bound to a `device_id`.

### 2. Request Validation and Abuse Controls

- Worker enforces `application/json` content-type and body size limits.
- Structured validation is applied to:
  - Device register payloads.
  - Device token payloads.
  - Event payload schema (field types, lengths, timestamps, timezone validity, date ordering).
- Rate limiting (KV-backed counters) is enforced on `/events`:
  - Per-device hourly limit.
  - Per-IP per-minute limit.

### 3. Digest Pipeline Reliability

- KV listing for pending items now paginates using cursors.
- Pending events are loaded across pages, sorted by start date, and sent in batches.
- On successful email send, pending items are moved to sent prefix and removed from pending.
- Failures are logged and do not silently delete pending data.

### 4. Output Sanitization

- Email content escapes HTML text fields.
- `googleCalendarURL` is allowlisted and sanitized before being rendered into `href`.
- Only HTTPS calendar hosts are accepted.

### 5. Testing and CI

- Worker test suite covers:
  - JWT issuance/verification.
  - Device signature verification.
  - Event/register/token payload validation.
  - URL allowlisting.
  - KV pagination behavior.
- CI workflow now includes:
  - Worker dependency install, typecheck, and tests.
  - iOS simulator build validation.
  - Secret scanning (gitleaks).

## Secrets and Key Management

- Local app secrets live in `Secrets.xcconfig` (gitignored).
- `Secrets.example.xcconfig` is committed as non-secret template.
- Worker runtime secrets are managed via Wrangler secrets:
  - `RESEND_API_KEY`
  - `DIGEST_EMAIL_TO`
  - `JWT_SIGNING_SECRET`

### Rotation Guidance

- Rotate `JWT_SIGNING_SECRET` immediately if compromise is suspected.
- Rotation impact: all existing access tokens become invalid (expected).
- Keep token lifetime short (10 minutes) to reduce exposure window.

## Known Limitations / Remaining Risks

- Device identity is per-install, but there is no end-user account identity yet.
- Device registration is signature-verified but not hardware-attested.
- KV-based rate limiting is eventually consistent and not strongly atomic.
- No dedicated SIEM pipeline; logging is currently Worker console based.

## Recommended Next Hardening Steps

1. Add Apple App Attest verification for stronger app/device provenance.
2. Add user-level identity (e.g., Sign in with Apple) and bind events to user + device.
3. Move rate limiting to a stronger primitive (Durable Objects or edge-native WAF rules).
4. Add alerting pipeline for auth failures, rate-limit spikes, and digest send failures.
5. Add periodic dependency update automation and security patch cadence.
