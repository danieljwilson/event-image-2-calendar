# Roadmap

Status of Event Snap features and the path to a production-ready App Store release.

## Completed

### Core Functionality
- [x] Event extraction from poster photos via LLM vision API (multi-provider)
- [x] Structured prompt with cultural event detection (vernissage, festival, apéro, etc.)
- [x] SwiftData persistence with event lifecycle (processing → ready → added/dismissed)
- [x] Background processing via `UIApplication.beginBackgroundTask`
- [x] City-level location context for extraction accuracy

### Calendar Integration
- [x] Google Calendar via URL scheme (no OAuth)
- [x] ICS file export via share sheet
- [x] All-day event support (correct yyyyMMdd format, exclusive end dates)
- [x] Multi-day event support with multi-date selection and full-range options
- [x] Timed multi-day events: recurring performances (ballet, concerts) grouped as single event with date selection, preserving performance times
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
- [x] Image→URL extraction fallback for shares with poor preview images (Instagram, etc.)
- [x] Substantive text filtering: skip non-content share text (short boilerplate, bare URLs) in URL extraction path
- [x] Source-aware error messages (image/link/share/text) based on available extraction sources
- [x] Social media extraction (Instagram, Facebook): adaptive text threshold (15 chars for social, 50 for regular) + dedicated social-aware prompt that uses caption text and web search to find events indirectly when pages are auth-walled
- [x] Social media OG metadata prefetch: fetch `og:title`, `og:description`, `og:image` from Instagram/Facebook URLs using Facebook crawler UA, then route through vision or text extraction with full context

### Extraction Quality
- [x] LLM web search tool for verifying/completing event details in a single API call (Claude `web_search_20250305` / OpenAI `web_search`)
- [x] User location context (timezone + country) for localized web search results
- [x] Missing date handling: events without determinable dates flagged as failed with user-editable date pickers
- [x] Strengthened prompts requiring `start_datetime` populated from visible times (not just description)
- [x] Separate date/time certainty: `date_confirmed` and `time_confirmed` flags preserve extracted partial info (e.g., time known but date uncertain)
- [x] Focused DateCorrectionSheet that shows only the missing picker (date, time, or both) instead of full EventDetailView
- [x] Consistency enforcement: all events from the same image share date certainty; day-of-week names explicitly excluded as confirmed dates
- [x] Past event detection: events with dates in the past are flagged as failed with user-correctable date editing
- [x] User-configurable extraction language: description field output in chosen language (default English), titles/venues kept in original language
- [x] DateCorrectionSheet auto-syncs end date when start date changes, preserving extracted duration
- [x] Processed events grouped: next 3 "Coming Up" prominently, remainder collapsed by month

### Digest Pipeline
- [x] Cloudflare Worker with authenticated event ingestion
- [x] P-256 device key registration + ECDSA signature verification
- [x] Short-lived JWT access tokens (10 min, HMAC-SHA256)
- [x] KV-based rate limiting (per-device hourly, per-IP per-minute)
- [x] Cursor-paginated KV reads for digest assembly
- [x] Batched HTML digest email via Resend
- [x] Output sanitization (HTML escaping, URL allowlisting)
- [x] Digest auto-queues on extraction success, dequeues on all add/dismiss/delete paths (reminder-based)
- [x] Worker `DELETE /events/:id` endpoint for removing acted-on events from digest queue
- [x] Local iOS digest outbox with queued/sending/sent/failed retry state
- [x] Idempotent Worker `/events` writes keyed by device + event ID
- [x] Per-chunk digest archival after each successful email send
- [x] All-day event support in digest payload + email rendering
- [x] Settings view with digest email opt-out, email address entry, and camera-on-launch preference
- [x] Per-device digest email: `PUT /device/preferences` stores email on DeviceRecord, cron sends per-device
- [x] Digest email entry in onboarding + settings with server sync via WorkerAuthService

### Infrastructure
- [x] XcodeGen project generation
- [x] CI pipeline: worker typecheck + tests, iOS simulator build, gitleaks
- [x] Multi-provider LLM extraction: Worker translation layer (`providers.ts`) auto-routes by model prefix — `gpt-*` → OpenAI Responses API, `claude-*` → Anthropic Messages API. Currently testing GPT-5 nano (`gpt-5-nano-2025-08-07`); fallback: GPT-5.4 nano (`gpt-5.4-nano-2026-03-17`) or Claude Haiku 4.5. One-line switch via `extractionModel` constant in `ClaudeAPIService.swift`.

---

## Phase 0: Secure Inference & Environment Separation

