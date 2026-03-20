# Architecture

Event Snap is an iOS app that extracts event details from poster photos (or shared URLs/text) and creates Google Calendar events. A Cloudflare Worker provides authenticated extraction proxy, event ingestion, and a daily digest email pipeline.

## Tech Stack

- **iOS 17+** — SwiftUI, SwiftData, `@Observable` macro, zero SPM dependencies
- **XcodeGen** — `project.yml` → `.xcodeproj`
- **Claude API** — `claude-haiku-4-5` for vision/extraction, called server-side via Worker proxy
- **Cloudflare Worker** — TypeScript, auth, extraction proxy (`POST /extract`), KV storage, cron-triggered digest
- **Resend** — transactional email for daily digest

## System Diagram

The diagram below shows the current architecture. All extraction requests are proxied through the Worker.

```mermaid
flowchart LR
    subgraph Device["iOS Device"]
        App["Event Snap App\n(SwiftUI + SwiftData)"]
        Ext["Share Extension\n(UIKit)"]
        Shared["Shared Container\n(App Groups)"]
        Keychain["Keychain\nP-256 Key + Device ID"]
    end

    subgraph Claude["Claude API"]
        Vision["POST /v1/messages\nclaude-haiku-4-5"]
    end

    subgraph Edge["Cloudflare Worker"]
        Register["POST /auth/register"]
        Token["POST /auth/token"]
        Extract["POST /extract"]
        Events["POST /events\nDELETE /events/:id"]
        Digest["Cron: Daily Digest"]
    end

    subgraph Data["Cloudflare KV"]
        DevRec["device:* records"]
        Pending["pending:* events"]
        Sent["sent:* events"]
        RL["ratelimit:* counters"]
    end

    subgraph Email["Resend"]
        Mail["Digest Email"]
    end

    Ext -->|"Save image/URL/text"| Shared
    Shared -->|"Darwin notification\n+ scenePhase check"| App

    App -->|"Sign register/token"| Keychain
    App -->|"POST /auth/register"| Register
    Register --> DevRec
    App -->|"POST /auth/token (signed)"| Token
    Token --> DevRec
    Token -->|"JWT (10 min)"| App
    App -->|"Bearer JWT + image/URL/text"| Extract
    Extract -->|"Server-side Claude request"| Vision
    Vision -->|"Structured JSON"| Extract
    Extract -->|"Structured JSON"| App
    App -->|"Bearer JWT"| Events
    Events --> Pending
    Events --> RL

    Digest -->|"Cursor-paginated list"| Pending
    Digest -->|"Archive processed"| Sent
    Digest -->|"HTML email"| Mail
```

## Project Structure

```
EventImage2Calendar/                      # Main app target
├── EventImage2CalendarApp.swift          # App entry + SwiftData container
├── Models/
│   ├── EventDetails.swift                # @Observable event model (in-memory) + DTO
│   └── PersistedEvent.swift              # SwiftData @Model + EventStatus enum
├── Services/
│   ├── ClaudeAPIService.swift            # Extraction client via Worker /extract proxy
│   ├── CalendarService.swift             # Google Calendar URL + .ics generation
│   ├── BackgroundEventProcessor.swift    # Background API calls + SwiftData persistence
│   ├── LocationService.swift             # CLLocationManager wrapper
│   ├── DigestService.swift               # Local digest outbox + POST /events flush/retry
│   ├── WorkerAuthService.swift           # Device key registration + JWT retrieval + digest preferences
│   ├── WebSearchService.swift            # Google search URL helper for descriptions
│   └── CrashReportingService.swift       # MetricKit subscriber — crash/hang/diagnostic reports
├── Views/
│   ├── ContentView.swift                 # Root (onboarding gate → EventListView)
│   ├── OnboardingView.swift              # 7-page onboarding (features, permissions, digest email, final)
│   ├── CameraView.swift                  # Camera sheet + ImagePicker
│   ├── EventListView.swift               # Event queue with swipe actions + DateCorrectionSheet + grouped processed list
│   ├── EventRowView.swift                # Compact list row
│   ├── EventDetailView.swift             # Editable form + calendar buttons
│   └── SettingsView.swift                # User preferences (digest toggle + email, camera-on-launch, extraction language)
└── PrivacyInfo.xcprivacy                 # App privacy manifest

ShareExtension/                           # Share Extension target
├── ShareViewController.swift             # NSItemProvider handler (UIKit-based)
├── ShareExtension.entitlements           # App Groups entitlement
└── Info.plist                            # Extension config + activation rules

Shared/                                   # Code shared between both targets
├── ImageResizer.swift                    # UIImage resize (1024px max, JPEG 0.7)
├── PendingShare.swift                    # Codable model for extension → app handoff
└── SharedContainerService.swift          # App Groups file read/write

cloudflare-worker/
├── wrangler.toml                         # Worker config + cron trigger (8 AM daily)
└── src/
    ├── index.ts                          # Route handlers (/extract, /events, /auth/*) + scheduled digest
    ├── email.ts                          # HTML digest email builder
    ├── security.ts                       # JWT issuance/verification + ECDSA signatures
    ├── validation.ts                     # Request/payload schema validation
    └── types.ts                          # TypeScript interfaces
```

