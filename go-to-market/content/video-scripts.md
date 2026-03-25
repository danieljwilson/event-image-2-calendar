# Content & Video Scripts

## Short-Form Videos (TikTok / Reels / Shorts)

These are the highest-ROI content pieces — visually demonstrable, snackable, shareable.

### Video 1: "POV: You see a concert poster"
**Duration:** 15-20 sec
**Script:**
- (0-3s) Walking past a concert poster on the street, camera pans to it
- (3-6s) Pull out phone, open Event Snap
- (6-10s) Snap photo, extraction animates
- (10-14s) Event details appear: band name, date, venue
- (14-18s) Tap "Add to Calendar" — done
- **Text overlay:** "Never forget a show again"
- **Sound:** trending audio or satisfying "ding" on calendar add

### Video 2: "Share Extension magic"
**Duration:** 15 sec
- (0-3s) Scrolling Instagram, see an event post
- (3-6s) Tap share -> Event Snap
- (6-10s) Extraction happens
- (10-15s) Calendar event created
- **Text overlay:** "Works from ANY app"

### Video 3: "My kid brought home 3 flyers today"
**Duration:** 20 sec
- (0-5s) Spread of school flyers on kitchen counter
- (5-8s) Snap first flyer
- (8-11s) Snap second flyer
- (11-14s) Snap third flyer
- (14-18s) Show calendar with all 3 events added
- (18-20s) Satisfied nod
- **Text overlay:** "3 flyers, 30 seconds, 0 typing"

### Video 4: "Festival season prep"
**Duration:** 15 sec
- (0-3s) Multi-event festival poster
- (3-8s) Snap photo -> multiple events extracted
- (8-12s) Scroll through extracted events
- (12-15s) Add all to calendar
- **Text overlay:** "One poster. Five calendar events."

### Video 5: "The app I wish existed in college"
**Duration:** 20 sec
- (0-5s) Walking through campus, bulletin board full of posters
- (5-15s) Rapid-fire: snap, extract, add. Snap, extract, add.
- (15-20s) Show packed calendar
- **Text overlay:** "Event Snap. Free on iOS."

### Recurring Series Ideas
- **"Does it work with..."** — test extraction on unusual sources (restaurant event menus, handwritten flyers, screenshots of texts, foreign language posters)
- **"Event Snap vs. typing it manually"** — split screen speed comparison
- **"My week in events"** — weekly recap of events captured via Event Snap

---

## YouTube Tutorial

### "How I Never Miss an Event (Event Snap Tutorial)"
**Duration:** 2-3 minutes
**Outline:**
1. (0-15s) Hook: "I used to see event posters and forget about them. Then I built an app."
2. (15-45s) Demo: Camera extraction — walk through the full flow
3. (45-1:15) Demo: Share Extension — share from Instagram, Safari, Mail
4. (1:15-1:45) Demo: URL extraction — paste an Eventbrite link
5. (1:45-2:15) Features: multi-event extraction, date correction, daily digest
6. (2:15-2:45) Wrap: free on iOS, 20 extractions/day, no account needed
7. (2:45-3:00) CTA: App Store link in description

---

## Blog Posts

### Post 1: "Building an AI-Powered iOS App as a Solo Developer"
**Audience:** Developers (Hacker News, Dev.to, IndieHackers)
**Outline:**
- The problem: poster -> calendar is surprisingly tedious
- Why AI vision, not OCR (semantic understanding vs. text extraction)
- Architecture: SwiftUI + Cloudflare Worker + multi-provider LLM
- Zero SPM dependencies — why and how
- Share Extension challenges and solutions
- Web search verification: making AI output reliable
- Lessons learned shipping as a solo dev

### Post 2: "How I Use AI to Manage My Social Calendar"
**Audience:** Lifestyle/productivity (Medium, personal blog)
**Outline:**
- The "poster problem" — we all see events and forget them
- My workflow: snap everything, review later
- Daily digest email as a safety net
- Share Extension for online events (Instagram, Eventbrite)
- Tips for making the most of it

### Post 3: "Building a Cloudflare Worker as an AI Proxy"
**Audience:** Technical (dev blogs, Cloudflare community)
**Outline:**
- Why proxy AI calls through a Worker (key security, rate limiting, multi-provider)
- Provider auto-routing by model prefix
- JWT authentication with device key pairs
- Cost tracking and analytics dashboard
- Lessons learned on Worker limits and KV usage

---

## Content Calendar Template

| Week | Platform | Content |
|------|----------|---------|
| 1 | TikTok/Reels | Video 1: "POV: concert poster" |
| 1 | Twitter/X | Launch thread |
| 2 | TikTok/Reels | Video 2: "Share Extension magic" |
| 2 | Blog | Post 1: "Building an AI-powered iOS app" |
| 3 | TikTok/Reels | Video 3: "3 flyers, 30 seconds" |
| 3 | YouTube | Tutorial: "How I Never Miss an Event" |
| 4 | TikTok/Reels | Video 4: "Festival season prep" |
| 4 | Blog | Post 2: "How I use AI for my social calendar" |
| 5+ | TikTok/Reels | Recurring: "Does it work with..." series |
