# Event Image 2 Calendar

iOS app that extracts event details from poster photos using LLM vision API (multi-provider, proxied via Cloudflare Worker) and creates Google Calendar events. Supports sharing from any app via Share Extension. Background processing + daily digest email via Cloudflare Worker.

See [ARCHITECTURE.md](ARCHITECTURE.md) for full system design and security. See [ROADMAP.md](ROADMAP.md) for project status and next steps.

## Tech Stack
- **SwiftUI** (iOS 17+) with `@Observable` macro + **SwiftData** for persistence
- **LLM Extraction** — multi-provider: currently **OpenAI GPT-5.4 nano** (`gpt-5.4-nano-2026-03-17`), Anthropic Claude available as fallback. Worker auto-routes by model prefix.
- **Cloudflare Worker** for extraction proxy (`POST /extract`) + **Resend** for daily digest emails
- **Zero SPM dependencies** — all via platform frameworks
- **XcodeGen** for project generation (`project.yml` → `.xcodeproj`)

## Project Structure
```
EventImage2Calendar/                      # Main app target
├── EventImage2CalendarApp.swift          # App entry point + SwiftData container
├── Models/
│   ├── EventDetails.swift                # @Observable + Codable event model (in-memory) + DTO
│   └── PersistedEvent.swift              # SwiftData @Model + EventStatus enum
├── Services/
│   ├── APIConfiguration.swift            # Centralized Worker base URL (#if DEBUG → staging, else → production)
│   ├── ClaudeAPIService.swift            # LLM extraction client via Worker /extract proxy (vision + URL + text with web_search tool)
│   ├── LocationService.swift             # CLLocationManager wrapper
│   ├── CalendarService.swift             # Google Calendar URL + .ics generation
│   ├── BackgroundEventProcessor.swift    # Background API calls + SwiftData persistence
│   ├── DigestService.swift               # POST events to Cloudflare Worker
│   ├── WorkerAuthService.swift           # Device key registration + JWT retrieval + digest preferences + usage fetch
│   ├── WebSearchService.swift            # Google search URL helper for descriptions
│   ├── CrashReportingService.swift       # MetricKit subscriber — crash/hang/diagnostic reports
│   └── FeedbackService.swift             # TestFlight detection, device metadata, screenshot capture, feedback log
├── Views/
│   ├── ContentView.swift                 # Root (onboarding gate → EventListView)
│   ├── OnboardingView.swift              # 7-page onboarding (features, permissions, digest email, final)
│   ├── CameraView.swift                  # Camera sheet (modal) + ImagePicker
│   ├── EventListView.swift               # Event queue with swipe actions + share consumption
│   ├── EventRowView.swift                # Compact list row
│   ├── EventDetailView.swift             # Editable event form + calendar buttons + multi-day UI
│   ├── SettingsView.swift                # User preferences (digest toggle + email, camera-on-launch) + FeedbackLogView
│   └── FeedbackMailView.swift            # MFMailComposeViewController wrapper for in-app feedback
└── PrivacyInfo.xcprivacy                 # App privacy manifest

ShareExtension/                           # Share Extension target
├── ShareViewController.swift             # NSItemProvider handler (UIKit)
├── ShareExtension.entitlements           # App Groups entitlement
└── Info.plist                            # Extension config + activation rules

Shared/                                   # Code shared between both targets
├── ImageResizer.swift                    # UIImage resize (1024px max, JPEG 0.7)
├── PendingShare.swift                    # Codable model for extension → app handoff
└── SharedContainerService.swift          # App Groups file read/write

cloudflare-worker/
├── wrangler.toml                         # Worker config + cron trigger
├── src/
│   ├── index.ts                          # /auth/register + /auth/token + POST /extract + POST /report-error + GET /usage + GET /admin/dashboard + POST /events + daily cron
│   ├── providers.ts                      # LLM provider detection + request/response translation + pricing + usage extraction
│   ├── dashboard.ts                      # HTML builder for admin analytics dashboard
│   ├── email.ts                          # HTML digest email builder
│   ├── security.ts                       # JWT + signature verification helpers
│   ├── validation.ts                     # Request/schema validation
│   └── types.ts                          # TypeScript interfaces
```

