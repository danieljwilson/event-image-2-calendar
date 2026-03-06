# Event Image 2 Calendar

iOS app that extracts event details from poster photos using Claude vision API and creates Google Calendar events. Background processing + daily digest email via Cloudflare Worker.

## Tech Stack
- **SwiftUI** (iOS 17+) with `@Observable` macro + **SwiftData** for persistence
- **Claude API** (`claude-haiku-4-5`) for vision/extraction
- **Cloudflare Worker** + **Resend** for daily digest emails
- **Zero SPM dependencies** — all via platform frameworks
- **XcodeGen** for project generation (`project.yml` → `.xcodeproj`)

## Project Structure
```
EventImage2Calendar/
├── EventImage2CalendarApp.swift          # App entry point + SwiftData container
├── Models/
│   ├── EventDetails.swift                # @Observable + Codable event model (in-memory)
│   └── PersistedEvent.swift              # SwiftData @Model + EventStatus enum
├── Services/
│   ├── ClaudeAPIService.swift            # Claude Messages API client (vision)
│   ├── LocationService.swift             # CLLocationManager wrapper
│   ├── CalendarService.swift             # Google Calendar URL + .ics generation
│   ├── BackgroundEventProcessor.swift    # Background API calls + SwiftData persistence
│   └── DigestService.swift               # POST events to Cloudflare Worker
├── Views/
│   ├── ContentView.swift                 # Root (hosts EventListView)
│   ├── CameraView.swift                  # Camera sheet (modal) + ImagePicker + UIImage ext
│   ├── EventListView.swift               # Event queue with swipe actions
│   ├── EventRowView.swift                # Compact list row
│   └── EventDetailView.swift             # Editable event form + calendar buttons
└── Utilities/
    └── APIKeyStorage.swift               # Reads API key from Bundle (xcconfig)

cloudflare-worker/
├── wrangler.toml                         # Worker config + cron trigger
├── src/
│   ├── index.ts                          # POST /events + daily cron
│   ├── email.ts                          # HTML digest email builder
│   └── types.ts                          # TypeScript interfaces
```

## Key Conventions
- Architecture: `BackgroundEventProcessor` (@Observable) handles photo intake + background API calls. `PersistedEvent` (SwiftData @Model) stores events with lifecycle status.
- Event lifecycle: processing → ready → added/dismissed. Events persist across app launches.
- Background processing: `UIApplication.beginBackgroundTask` ensures API call completes even if app closes.
- API key stored in `Secrets.xcconfig` (gitignored), read via `Bundle.main.infoDictionary`
- Images resized to 1024px max dimension, JPEG quality 0.7 before API upload
- Google Calendar integration via URL scheme (no OAuth)
- Location accuracy: `kCLLocationAccuracyKilometer` (city-level, for context only)
- Extraction prompt prioritizes primary attendable events (e.g., vernissage) over date ranges

## Development
```bash
# Regenerate Xcode project after changing project.yml
xcodegen generate

# API key setup — create Secrets.xcconfig with:
# CLAUDE_API_KEY = sk-ant-your-key-here

# Deploy Cloudflare Worker
cd cloudflare-worker && npm install && wrangler deploy
# Set secrets: wrangler secret put RESEND_API_KEY / DIGEST_EMAIL_TO / AUTH_TOKEN
```

## Common Tasks
- **Change AI model**: Edit `ClaudeAPIService.swift`, swap `claude-haiku-4-5` → `claude-sonnet-4-6`
- **Adjust image compression**: Edit `UIImage.resizedForAPI()` in `CameraView.swift`
- **Modify extraction prompt**: Edit system/user prompts in `ClaudeAPIService.swift`
- **Change digest schedule**: Edit `crons` in `cloudflare-worker/wrangler.toml`
- **Change digest email template**: Edit `cloudflare-worker/src/email.ts`