## Event Lifecycle

```
Camera / Photo Library / Share Extension
                │
                ▼
    BackgroundEventProcessor
    (UIApplication.beginBackgroundTask)
                │
                ▼
        ClaudeAPIService
    (vision extraction or URL extraction)
                │
                ▼
      Cloudflare Worker /extract
      (JWT auth + rate limiting)
    ┌── auto-retry (3x, exponential backoff: 2s/4s/8s)
    │   for retryable errors (network, 5xx, 429)
                │
                ▼
           Claude API
                │
                ▼
    PersistedEvent (SwiftData)
    status: processing → ready
                │
        ┌───────┴───────┐
        ▼               ▼
 DigestService       User action
 (auto-queue on      (swipe Add or Dismiss)
  ready, POST            │
  /events)               ▼
        │          DigestService.dequeueEvent
        ▼          (DELETE /events/:id if
 Cloudflare          already sent to worker)
 Worker /events          │
        │                ▼
        ▼          status → added
 Daily digest            or deleted
 email (8 AM)
```

**Status values:** `processing` → `ready` → `added` | `dismissed` | `failed`

**Error handling & retry:**
- `ClaudeAPIError` classifies errors as retryable (network, 5xx, 429, 413) or permanent (auth, decoding, no-event-found). Error messages are source-aware: "image" for pure photos, "link" for URL shares, "share" for mixed image+URL shares, "text" for text-only shares
- `performExtraction` auto-retries retryable errors up to 3 times with exponential backoff (2s, 4s, 8s)
- Manual retry available via swipe action or detail view button, capped at 5 total attempts (`PersistedEvent.maxRetryCount`)
- On app launch: events stuck in `.processing` for >5 min are recovered to `.failed`; failed events with retryable errors are auto-retried
- Image validation: progressive JPEG compression (quality 0.7 → 0.5 → 0.3) with 1.5 MB size cap before API upload

**Multi-day events:** When Claude detects a date range with no specific timed event, it returns `is_multi_day: true` with an `event_dates` array. The detail view offers two modes: "Select Days" (multi-select checklist — pick any combination of dates, each becomes a separate all-day calendar event) or "Full Event" (entire date range as one event). Multi-date selection creates multiple Google Calendar entries (opened with staggered delays) or a single ICS file containing multiple VEVENTs.

### Digest flow (reminder-based)

The digest sends reminders about events the user has **not yet acted on**:

1. Extraction produces a local `PersistedEvent` in `.ready` (past events are excluded — they get `.failed`)
2. `DigestService.queueEvent` automatically queues it for digest (if enabled in Settings) and flushes to the Worker via `POST /events`
3. If the user acts (swipes "Add", taps "Add to Google Calendar" in detail view, or dismisses/deletes), `DigestService.dequeueEvent` removes the event from the digest queue and calls `DELETE /events/:id` to remove it from Worker KV
4. The daily cron emails only events still in `pending:*` — those the user hasn't dealt with

