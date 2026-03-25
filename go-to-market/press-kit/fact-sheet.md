# Event Snap — Press Fact Sheet

## Overview

**App name:** Event Snap
**Tagline:** Photos to calendar, instantly
**One-liner:** Snap a poster, share a link, or paste text — Event Snap extracts the event details and creates a calendar event.
**Platform:** iOS 17+
**Price:** Free (20 extractions/day)
**Developer:** [Your name]
**Website:** https://eventsnap.app
**App Store:** [link TBD]
**Contact:** press@eventsnap.app

## What It Does

Event Snap uses AI vision to read event posters, flyers, web pages, and social media posts, extracting the key details — title, date, time, venue, description — and creating a calendar event in one tap. It verifies dates and addresses via web search for accuracy.

## Key Features

- **Photo extraction** — point your camera at any event poster or flyer
- **URL extraction** — share links from Eventbrite, Instagram, Facebook, Meetup, or any event page
- **Share Extension** — works from any iOS app via the share sheet
- **Web search verification** — AI cross-checks dates, venues, and addresses for accuracy
- **Multi-event support** — a single image with multiple events creates separate calendar entries
- **Daily digest email** — opt-in daily summary of extracted events you haven't added yet
- **One-tap calendar** — add to Google Calendar or export as .ics file
- **No account required** — works immediately, no sign-up or OAuth

## How It Works

1. Snap a photo of an event poster, share a link, or paste text
2. AI extracts event details (title, date, time, venue, description)
3. Web search verifies and completes any missing information
4. Review the extracted details and tap to add to your calendar

## Privacy

- Images are processed in memory and never stored
- Location data is coarse (city-level) and used only for timezone context
- No tracking, no advertising SDKs, no analytics
- No personal information collected (device identity via anonymous key pair)

## Technical Details

- Built with SwiftUI and SwiftData (zero third-party dependencies)
- LLM extraction via Cloudflare Worker proxy (OpenAI GPT-5 nano primary, Claude fallback)
- Share Extension with file-based handoff via App Groups
- Background processing completes even if app closes

## Press-Ready Quotes

> [Placeholder — add quotes from developer and/or beta testers before distributing]

## Assets

- High-res app icon: [link TBD]
- Screenshot set: [link TBD]
- Demo video (30 sec): [link TBD]
- Demo video (60 sec): [link TBD]
- Developer headshot: [link TBD]
