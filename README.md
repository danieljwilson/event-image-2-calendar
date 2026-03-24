# Event Snap

iOS app that extracts event details from photos of posters, flyers, and screenshots using LLM vision, then creates Google Calendar events. Share from any app via the Share Extension.

## How it works

1. Take a photo or share an image/URL from any app
2. LLM vision extracts event details (title, date, venue, address)
3. Review and edit, then add to Google Calendar with one tap
4. Optional daily digest email reminds you of events you haven't added yet

## Tech Stack

- **SwiftUI** (iOS 17+) + **SwiftData** for persistence
- **LLM extraction** via Cloudflare Worker proxy (currently OpenAI GPT-5 nano, Anthropic Claude as fallback)
- **Cloudflare Worker** for extraction proxy, daily digest emails (Resend), and analytics
- **Zero SPM dependencies** — platform frameworks only
- **XcodeGen** for project generation

## Setup

### Prerequisites

- Xcode 16+
- Node.js 18+ (for Cloudflare Worker)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Cloudflare account with Workers

### iOS App

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode and build
open EventImage2Calendar.xcodeproj
```

### Cloudflare Worker

```bash
cd cloudflare-worker
npm install

# Set required secrets
wrangler secret put CLAUDE_API_KEY
wrangler secret put OPENAI_API_KEY
wrangler secret put RESEND_API_KEY
wrangler secret put DIGEST_EMAIL_TO
wrangler secret put JWT_SIGNING_SECRET
wrangler secret put ADMIN_DASHBOARD_KEY

# Deploy
wrangler deploy

# Run tests
npx vitest run
```

### Local Secrets

Create a `.env` file (gitignored) for local references:

```
DASHBOARD_KEY=<your ADMIN_DASHBOARD_KEY value>
```

## Admin Dashboard

View extraction analytics (tokens, cost, processing time, errors per user):

```bash
source .env && open "https://event-digest-worker.daniel-j-wilson-587.workers.dev/admin/dashboard?key=$DASHBOARD_KEY"
```

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — system design, data flow, security model
- [ROADMAP.md](ROADMAP.md) — project status and planned features
- [CLAUDE.md](CLAUDE.md) — AI assistant context (project structure, conventions, common tasks)