The local outbox tracks `notQueued` → `queued` → `sending` → `sent` | `failed`. Users can disable digest emails entirely in the Settings view.

## Share Extension

The Share Extension is a lightweight UIKit-based app extension (~120MB memory limit) that accepts images, URLs, and text from any app's share sheet.

**Handoff pattern:** File-based via App Groups (`group.com.eventsnap.shared`).

1. Extension receives `NSItemProvider` attachments (priority: image > URL > text)
2. Extension writes a `PendingShare` JSON manifest + image data to shared container
3. Extension posts Darwin notification (`com.eventsnap.newShareAvailable`)
4. Main app picks up pending shares on notification, `scenePhase` change to `.active`, or `onAppear`
5. Main app processes through the same `BackgroundEventProcessor` pipeline as camera photos

## Extraction Pipeline

All extraction modes use Claude's **`web_search_20250305`** tool, allowing the model to verify and complete event details (dates, addresses, venues) via web search in a single API call — no separate enrichment step.

### Server-side proxy

`ClaudeAPIService` sends all extraction requests to `POST /extract` on the Cloudflare Worker. The Worker validates auth, enforces rate limits (50 extractions/device/hour, 10/IP/minute), injects the server-side Claude API key, and proxies the request to Anthropic. The Claude API key never leaves the server.

The app authenticates via `WorkerAuthService`: on first use it registers a P-256 device key, then acquires a short-lived JWT for each extraction. On 401, the token is refreshed and the request retried once.

Three extraction modes in `ClaudeAPIService`:

- **Image extraction** (`extractEvents` / `extractEvent`): Sends base64 JPEG + structured prompt with `web_search` tool (max 5 uses). Returns a JSON **array** of events — a single image may contain multiple distinct events at different venues/times. `extractEvent` is a convenience wrapper returning the first event only.
- **Text extraction** (`extractEventFromText`): Sends page text content + `web_search` tool (max 3 uses). Truncates input to 4000 chars.
- **URL extraction** (`extractEventFromURL`): Sends bare URL + `web_search` tool (max 5 uses) — Claude searches the web to find and extract event details from the URL.

All three methods accept a `language` parameter (default: "English") that controls the output language of the `description` field. Titles, venue names, and addresses are kept in their original language. The preference is stored in `UserDefaults` as `extractionLanguage` and configurable in Settings.

**Web search response handling:** With web search enabled, Claude's response `content` array may contain `[text, server_tool_use, web_search_tool_result, text, ...]`. The parser concatenates all `text` blocks and extracts JSON from the result. The Worker passes the Claude response through unchanged, so all parsing remains on the iOS side.

**Multi-event images:** When a poster/screenshot lists several events (e.g., a cultural weekend schedule with events at different venues), `extractEvents` returns one `EventDetails` per distinct event. `BackgroundEventProcessor` applies the first result to the original `PersistedEvent` and creates additional `PersistedEvent` rows for the rest.

All use shared `sendRequestRaw()` for HTTP handling (90s timeout to accommodate web search via the Worker proxy). `sendRequest()` parses a single JSON object via `EventDetailsDTO`; `sendRequestMultiple()` tries JSON array first, falls back to single object. Network errors from `URLSession` are wrapped into `ClaudeAPIError.apiError` for consistent error classification. Empty extractions (all key fields nil) throw `ClaudeAPIError.noEventFound`.

### Extraction Fallback (Image → URL)

When a share includes both an image and a URL (e.g., Instagram, Facebook), the image is tried first. If image extraction fails with an extraction-level error (`.noEventFound`, `.decodingFailed`, `.invalidResponse`), the processor automatically falls back to URL-based extraction. Auth, network, and quota errors are **not** retried via fallback — they would fail on the URL path too. Debug logs record the original error and fallback path chosen.

### URL Share Extraction Pipeline

