# Event Snap Monetization Strategy

## 1. Executive Summary

Event Snap is the only product that knows which events users **commit to attending** — measured by the calendar-save action. This conversion signal is stronger than any impression, click, or RSVP, and no other platform can offer it to event organizers. The monetization thesis: sell **Promoted Events** to organizers priced on **cost-per-calendar-save (CPCS)**, starting with direct B2B sales in a single city.

## 2. The Calendar-Save Advantage

When a user saves a promoted event to Google Calendar through Event Snap, the organizer knows that person allocated time on their personal calendar. This is a fundamentally different signal than what any competing platform offers:


| Platform                       | What organizers pay for   | Signal strength                     |
| ------------------------------ | ------------------------- | ----------------------------------- |
| Instagram / Facebook Ads       | Impressions or clicks     | Weak — scroll-past, accidental taps |
| Eventbrite Promoted            | Placement on listing page | Medium — browse intent              |
| Google Ads                     | Search click              | Medium — search intent              |
| **Event Snap Promoted Events** | **Calendar save**         | **Strong — commitment to attend**   |


This justifies premium CPCS pricing ($3–8 per save depending on event type and city) because the organizer pays only for demonstrated attendance intent. For context, typical Facebook event ad CPC is $0.50–2.00, but a calendar save is worth 5–10x a click in conversion value.

**Attribution note:** The current implementation opens Google Calendar with pre-filled event details via URL scheme. While we can't confirm the user tapped "Save" in Google Calendar (no OAuth), the act of opening the pre-filled calendar is a strong proxy — users who go that far almost always save. Adding Google Calendar OAuth later would make the conversion signal bulletproof.

## 3. Product Prerequisites

These must be built before monetization. Ordered by dependency — earlier items enable later ones.

### 3a. Category Extraction (Pre-launch, minimal effort)

Add a `category` field to the Claude extraction prompt. The extraction call already happens — this adds one field to the JSON schema at zero additional API cost.

- Fixed taxonomy: `music`, `art`, `food`, `sports`, `tech`, `community`, `nightlife`, `theater`, `film`, `family`, `education`, `wellness`, `outdoor`, `other`
- Touches: `EventDetailsDTO`, `PersistedEvent`, `EventPayload`, Claude system prompt
- ~30 lines of code across 4 files
- **Why now:** Category is the critical targeting signal. Without it, organizers can't target relevant users. Adding it pre-launch means all historical events have categories from day one.

### 3b. Aggregate Trending Counters (Post-launch, Worker-side)

When multiple users in a city save the same event, that's a trending signal — useful for discovery without any user profiling.

- Server-side KV counters: `trending:{city}:{category}:{event_hash} → count`
- TTL: 7–14 days (events age out naturally)
- No per-user data stored — only aggregate counts
- **Why this matters:** Powers the Discover tab with organic content before any promoted events exist

### 3c. Discover Tab (The strategic linchpin)

The app is currently extraction-only (photo → event). A "Discover" or "What's On" tab transforms it from a utility into a platform. This tab serves dual purpose:

- **User feature:** Browse trending/upcoming events nearby
- **Primary ad surface:** Promoted events mixed into the feed with clear labeling

Without this surface, monetization is limited to digest email ads. The Discover tab should launch as a purely organic feature first, with promoted events added later.

### 3d. User Identity (Already on ROADMAP — Phase 3)

Sign in with Apple enables:

- Per-user digest preferences (already planned)
- Coarse preference tracking (which categories this user tends to save)
- Attribution for promoted event campaigns

## 4. Monetization Model

### 4a. Promoted Events (Primary revenue)

- **Format:** Native event cards identical to organic events, with a "Promoted" badge
- **Surfaces:** Discover tab, digest email, post-save recommendations
- **Pricing:** Cost-per-calendar-save (CPCS) — organizer pays only when a user opens the event in Google Calendar
- **Target pricing:** $3–5 CPCS initially (adjustable per city/category/event type)
- **Targeting dimensions (coarse, privacy-safe):**
  - City (from LocationService, coarse to city level)
  - Category (from extraction)
  - Date range (events in the next 7/14/30 days)
  - No personal targeting, no behavioral profiles, no cross-app tracking
- **Density limits:** Max 1 promoted per 5 organic events in Discover; max 3 promoted per digest email

### 4b. Premium Tier (Secondary revenue)


