# Roadmap

Status of Event Snap features and the path to a production-ready App Store release.

## Completed

### Core Functionality
- [x] Event extraction from poster photos via Claude vision API
- [x] Structured prompt with cultural event detection (vernissage, festival, apéro, etc.)
- [x] SwiftData persistence with event lifecycle (processing → ready → added/dismissed)
- [x] Background processing via `UIApplication.beginBackgroundTask`
- [x] City-level location context for extraction accuracy

### Calendar Integration
- [x] Google Calendar via URL scheme (no OAuth)
- [x] ICS file export via share sheet
- [x] All-day event support (correct yyyyMMdd format, exclusive end dates)
- [x] Multi-day event support with single-day picker and full-range options
- [x] URL auto-linking in event descriptions

### Share Extension
- [x] iOS Share Extension accepting images, URLs, and text
- [x] File-based handoff via App Groups
- [x] Darwin notification for real-time pickup
- [x] URL-based event extraction (Eventbrite, Meetup, etc.)
- [x] Memory-efficient image handling via ImageIO downsampling (share extension safe)
- [x] Multi-strategy page content fetching (desktop UA → Facebook crawler UA → Instagram embed)
- [x] Text-based extraction from page content when no image available
- [x] OG metadata extraction (image, title, description) with HTML body text fallback

### Digest Pipeline
- [x] Cloudflare Worker with authenticated event ingestion
- [x] P-256 device key registration + ECDSA signature verification
- [x] Short-lived JWT access tokens (10 min, HMAC-SHA256)
- [x] KV-based rate limiting (per-device hourly, per-IP per-minute)
- [x] Cursor-paginated KV reads for digest assembly
- [x] Batched HTML digest email via Resend
- [x] Output sanitization (HTML escaping, URL allowlisting)

### Infrastructure
- [x] XcodeGen project generation
- [x] CI pipeline: worker typecheck + tests, iOS simulator build, gitleaks

---

## Phase 1: Polish & Testing

Priority: **High** — prerequisite for reliable daily use.

- [ ] End-to-end device testing of Share Extension (images from Photos, URLs from Safari/Instagram)
- [ ] End-to-end testing of multi-day event flow (single day selection + full range)
- [x] Graceful error handling for network failures and API errors
- [x] Loading indicators during extraction
- [x] Retry logic for transient failures (with backoff)
- [x] Edge cases: very large images, unsupported formats, posters with no event info

## Phase 2: Security Hardening

Priority: **High** — required before public release.

### Apple App Attest
- [ ] Generate App Attest key on first launch, store key ID in Keychain
- [ ] Worker endpoint for attestation challenge (`/attest/challenge`)
- [ ] Attestation verification on device registration
- [ ] Assertion counter + replay protection
- [ ] Feature flag for gradual rollout (`ENFORCE_APP_ATTEST`)

### Stronger Rate Limiting
- [ ] Durable Object rate limiter with atomic counters
- [ ] Remove KV counter dependency in write path when DO enforced
- [ ] Cloudflare WAF rate rule for `/events` endpoint
- [ ] Feature flag (`ENFORCE_DO_RATE_LIMIT`)

### JWT Key Rotation
- [ ] Multi-key JWT model with `kid` header
- [ ] Active + grace key support (overlap window for zero-downtime rotation)
- [ ] Automated rotation workflow (GitHub Actions)
- [ ] Rotation runbook tests (new valid, grace valid, retired rejected)

## Phase 3: User Identity & Authorization

Priority: **Medium** — needed for multi-user production scale.

- [ ] Sign in with Apple integration (iOS + Worker token exchange)
- [ ] Worker validates Apple identity tokens via JWKS
- [ ] User-bound access tokens (JWT includes `user_id`)
- [ ] Events stored with `userId` metadata
- [ ] Per-user digest preferences (opt-in/out, frequency)
- [ ] Feature flag for gradual enforcement (`ENFORCE_USER_AUTH`)

## Phase 4: Production Release

Priority: **Medium** — final steps for App Store submission.

### Monitoring & Operations
- [ ] Structured security event logging (auth, rate-limit, digest failures)
- [ ] Log export to centralized sink
- [ ] Alert policies with defined thresholds and severities
- [ ] Incident response runbook

### App Store Preparation
- [ ] Privacy labels (camera, location, network usage declarations)
- [ ] App Store screenshots and description
- [ ] App review guidelines compliance check
- [ ] Staging/production environment separation for Worker

### Cleanup
- [ ] Remove device-only auth fallback paths
- [ ] Remove feature flags after full enforcement
- [ ] Dependency update automation

---

## Known Limitations

These are accepted trade-offs in the current architecture:

| Limitation | Impact | Resolution Phase |
|-----------|--------|-----------------|
| Device-only identity (no user accounts) | Can't bind events to a person across devices | Phase 3 |
| No hardware attestation | Scripted clients could register fake devices | Phase 2 |
| KV rate limiting eventually consistent | Brief burst windows possible | Phase 2 |
| No monitoring/alerting | Security events only visible in Worker console logs | Phase 4 |
| Google Calendar via URL (no OAuth) | User must manually confirm event in browser | Acceptable trade-off |

## Release Readiness Checklist

Before App Store submission:

- [ ] All Phase 1 items complete
- [ ] All Phase 2 items complete
- [ ] Phase 3 at minimum: Sign in with Apple functional
- [ ] CI passing on all checks
- [ ] Security alerts tested end-to-end in staging
- [ ] JWT key rotation dry-run executed
- [ ] Privacy labels accurate
- [ ] No secrets in committed code (gitleaks clean)
