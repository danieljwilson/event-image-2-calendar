# Event Image 2 Calendar

iOS app that extracts event details from poster photos using Claude vision API and creates Google Calendar events. Supports sharing from any app via Share Extension. Background processing + daily digest email via Cloudflare Worker.

See [ARCHITECTURE.md](ARCHITECTURE.md) for full system design and security. See [ROADMAP.md](ROADMAP.md) for project status and next steps.

## Tech Stack
- **SwiftUI** (iOS 17+) with `@Observable` macro + **SwiftData** for persistence
- **Claude API** (`claude-haiku-4-5`) for vision/extraction
- **Cloudflare Worker** + **Resend** for daily digest emails
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
│   ├── ClaudeAPIService.swift            # Claude Messages API client (vision + URL extraction)
│   ├── LocationService.swift             # CLLocationManager wrapper
│   ├── CalendarService.swift             # Google Calendar URL + .ics generation
│   ├── BackgroundEventProcessor.swift    # Background API calls + SwiftData persistence
│   ├── DigestService.swift               # POST events to Cloudflare Worker
│   ├── WorkerAuthService.swift           # Device key registration + JWT retrieval
│   └── WebSearchService.swift            # Web search capabilities
├── Views/
│   ├── ContentView.swift                 # Root (hosts EventListView)
│   ├── CameraView.swift                  # Camera sheet (modal) + ImagePicker
│   ├── EventListView.swift               # Event queue with swipe actions + share consumption
│   ├── EventRowView.swift                # Compact list row
│   └── EventDetailView.swift             # Editable event form + calendar buttons + multi-day UI
└── Utilities/
    └── APIKeyStorage.swift               # Reads API key from Bundle (xcconfig)

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
│   ├── index.ts                          # /auth/register + /auth/token + POST /events + daily cron
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
- API key stored in `Secrets.xcconfig` (gitignored), read via `Bundle.main.infoDictionary`
- Images resized to 1024px max dimension, JPEG quality 0.7 before API upload (see `Shared/ImageResizer.swift`)
- Google Calendar integration via URL scheme (no OAuth)
- Location accuracy: `kCLLocationAccuracyKilometer` (city-level, for context only)
- Extraction prompt prioritizes primary attendable events (e.g., vernissage) over date ranges
- Multi-day events use `isAllDay` flag + `eventDates` array for single-day picker UI

## Development
```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# API key setup — create Secrets.xcconfig with:
# CLAUDE_API_KEY = sk-ant-your-key-here

# Deploy Cloudflare Worker
cd cloudflare-worker && npm install && wrangler deploy
# Set secrets: wrangler secret put RESEND_API_KEY / DIGEST_EMAIL_TO / JWT_SIGNING_SECRET
```

## Common Tasks
- **Change AI model**: Edit `ClaudeAPIService.swift`, swap `claude-haiku-4-5` → `claude-sonnet-4-6`
- **Adjust image compression**: Edit `UIImage.resizedForAPI()` in `Shared/ImageResizer.swift`
- **Modify extraction prompt**: Edit system/user prompts in `ClaudeAPIService.swift`
- **Change digest schedule**: Edit `crons` in `cloudflare-worker/wrangler.toml`
- **Change digest email template**: Edit `cloudflare-worker/src/email.ts`

## Documentation Maintenance (REQUIRED)
After every set of code changes, update the relevant docs before finishing:
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: Update when changing system design, data flow, error handling, service interactions, security model, or adding/removing files from the project structure.
- **[ROADMAP.md](ROADMAP.md)**: Update when completing roadmap items (check them off), discovering new work items, or changing priorities.