## Key Conventions
- Architecture: `BackgroundEventProcessor` (@Observable) handles photo intake + background API calls. `PersistedEvent` (SwiftData @Model) stores events with lifecycle status.
- Event lifecycle: processing → ready → added/dismissed. Events persist across app launches.
- Background processing: `UIApplication.beginBackgroundTask` ensures API call completes even if app closes.
- Share Extension uses file-based handoff via App Groups (`group.com.eventsnap.shared`) + Darwin notifications.
- LLM API keys stored server-side only (Wrangler secrets); extraction proxied via Worker `/extract`
- Images resized to 1024px max dimension, JPEG quality 0.7 before API upload (see `Shared/ImageResizer.swift`)
- Google Calendar integration via URL scheme (no OAuth)
- Location accuracy: `kCLLocationAccuracyKilometer` (city-level, for context only)
- LLM uses web search tool for verifying/completing event details (dates, addresses, etc.). Worker translates Claude `web_search_20250305` ↔ OpenAI `web_search` automatically.
- No separate enrichment step — extraction + web search happen in a single LLM call
- Multi-event extraction: a single image can produce multiple `PersistedEvent` rows
- Multi-day events use `isAllDay` flag + `eventDates` array for multi-date selection UI
- Partial extraction certainty: `hasExplicitDate` / `hasExplicitTime` flags on `PersistedEvent` track which fields need user correction; `DateCorrectionSheet` in `EventListView` provides a focused picker for the missing piece

## Design Reference
- **Apple HIG** ([developer.apple.com/design/human-interface-guidelines](https://developer.apple.com/design/human-interface-guidelines)): Consult for UI/UX decisions (progress indicators, navigation patterns, button placement, accessibility). Do NOT fetch the entire site — strategically load only the relevant section (e.g., `/progress-indicators`, `/page-controls`, `/layout`) for the specific design question at hand. HIG pages require JavaScript rendering and may not load via WebFetch; use domain knowledge of HIG principles when pages are unavailable.

## Important Rules
- **Do NOT build Xcode projects** — make code changes only, the user will build and test themselves.

## Development
```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# Local Worker dev (uses .dev.vars for secrets, in-memory KV)
cd cloudflare-worker && npm run dev

# Deploy Cloudflare Worker (staging first, then production)
cd cloudflare-worker && npm install
npm run deploy:staging      # → event-digest-worker-staging
npm run deploy:production   # → event-digest-worker

# Set secrets per environment
wrangler secret put CLAUDE_API_KEY [--env staging]
# Full list: CLAUDE_API_KEY, OPENAI_API_KEY, RESEND_API_KEY, DIGEST_EMAIL_TO, JWT_SIGNING_SECRET, ADMIN_DASHBOARD_KEY
# Use DIFFERENT values for JWT_SIGNING_SECRET and ADMIN_DASHBOARD_KEY across environments
```

iOS debug builds hit **staging**, release builds hit **production** (via `APIConfiguration.swift`). See `cloudflare-worker/DEPLOY.md` for full deploy/promotion flow.

## Common Tasks
- **Change AI model**: Edit `extractionModel` constant in `ClaudeAPIService.swift`. Worker auto-routes by model prefix (`gpt-*` → OpenAI, `claude-*` → Anthropic). If the model isn't already in `ALLOWED_MODELS` in `validation.ts`, add it and redeploy Worker. Available OpenAI models: [developers.openai.com/api/docs/models/all](https://developers.openai.com/api/docs/models/all). Currently configured: `gpt-5-nano`, `gpt-5-nano-2025-08-07`, `gpt-5.4-nano`, `gpt-5.4-nano-2026-03-17`, `claude-haiku-4-5`.
- **Adjust image compression**: Edit `UIImage.resizedForAPI()` in `Shared/ImageResizer.swift`
- **Modify extraction prompt**: Edit system/user prompts in `ClaudeAPIService.swift`
- **Change digest schedule**: Edit `crons` in `cloudflare-worker/wrangler.toml`
- **Change digest email template**: Edit `cloudflare-worker/src/email.ts`
- **Change free tier daily extraction limit**: Edit `FREE_TIER_DAILY_EXTRACTIONS` in `cloudflare-worker/src/index.ts` (currently 20/day)

## Documentation Maintenance (REQUIRED)
After every set of code changes, update the relevant docs before finishing:
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: Update when changing system design, data flow, error handling, service interactions, security model, or adding/removing files from the project structure.
- **[ROADMAP.md](ROADMAP.md)**: Update when completing roadmap items (check them off), discovering new work items, or changing priorities.