Priority: **Critical** — must be complete before any public beta or App Store submission.

### Backend-proxy Claude access
- [x] Move Claude extraction behind a trusted backend/worker endpoint (`POST /extract`)
- [x] Remove `CLAUDE_API_KEY` from the app bundle / `Info.plist`
- [x] Keep Anthropic credentials server-side only (Wrangler secret)
- [x] Apply request size limits (2MB body, model allowlist, max_tokens cap) and extraction quotas (50/device/hour, 10/IP/minute)
- [x] Add cost/budget monitoring for LLM usage — Worker captures token usage + cost per extraction, stores per-device and global aggregates in KV, iOS displays in Settings via `GET /usage`

### Environment separation
- [ ] Create distinct Cloudflare Worker environments for `dev`, `staging`, and `production`
- [ ] Use separate KV namespaces and secrets per environment
- [ ] Document deploy/promotion flow from staging to production
- [ ] Configure a verified production Resend sender domain

## Paperclip Integration

Priority: **High** — adopt [Paperclip](https://github.com/paperclipai/paperclip) for AI agent orchestration.

Paperclip is an open-source Node.js server + React UI that orchestrates teams of AI agents with org charts, budgets, governance, goal alignment, and task coordination. Integrating Paperclip would move Event Snap's extraction pipeline and development workflow from ad-hoc single-agent calls to a managed, auditable multi-agent system.

### Evaluation & Setup
- [ ] Deploy Paperclip locally and evaluate orchestration model against Event Snap's extraction pipeline
- [ ] Define agent roles: extraction agent (Claude vision), enrichment agent (web search), quality-check agent (date/time validation)
- [ ] Map current `BackgroundEventProcessor` → `ClaudeAPIService` flow to Paperclip task/ticket model

### Extraction Pipeline Migration
- [ ] Move image extraction behind a Paperclip-managed agent with budget controls and cost tracking
- [ ] Add a validation agent that cross-checks extracted dates/times against web search results before marking `date_confirmed`
- [ ] Use Paperclip's heartbeat system for scheduled digest assembly and retry of failed extractions
- [ ] Replace manual retry logic with Paperclip's built-in task lifecycle and delegation

### Development Workflow
- [ ] Use Paperclip to coordinate coding agents (Cursor, Claude Code) for parallel feature development
- [ ] Set up goal hierarchy: product goals → feature tasks → agent assignments
- [ ] Configure budget limits per agent to control API costs during development
- [ ] Adopt [Superpowers](https://github.com/obra/superpowers) agentic skills framework for structured development methodology
- [ ] Integrate Superpowers brainstorming + spec-writing workflow into Paperclip's goal/task pipeline
- [ ] Use Superpowers subagent-driven-development for plan execution with two-stage review (spec compliance, then code quality)
- [ ] Enforce Superpowers TDD workflow (RED-GREEN-REFACTOR) across all coding agents via skill injection
- [ ] Use Superpowers git worktrees for parallel feature branches managed by Paperclip's task assignments

### Production Operations
- [ ] Paperclip dashboard for monitoring extraction success rates, costs, and agent health
- [ ] Governance rules for extraction quality thresholds (auto-pause agents with high error rates)
- [ ] Integrate Paperclip's audit log with the existing Cloudflare Worker logging infrastructure

---

## Phase 1: Polish & Testing

Priority: **High** — prerequisite for reliable daily use.

- [ ] End-to-end device testing of Share Extension (images from Photos, URLs from Safari/Instagram)
- [ ] End-to-end testing of multi-day event flow (single day selection + full range)
- [ ] Manual QA matrix covering Photos, Camera, Safari, Instagram, Eventbrite, and plain-text shares
- [x] Onboarding flow (7-page App Store, 9-page TestFlight: features, permissions, digest toggle, error feedback, thank you)
- [x] Onboarding polish: progress bar, navigation chevrons, consistent layout, keyboard dismissal, reactive permission status, digest toggle with conditional email field
- [x] TestFlight build uploaded + App Store Connect record created
- [x] In-app feedback: Settings row + screenshot-triggered prompt via MFMailComposeViewController, with local feedback log
- [ ] TestFlight beta cycle with external testers and bug triage
- [ ] Minimal iOS automated tests for calendar formatting, event parsing, and persistence recovery
- [ ] Basic UI smoke test for the happy-path extraction flow
- [x] Client crash reporting via MetricKit (`CrashReportingService`) + improved debug logging in Share Extension and BackgroundEventProcessor
- [x] Debug log viewer in Settings > Diagnostics for viewing Share Extension and extraction logs
- [x] Graceful error handling for network failures and API errors
- [x] Loading indicators during extraction
- [x] Retry logic for transient failures (with backoff)
- [x] Edge cases: very large images (progressive JPEG quality reduction), unsupported formats, posters with no event info
- [x] Multi-day all-day events skip time confirmation and go directly to ready status
- [x] Multi-event image extraction (single image → multiple PersistedEvents)

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
- [ ] Per-user digest preferences (frequency customization — opt-in/out and email already implemented per-device)
- [x] Per-device digest recipient email via `PUT /device/preferences` (replaces single global `DIGEST_EMAIL_TO`)
- [ ] Privacy policy, support URL, and account metadata required for Sign in with Apple
- [ ] Account deletion / data removal flow if user accounts ship publicly
- [ ] Feature flag for gradual enforcement (`ENFORCE_USER_AUTH`)

## Phase 4: Production Release

Priority: **Medium** — final steps for App Store submission.

### Monitoring & Operations
- [ ] Structured security event logging (auth, rate-limit, digest failures)
- [ ] Structured application logging for extraction failures, share import failures, and digest send failures
- [ ] Log export to centralized sink
- [ ] Alert policies with defined thresholds and severities
- [ ] Budget / cost alerts for Anthropic and Resend usage
- [ ] Incident response runbook
- [ ] Rollback runbook for Worker deploys and auth/config changes
- [ ] Anthropic outage and Resend outage operational playbooks

### App Store Preparation
- [ ] Privacy labels (camera, location, network usage declarations)
- [ ] App Store screenshots and description
- [ ] App review guidelines compliance check
- [ ] Final staging dry-run covering extraction, auth, digest, and alerts
- [ ] Production rollout checklist with owner + timing

### Cleanup
- [ ] Remove device-only auth fallback paths
- [ ] Remove feature flags after full enforcement
- [ ] Dependency update automation

## Meta oEmbed API Migration

Priority: **Low** — current OG tag scraping works; oEmbed is the proper long-term approach.

- [ ] Create Meta app and request "Meta oEmbed Read" app review approval
- [ ] Store Meta app access token in Worker secrets
- [ ] Migrate social media metadata fetch from OG tag scraping to Meta oEmbed API (`GET /v25.0/instagram_oembed` / `/oembed_post`) — returns structured caption HTML, author name, thumbnail URL
- [ ] Remove client-side OG fetch in favor of Worker-side oEmbed call (keeps secrets server-side)

## Deferred Infrastructure Escalation

These are intentionally deferred until scale or reliability requirements justify the added complexity.

- [ ] Fully atomic digest queue via D1 transactions or a Durable Object coordinator
- [ ] Exactly-once digest send/ack semantics across email delivery and queue archival
- [ ] Replace KV-backed digest queue with stronger coordination only if current idempotent + retryable design proves insufficient

---

## Known Limitations

These are accepted trade-offs in the current architecture:

| Limitation | Impact | Resolution Phase |
|-----------|--------|-----------------|
| ~~Claude API key currently shipped in the client app bundle~~ | ~~Extractable secret, direct API abuse/cost risk~~ | ~~Phase 0~~ (resolved) |
| Device-only identity (no user accounts) | Can't bind events to a person across devices | Phase 3 |
| No hardware attestation | Scripted clients could register fake devices | Phase 2 |
| KV rate limiting eventually consistent | Brief burst windows possible | Phase 2 |
| No monitoring/alerting | Security events only visible in Worker console logs | Phase 4 |
| ~~No iOS crash reporting / client telemetry~~ | ~~App or Share Extension failures are hard to diagnose in production~~ | ~~Phase 1~~ (resolved) |
| Digest queue is idempotent and retryable but not fully atomic | A narrow duplicate-send window remains if email succeeds and archival fails before completion | Deferred infrastructure escalation |
| Google Calendar via URL (no OAuth) | User must manually confirm event in browser | Acceptable trade-off |

## Release Readiness Checklist

Before App Store submission:

- [ ] All Phase 0 items complete
- [ ] All Phase 1 items complete
- [ ] All Phase 2 items complete
- [ ] Phase 3 at minimum: Sign in with Apple functional
- [ ] CI passing on all checks
- [ ] TestFlight beta completed without open Sev-1 / Sev-2 issues
- [ ] No Anthropic secrets in shipped client binaries
- [ ] Security alerts tested end-to-end in staging
- [ ] JWT key rotation dry-run executed
- [ ] Worker staging and production environments verified as isolated
- [ ] Privacy labels accurate
- [ ] No secrets in committed code (gitleaks clean)
