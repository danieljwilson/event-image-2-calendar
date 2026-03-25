# Press & Outreach Pitch Templates

## Target List

### Tech Blogs
| Publication | Writer(s) to target | Angle |
|-------------|---------------------|-------|
| 9to5Mac | Chance Miller, Zac Hall | AI utility app, iOS productivity |
| MacStories | Federico Viticci, John Voorhees | Workflow automation, Share Extension |
| The Sweet Setup | — | Productivity tool recommendation |
| iMore | — | Best new iOS apps |
| Cult of Mac | — | Indie app spotlight |
| AppAdvice | — | New app review |

### Newsletters
| Newsletter | Submission method |
|------------|-------------------|
| iOS Dev Weekly | Submit via website |
| Dense Discovery | Submit via website |
| Sidebar | Submit via website |
| The Sample | Submit via website |
| TLDR | Submit via website |

### Podcasts
| Podcast | Host(s) | Pitch angle |
|---------|---------|-------------|
| AppStories | Federico Viticci, John Voorhees | iOS app deep-dive |
| Launched | Charlie Chapman | Indie dev launch story |
| Under the Radar | Marco Arment, David Smith | Solo dev building with AI |
| Indie Dev Monday | Josh Holtz | Indie dev spotlight |

### YouTube
| Creator | Focus area |
|---------|-----------|
| Christopher Lawley | iPad/iPhone productivity |
| Brandon Butch | iPhone tips & apps |
| Shane Whatmore | Productivity tools |

---

## Template 1: Tech Blog Pitch

**Subject:** Event Snap: AI-powered poster-to-calendar app for iOS

Hi [Name],

I built Event Snap, a free iOS app that turns event posters into calendar events using AI vision. Point your camera at a concert poster, share an Eventbrite link, or forward a flyer — it extracts the title, date, time, and venue, verifies them via web search, and creates a calendar event in one tap.

What makes it different from OCR-based approaches:
- It understands event context, not just text (handles ambiguous dates, multi-event posters, venue abbreviations)
- Works from any app via Share Extension — Instagram, Safari, Photos, Mail
- Web search verification catches errors and fills in missing details
- No account required, no OAuth — just snap and go

It's free with 20 extractions/day. Built as a solo project with SwiftUI, zero third-party dependencies, and a Cloudflare Worker backend.

Happy to provide a TestFlight build, screenshots, or a demo video. Here's the [fact sheet / press kit link].

Best,
[Your name]

---

## Template 2: Newsletter Submission

**App name:** Event Snap
**One-liner:** Snap a poster or share a link — AI extracts event details and creates a calendar event.
**URL:** https://eventsnap.app
**Why it's interesting:** Solves the gap between seeing an event and getting it on your calendar. Uses AI vision + web search to understand event context (not just OCR). Works from any iOS app via Share Extension. Free, no account needed.

---

## Template 3: Podcast Guest Pitch

**Subject:** Solo dev story: Building an AI-powered iOS app (Event Snap)

Hi [Host name],

I'm [your name], an academic researcher who built Event Snap — an iOS app that turns event posters into calendar events using AI vision.

I think it could make for an interesting episode because:

1. **The problem is universal** — everyone has seen a poster for something they wanted to attend and then forgotten about it
2. **The technical approach is novel** — AI vision + web search verification in a single LLM call, proxied through a Cloudflare Worker, with zero third-party dependencies on the iOS side
3. **The solo dev angle** — built this as a side project while working as an academic researcher; there's a story about shipping a real product with AI when you're not a full-time app developer

I can talk about the technical architecture, the AI extraction pipeline, lessons learned shipping an indie iOS app, or whatever fits your show best.

Best,
[Your name]

---

## Template 4: YouTube Reviewer Pitch

**Subject:** Event Snap — a new iOS app for your "apps you need" content

Hi [Creator name],

I built Event Snap, a free iOS app that I think would resonate with your audience. It solves a small but universal friction: you see an event poster (concert, meetup, festival, school event) and want it on your calendar without typing everything in manually.

How it works: snap a photo or share a link from any app, and AI extracts the event details + verifies them via web search. One tap to add to Google Calendar.

It's very visual and demo-friendly — the extraction flow from poster photo to calendar event takes about 5 seconds and looks great on camera.

I can send a TestFlight build if you'd like to try it, plus screenshots and a press kit. Happy to answer any questions.

Best,
[Your name]

---

## Outreach Tips

- **Personalize every pitch** — reference the writer's recent articles or the podcast's recent episodes
- **Send Tuesday-Thursday** for best response rates
- **Follow up once** after 5-7 days if no response, then move on
- **Offer a TestFlight build** — reviewers prefer to try the app themselves
- **Don't mass-email** — quality over quantity; 10 personalized pitches beat 100 generic ones