When a URL is shared (from Instagram, Safari, etc.), `BackgroundEventProcessor.extractFromURL` classifies the companion `sourceText`:

1. **Substantive text** (>50 chars after stripping URLs) → send to `extractEventFromText` with `web_search` tool
2. **Non-substantive text** (short share boilerplate like "Check out this post") or no text → send bare URL to `extractEventFromURL` with `web_search` tool (Claude fetches page content via web search)

The 50-char threshold is a heuristic; decisions are logged with original and stripped text lengths for tuning.

**Response schema:** `{ title, start_datetime, end_datetime, venue, address, description, timezone, is_multi_day, event_dates, date_confirmed, time_confirmed }`

### Missing Date/Time & Past Event Handling

Claude returns `date_confirmed` and `time_confirmed` booleans alongside `start_datetime` (which is always populated — using today's date as placeholder when the date is unknown, or `T00:00:00` when the time is unknown). `EventDetailsDTO.toEventDetails()` maps these to `hasExplicitDate` and `hasExplicitTime` on `EventDetails`. `PersistedEvent.applyExtraction()` sets the event to `.failed` with a field-specific message ("Please enter the date", "Please enter the time", or both) when either flag is false.

**Past event detection:** After date/time validation, `applyExtraction()` checks whether the event's start date is in the past (`isPastStartDate`). If so, the event is set to `.failed` with the message "This event is in the past. Update the date and confirm if it will occur again." The user can edit the date in `EventDetailView` and tap "Confirm Updated Date" to transition to `.ready`. Past events are tappable in `EventListView` via `NavigationLink` for easy correction.

The user sees a focused `DateCorrectionSheet` (presented from `EventListView`) that shows only the missing picker component(s) — date-only, time-only, or both. The sheet merges the user's correction with the already-extracted values (e.g., keeping the extracted time when only the date was missing) and transitions the event to `.ready`. Changing the start date automatically syncs the end date, preserving the originally extracted duration. A fallback confirmation button is also available in `EventDetailView` for events reached via navigation.

The prompt enforces consistency: if no numeric calendar date is visible anywhere in an image, all events extracted from that image must have `date_confirmed: false`. Day-of-week names (samedi, vendredi, etc.) are explicitly listed as not constituting confirmed dates.

### Swappable Components

The following components can be independently swapped or upgraded:

| Component | Location | Current Value | Notes |
|-----------|----------|---------------|-------|
| **AI Model** | `ClaudeAPIService.swift` — `"model"` key in request bodies | `claude-haiku-4-5` | Can swap to `claude-sonnet-4-6` or `claude-opus-4-6` for higher quality (at higher cost). All three extraction methods use the same model string. |
| **Web Search Tool** | `ClaudeAPIService.webSearchTool()` helper | `web_search_20250305` | Newer `web_search_20260209` adds dynamic filtering (`allowed_domains`, `blocked_domains`) but only works with Sonnet 4.6+ and Opus 4.6 (not Haiku 4.5). Upgrade requires changing the model too. |
| **API Version Header** | `cloudflare-worker/src/index.ts` — `CLAUDE_API_VERSION` constant | `2023-06-01` | Set server-side in the Worker proxy. Must be compatible with the web search tool version in use. |
| **User Location** | `ClaudeAPIService.webSearchTool()` — `user_location` parameter | Device timezone + country code | Provides localized web search results. Derived from `TimeZone.current` and `Locale.current.region`. Could be enhanced with reverse geocoding for city-level precision. |
| **Image Compression** | `Shared/ImageResizer.swift` | 1024px max, JPEG 0.7→0.5→0.3 progressive, 1.5 MB cap | Progressive quality reduction keeps images under the Worker body limit after base64 inflation. |
| **Extraction Gateway** | `ClaudeAPIService.swift` → Worker `/extract` route → Claude | App → Worker → Claude | Worker proxy keeps provider secrets server-side and enforces rate limits centrally. |
| **Digest Email Provider** | `cloudflare-worker/src/email.ts` | Resend | Any transactional email API (SendGrid, Mailgun, etc.) — swap the HTTP call in `sendDigestEmail()`. |

## Calendar Integration

`CalendarService` generates two output formats:

| Format | Timed Events | All-Day Events |
|--------|-------------|----------------|
| **Google Calendar URL** | `yyyyMMdd'T'HHmmss` | `yyyyMMdd` (end date exclusive) |
| **ICS file** | `DTSTART:20260320T190000` | `DTSTART;VALUE=DATE:20260502` (end exclusive) |

Google Calendar is opened via URL scheme (`calendar.google.com/calendar/render?action=TEMPLATE&...`). No OAuth required.

Description URLs are auto-linked as `<a href>` tags for Google Calendar rendering.

## Cloudflare Worker

### Routes

| Route | Method | Auth | Purpose |
|-------|--------|------|---------|
| `/auth/register` | POST | Signed payload | Register device public key |
| `/auth/token` | POST | Signed payload | Issue 10-min JWT |
| `/extract` | POST | Bearer JWT | Proxy Claude extraction with server-side API key |
| `/events` | POST | Bearer JWT | Accept event payload |
| `/events/:id` | DELETE | Bearer JWT | Remove event from digest queue |
| `/device/preferences` | PUT | Bearer JWT | Update device digest email |
| `/health` | GET | None | Health check |

### Planned Routes

| Route | Method | Auth | Purpose |
|-------|--------|------|---------|
| `/attest/challenge` | POST | Signed payload | Issue App Attest challenge |

### Event Ingestion

`POST /events` is idempotent at the storage-key level: the Worker stores pending digest entries under a stable `pending:{deviceId}:{eventId}` key so repeated client retries overwrite the same pending item rather than creating duplicates.

### Scheduled Job

Daily cron (8 AM) collects `pending:*` events from KV with cursor-based pagination, groups by device ID, looks up each device's `digestEmail` from its `DeviceRecord`, sorts by start date, sends HTML digest via Resend in batches of 100 per device, and archives each successful chunk to `sent:*` immediately after that chunk is delivered.

**Recipient model:** Each device can store a `digestEmail` via `PUT /device/preferences`. The cron uses the per-device email when available, falling back to the global `DIGEST_EMAIL_TO` secret. Users configure their email during onboarding or in the Settings view.

### Digest Delivery Semantics

- The client outbox makes digest submission retryable across transient auth/network failures.
- Worker-side idempotent pending keys prevent duplicate queue records from client retries.
- Per-chunk archival reduces duplicate-email risk if a later chunk fails during the same cron run.
- All-day events are carried explicitly in the payload and rendered as date-only / "All day" in digest emails.

### Deferred Atomic Queue Upgrade

The current design intentionally stops short of a fully atomic queue. It uses a local client outbox plus idempotent KV writes for practical reliability, but does not guarantee strict exactly-once delivery if an email send succeeds and archival fails immediately afterward. A stronger queue backed by D1 transactions or a Durable Object coordinator is deferred until scale or operational evidence justifies the extra complexity.

### Rate Limiting

KV-backed counters (eventually consistent):

**Event ingestion (`/events`):**
- 120 events/device/hour
- 30 events/IP/minute

**Extraction (`/extract`):**
- 20 extractions/device/day (free tier — `FREE_TIER_DAILY_EXTRACTIONS` in `index.ts`)
- 10 extractions/IP/minute

The daily device cap is the primary cost control knob. To adjust the free tier limit, change `FREE_TIER_DAILY_EXTRACTIONS` in `cloudflare-worker/src/index.ts`. For per-device paid tiers, store a `tier` field on the device record in KV and look it up in `handleExtract` instead of using the constant.

**Deferred:** Durable Objects for atomic rate limiting and Cloudflare WAF rules on `/events` and `/extract`.

### Environments

The production target uses separate `dev`, `staging`, and `production` Worker environments, each with:

- Distinct KV namespaces
- Distinct secrets
- Distinct email sender configuration
- A documented promotion path from staging to production

## Security

### Authentication Flow

1. **Device registration:** iOS generates P-256 signing key in Keychain on first launch. Signs `register:{deviceId}:{timestamp}` and posts public key + signature to `/auth/register`.
2. **Token issuance:** Signs `token:{deviceId}:{timestamp}` and posts to `/auth/token`. Worker verifies ECDSA signature, issues HMAC-SHA256 JWT (10 min TTL, `events:write` scope, device-bound).
3. **Extraction request:** `POST /extract` with `Authorization: Bearer <jwt>`. Worker validates JWT, enforces rate limits, validates request body (model allowlist, max_tokens cap, required fields), and proxies to Claude with server-side API key.
4. **Event submission:** `POST /events` with `Authorization: Bearer <jwt>`. Worker validates JWT signature, expiration, scope, and payload schema.

### Trust Boundaries

- **iOS app/device runtime** — untrusted against reverse engineering
- **Cloudflare Worker** — enforcement boundary for auth, validation, rate limiting, and production Claude access
- **Cloudflare KV** — trusted for persistence; rate limiting is eventually consistent
- **Resend** — external processor, receives only validated/sanitized data
- **Claude API key** — server-side only, injected by Worker `/extract` proxy

### Request Validation

- `application/json` content-type enforcement
- Event payloads (`/events`): 32KB body limit, field-level validation (title 1-200, description 0-4000, venue/address 0-200, URL 0-2048), date parsing/ordering, timezone validation
- Extraction payloads (`/extract`): 8 MB body limit (for base64 images), model allowlist (`claude-haiku-4-5`), max_tokens cap (4096), required system prompt and messages
- Timestamp freshness (5-minute skew tolerance)

### Output Sanitization

- HTML text fields escaped in digest emails
- `googleCalendarURL` allowlisted and protocol-constrained (HTTPS only, `calendar.google.com`)

### Secrets Management

| Secret | Location | Purpose |
|--------|----------|---------|
| `CLAUDE_API_KEY` | Wrangler secret (server-side only) | Claude API access via `/extract` proxy |
| `RESEND_API_KEY` | Wrangler secret | Email sending |
| `DIGEST_EMAIL_TO` | Wrangler secret | Digest delivery (single recipient; per-user in future) |
| `JWT_SIGNING_SECRET` | Wrangler secret | JWT HMAC signing |

No secrets are shipped in the iOS app binary. The Claude API key is injected server-side by the Worker.

**Rotation:** Rotate `JWT_SIGNING_SECRET` immediately if compromised. All existing tokens become invalid (by design — 10-min TTL limits exposure). Future: multi-key rotation with active + grace windows.

### Known Limitations

- Device identity is per-install; no user account identity yet
- Device registration is signature-verified but not hardware-attested
- KV rate limiting is eventually consistent, not strongly atomic
- Digest queue is retryable and idempotent, but not fully atomic end-to-end
- No centralized monitoring/alerting pipeline

## Observability

### Crash Reporting (iOS)

`CrashReportingService` subscribes to `MXMetricManager` (MetricKit) at app startup. When iOS delivers diagnostic payloads on the next launch (crash reports, hang diagnostics, CPU/disk exceptions), the service writes each payload's JSON to `{App Group}/crash_reports/` with a timestamped filename, keeping at most 20 files.

The share extension runs in a separate process and does not generate MetricKit payloads. Extension errors are captured via `SharedContainerService.writeDebugLog` (file-based, shared via App Groups).

### Debug Log

`SharedContainerService.writeDebugLog` appends to `share_debug.log` in the App Groups container. Both the main app and the share extension write to this log. Log rotation truncates to the last 500 KB when the file exceeds 1 MB.

## Testing & CI

### Worker Tests

- JWT issuance and verification (valid, expired, wrong scope, tampered)
- ECDSA device signature verification
- Event/register/token payload validation
- Extraction request validation (model allowlist, max_tokens, required fields)
- URL allowlisting
- KV cursor pagination behavior

### CI Pipeline

- Worker: dependency install, TypeScript typecheck, test suite
- iOS: simulator build validation
- Security: gitleaks secret scanning
