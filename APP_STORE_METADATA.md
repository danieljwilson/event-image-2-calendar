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

<!-- Host this content at your chosen URL before submission -->
https://eventsnap.app/privacy

## Privacy Policy (draft content to host)

**Event Snap Privacy Policy**

Last updated: March 2026

Event Snap is designed to extract event details from photos and links you share with it. Here is how your data is handled:

**Photos and images** you capture or share are sent to our server for AI-powered text extraction. Images are processed in memory and are not stored after extraction is complete. Images are resized (max 1024px, JPEG quality 0.7) before transmission.

**Location data** (coarse, city-level) is used solely to improve extraction accuracy — helping identify the correct city and timezone for events. Location is sent with extraction requests and is not stored separately.

**Event data** you accept (title, date, venue, etc.) may be sent to our server for inclusion in a daily digest email. Event data is stored temporarily (up to 30 days) and deleted after the digest is sent.

**Device identity** is managed via a cryptographic key pair generated on your device. No personal information (name, email, Apple ID) is collected or linked to your device identity.

**No tracking**: Event Snap does not use analytics, advertising SDKs, or tracking pixels. No data is shared with third parties for advertising or marketing purposes.

**Third-party services**:
- Anthropic (Claude API) processes images and text for event extraction
- Resend delivers digest emails

**Data deletion**: Uninstalling the app removes all local data. Server-side pending events expire automatically after 30 days.

**Contact**: For privacy questions, email support@eventsnap.app.

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