| Feature                | Free                         | Premium ($2.99/mo or $24.99/yr) |
| ---------------------- | ---------------------------- | ------------------------------- |
| Photo/URL extraction   | Unlimited                    | Unlimited                       |
| Calendar save          | Yes                          | Yes                             |
| Daily digest email     | Yes (with sponsored section) | Yes (no sponsored)              |
| Discover tab           | Yes (with promoted events)   | Yes (no promoted)               |
| Batch processing       | No                           | Yes (queue multiple photos)     |
| Custom digest schedule | No                           | Yes (twice daily, weekly)       |
| Priority extraction    | No                           | Yes (faster queue)              |


Premium is primarily an ad-removal tier. The incremental features (batch processing, custom digest) justify the price beyond just removing ads.

### 4c. Ad Networks (Tertiary, deferred)

AdMob or Meta Audience Network for remnant fill only. Explicitly deferred until:

- Direct-sold promoted events are insufficient to fill inventory
- User base exceeds ~50K MAU
- Privacy implications fully evaluated

Ad network integration requires updating `PrivacyInfo.xcprivacy` and App Store privacy labels (currently declaring "no tracking"). This is a significant change to avoid as long as possible.

## 5. Ad Surfaces

In recommended implementation order (easiest first):

### Surface 1: Digest Email (Lowest friction)

- **Location:** New "Nearby Events" section appended after organic events in the daily digest
- **Format:** 1–3 event cards using the same HTML template, with "Promoted" header and divider
- **Why first:** Zero iOS changes, zero App Review risk. The email template already renders event cards — just append a sponsored section.
- **Billable event:** Click on "Add to Google Calendar" link in the email

### Surface 2: Discover Tab (Highest volume)

- **Location:** New third tab in EventListView alongside Pending and Processed
- **Format:** Event cards using EventRowView with "Promoted" badge, mixed into trending feed
- **Density:** Max 1 promoted per 5 organic events
- **Billable event:** Calendar save from the Discover tab

### Surface 3: Post-Save Recommendations

- **Location:** Inline banner or brief sheet after a user swipes "Add" on an event
- **Format:** "People who saved [Event X] also saved: [Promoted Event Y]"
- **Billable event:** Calendar save from the recommendation

### Surface 4: EventDetailView "Similar Events"

- **Location:** New section at bottom of EventDetailView, below description
- **Format:** 2–3 compact related event cards
- **Billable event:** Tap to view detail + calendar save

## 6. Go-to-Market

### Phase 1: Manual Pilot (10–20 organizers, one city, free)

- Select a single city with high event density and personal connections to organizers
- Identify 10–20 event organizers and venues
- Offer free promoted events for 3 months in exchange for feedback, testimonials, and cross-promotion (mention Event Snap at their events)
- Organizer onboarding: they provide event poster image, title, venue, date, and CTA URL — the same creative they already use elsewhere
- Track: saves per promoted event, save rate (saves / impressions), qualitative organizer feedback

### Phase 2: Paid Validation

- Convert best-performing pilot organizers to paid CPCS
- Simple invoicing (manual, monthly)
- Target metrics: >5% save rate for promoted events in the Discover tab
- Validate the $3–5 CPCS price point; adjust by category and city

### Phase 3: Self-Serve Portal

- Web-based organizer dashboard for creating and managing promoted events
- Stripe integration for payment
- Campaign creation: upload event poster, set targeting (city, category, date range), set budget
- Reporting dashboard: impressions, saves, save rate, spend, ROI estimates

## 7. Privacy & Compliance

### Promoted Events ≠ Tracking

Apple's App Tracking Transparency (ATT) defines tracking as linking app data with third-party data for targeted advertising. Promoted Events in Event Snap do **not** constitute tracking:

- Targeting uses only first-party, on-device signals (city location, in-app category preferences)
- No data shared with third parties for advertising
- No cross-app or cross-site identifiers
- No advertising SDK integrated
- No ATT prompt required

### Privacy Label Updates

When promoted events launch, the App Store privacy labels need updating:

- Add "Advertising Data" data type for promoted event delivery
- Update coarse location purpose to include "advertising" alongside "app functionality"
- These are disclosure changes, not functionality changes

### GDPR-Safe by Design

