# App Store Metadata

Reference for App Store Connect submission. Copy these values into the App Store Connect form.

## App Information

- **App name**: Event Snap
- **Subtitle**: Photos to calendar, instantly
- **Primary category**: Productivity
- **Secondary category**: Utilities
- **Content rights**: Does not contain, show, or access third-party content

## Description

Photograph an event poster or share a link, and Event Snap extracts the details — title, date, time, venue — and creates a calendar event. Works with posters, flyers, Instagram posts, Eventbrite pages, and more.

- Share from any app via the iOS share sheet
- AI-powered extraction with web verification
- One tap to add to Google Calendar or export as .ics
- Daily digest email summarizing your upcoming events

Event Snap uses AI to read event posters and web pages, pulling out the key details so you don't have to type them in manually. It verifies dates and addresses via web search for accuracy. No account required — just snap or share and go.

## Keywords

event, poster, calendar, photo, extract, flyer, schedule, ics, share, snap

## Support URL

<!-- Replace with your actual support URL before submission -->
mailto:support@eventsnap.app

## Privacy Policy URL

https://event-digest-worker.daniel-j-wilson-587.workers.dev/legal/privacy

## Terms of Service URL

https://event-digest-worker.daniel-j-wilson-587.workers.dev/legal/terms

## Privacy Policy

The full privacy policy is hosted at the URL above and served by the Cloudflare Worker.
Source: `cloudflare-worker/src/legal.ts` (`buildPrivacyPolicyHTML()`).

Also linked from: Settings > About > Privacy Policy, and the onboarding data disclosure page.

## App Store Privacy Labels

Configure these in App Store Connect under "App Privacy":

### Data Not Linked to You

| Data type | Purpose |
|-----------|---------|
| Coarse Location | App Functionality |
| Photos or Videos | App Functionality |

### Data Not Collected

All other categories.

### Tracking

This app does not track users.

## Screenshots

Capture on iPhone 15 Pro Max (6.7") and iPhone 15 Pro (6.1"):

1. Event list showing "Coming Up" section with several ready events
2. Camera capture view with a poster in frame
3. Event detail view showing extracted info (title, date, venue, description)
4. Share sheet with Event Snap extension visible
5. Date correction sheet (partial extraction UX)