- No rich user profiles — system uses aggregate signals (trending events by city/category)
- No per-user behavioral data leaves the device for profiling
- Promoted events served based on city + category + date, not user identity
- Users can opt out via Premium subscription
- Data minimization: only event metadata + coarse location, no PII beyond what Sign in with Apple provides

### App Store Review Considerations

- Promoted events must be clearly labeled as such (Apple requires disclosure)
- No interstitials or intrusive ad formats
- The Discover tab must feel like a genuine feature, not an ad container
- Starting with digest email ads avoids App Review implications entirely

## 8. Technical Requirements

### Data Model Changes

- Add `category: String?` to `PersistedEvent` (SwiftData) and `EventDetailsDTO`
- Add `isPromoted: Bool` and `campaignId: String?` to `PersistedEvent` (for Discover tab events)
- Add `category` to `EventPayload` sent to Worker

### New Worker Endpoints

- `GET /discover` — Trending + promoted events for a given city/category (Bearer JWT auth)
- `POST /promoted` — Submit a promoted event (organizer API key auth)
- `GET /promoted/:id/metrics` — Campaign metrics (organizer API key auth)
- `POST /promoted/:id/save` — Record a calendar save / billable event (Bearer JWT auth)

### KV Schema

- `trending:{city}:{category}:{event_hash}` → count (TTL: 7 days)
- `promoted:{campaign_id}` → PromotedEvent JSON (TTL: event end date)
- `save:{campaign_id}:{device_id}` → save record (TTL: 30 days, for dedup)
- `organizer:{api_key_hash}` → OrganizerRecord JSON

### Category Taxonomy

14 fixed categories for the extraction prompt:

`music` · `art` · `food` · `sports` · `tech` · `community` · `nightlife` · `theater` · `film` · `family` · `education` · `wellness` · `outdoor` · `other`

This taxonomy should be defined early and extended carefully — organizers target by category, so stability matters.

## 9. Phased Roadmap


| Phase | Timeline          | What                                                           | Prerequisite                                   |
| ----- | ----------------- | -------------------------------------------------------------- | ---------------------------------------------- |
| **0** | Q2–Q3 2026        | Ship the app (current ROADMAP Phases 0–4)                      | —                                              |
| **1** | Q3 2026           | Add category extraction to Claude prompt + data model          | App launched                                   |
| **2** | Q4 2026           | Discover tab as organic feature (trending events by city)      | Categories + ~100 active users                 |
| **3** | Q4 2026 – Q1 2027 | Promoted events in digest email (free pilot, 10–20 organizers) | Digest email working + organizer relationships |
| **4** | Q1–Q2 2027        | Promoted events in Discover tab (paid CPCS)                    | Discover tab + validated pilot                 |
| **5** | Q3 2027+          | Self-serve organizer portal + Stripe + scale to new cities     | Proven CPCS model                              |


**Key principle:** Each phase creates the prerequisite for the next. No phase should be skipped. Phase 0 (shipping the app) is the critical path — nothing else matters without users.

## 10. Risks & Mitigations


| Risk                                          | Likelihood         | Impact | Mitigation                                                                                                                                                     |
| --------------------------------------------- | ------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Insufficient user base to attract organizers  | High (early stage) | High   | Focus on one city; even 500 active users suffices for a pilot. Offer free pilot to build proof of concept.                                                     |
| Apple rejects app for undisclosed advertising | Medium             | High   | Always label promoted content clearly. Update privacy labels before submitting any build with promoted events. Start with digest email (no App Review needed). |
| Users perceive promoted events as spam        | Medium             | High   | Hard cap on promoted density (1:5 ratio). Premium tier removes all promoted content. Promoted events must meet same quality bar as organic.                    |
| Calendar-save attribution is imprecise        | Low                | Medium | "Open Google Calendar with pre-filled event" is a strong proxy. Organizers understand this. OAuth integration later closes the gap entirely.                   |
| Privacy regulation changes                    | Low                | Medium | Model is inherently privacy-safe — coarse, first-party, aggregate signals only. No ad network SDKs, no cross-app tracking.                                     |
| Organizer demand too low / market too small   | Medium             | Medium | Premium subscription generates revenue independently. Discover tab is a genuine feature regardless of monetization.                                            |
| Technical complexity of Discover feed         | Low                | Low    | V1 is a flat list of trending events sorted by save count. No ML, no personalization. Just "events near you that other people are saving."                     |


