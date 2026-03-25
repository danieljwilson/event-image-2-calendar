const STYLES = `
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #fff; color: #1d1d1f; padding: 32px 24px; max-width: 720px; margin: 0 auto; line-height: 1.6; }
  h1 { font-size: 28px; font-weight: 700; margin-bottom: 4px; }
  h2 { font-size: 18px; font-weight: 600; margin-top: 28px; margin-bottom: 8px; }
  p, li { font-size: 15px; color: #333; margin-bottom: 12px; }
  ul { padding-left: 20px; margin-bottom: 12px; }
  li { margin-bottom: 6px; }
  .updated { font-size: 13px; color: #86868b; margin-bottom: 24px; }
  a { color: #0071e3; text-decoration: none; }
  a:hover { text-decoration: underline; }
  .contact { margin-top: 32px; padding-top: 16px; border-top: 1px solid #e5e5ea; }
`;

export function buildPrivacyPolicyHTML(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Event Snap — Privacy Policy</title>
<style>${STYLES}</style>
</head>
<body>
<h1>Privacy Policy</h1>
<p class="updated">Last updated: March 25, 2026</p>

<p>Event Snap extracts event details from photos and links you share, helping you add events to your calendar. This policy explains what data is collected and how it is handled.</p>

<h2>What We Collect</h2>
<ul>
  <li><strong>Photos and images</strong> you capture or share for event extraction.</li>
  <li><strong>URLs and text</strong> you share via the Share Extension.</li>
  <li><strong>Coarse location</strong> (city-level) to improve extraction accuracy (timezone, nearby venues).</li>
  <li><strong>Event details</strong> extracted by AI (title, date, venue, address, category, city).</li>
  <li><strong>Device identity</strong> via a cryptographic key pair generated on your device. No personal information (name, email, Apple ID) is linked to this identity.</li>
  <li><strong>Email address</strong> (optional) if you enable the daily digest feature.</li>
</ul>

<h2>How Images Are Processed</h2>
<p>Photos are resized (max 1024px, JPEG compression) on your device before being sent to our server. Images are forwarded to an AI provider for text extraction, processed in memory, and are not stored after extraction is complete. Neither our server nor the AI provider retains your images.</p>

<h2>Third-Party Services</h2>
<p>Event Snap uses the following services to function:</p>
<ul>
  <li><strong>OpenAI / Anthropic</strong> — AI providers that process images and text to extract event details. Data is sent via our server proxy and is subject to the provider's data usage policies.</li>
  <li><strong>Web search</strong> (via AI tool use) — The AI may search the web to verify or complete event details (dates, addresses, venue information). Search queries contain event-related terms, not personal data.</li>
  <li><strong>Google Calendar</strong> — When you add an event to your calendar, event details are sent to Google via a URL scheme. This is user-initiated and handled by Google's own privacy policy.</li>
  <li><strong>Resend</strong> — Delivers daily digest emails. Receives event details (title, date, venue) and your email address if you opted in.</li>
  <li><strong>Cloudflare</strong> — Our server infrastructure. Handles authentication, rate limiting, and temporary event storage.</li>
</ul>

<h2>Analytics and Logging</h2>
<p>We log anonymous extraction metrics to monitor service health and costs. These logs include:</p>
<ul>
  <li>Anonymous device identifier</li>
  <li>Extraction type (image, URL, text)</li>
  <li>AI model used and token counts</li>
  <li>Processing time and success/failure status</li>
  <li>Event category and city (after extraction)</li>
</ul>
<p>These logs are retained for 90 days and are not shared with third parties. They do not contain image data, personal information, or event descriptions.</p>

<h2>Data Retention</h2>
<ul>
  <li>Pending digest events: 30 days</li>
  <li>Sent digest events: 7 days</li>
  <li>Extraction logs: 90 days</li>
  <li>Device records: 180 days</li>
</ul>
<p>All server-side data expires automatically according to these schedules.</p>

<h2>Crash Reporting</h2>
<p>Event Snap uses Apple's MetricKit framework to collect crash and performance diagnostics. This data is stored locally on your device and is only shared if you choose to send feedback.</p>

<h2>No Tracking</h2>
<p>Event Snap does not use advertising SDKs, analytics frameworks, or tracking pixels. No data is shared with third parties for advertising or marketing purposes. We do not build user profiles or track behavior across apps.</p>

<h2>Data Deletion</h2>
<p>Uninstalling the app removes all local data (events, images, preferences, device keys). Server-side data (pending events, extraction logs) expires automatically per the retention schedule above. To request immediate deletion of server-side data, contact us at the email below.</p>

<div class="contact">
  <h2>Contact</h2>
  <p>For privacy questions or data deletion requests:<br>
  <a href="mailto:event-snap-support@danieljwilson.com">event-snap-support@danieljwilson.com</a></p>
</div>
</body>
</html>`;
}

export function buildTermsHTML(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Event Snap — Terms of Service</title>
<style>${STYLES}</style>
</head>
<body>
<h1>Terms of Service</h1>
<p class="updated">Last updated: March 25, 2026</p>

<p>By using Event Snap, you agree to these terms. If you do not agree, please do not use the app.</p>

<h2>Service Description</h2>
<p>Event Snap is a mobile application that uses artificial intelligence to extract event details from photos, URLs, and text, and helps you add those events to your calendar. The app also offers an optional daily digest email summarizing your upcoming events.</p>

<h2>AI-Generated Content</h2>
<p>Event details are extracted by AI and may be inaccurate, incomplete, or misinterpreted. You are responsible for reviewing and verifying all extracted information before adding events to your calendar. Event Snap does not guarantee the accuracy of any extracted data, including dates, times, venues, or addresses.</p>

<h2>Acceptable Use</h2>
<p>Event Snap is intended for personal event management. You agree not to:</p>
<ul>
  <li>Upload illegal, harmful, or offensive content</li>
  <li>Attempt to circumvent rate limits or security measures</li>
  <li>Use the service for automated data scraping or bulk processing</li>
  <li>Reverse engineer the app or its server components</li>
</ul>

<h2>Availability</h2>
<p>Event Snap is provided "as is" without guarantees of availability, uptime, or uninterrupted service. We may modify, suspend, or discontinue the service at any time without notice. Free tier extraction limits may change.</p>

<h2>Your Data</h2>
<p>You retain ownership of all content you provide (photos, text, event details). By using the app, you grant us a limited license to process this content for the purpose of providing the service. See our <a href="/legal/privacy">Privacy Policy</a> for details on data handling.</p>

<h2>Intellectual Property</h2>
<p>The Event Snap app, its design, and its server infrastructure are the property of the developer. You may not copy, modify, or distribute the app beyond what is permitted by the App Store license.</p>

<h2>Limitation of Liability</h2>
<p>To the maximum extent permitted by law, Event Snap and its developer shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of the service, including but not limited to missed events, incorrect calendar entries, or data loss.</p>

<h2>Changes to These Terms</h2>
<p>We may update these terms from time to time. The "last updated" date at the top indicates when changes were made. Continued use of the app after changes constitutes acceptance of the updated terms.</p>

<div class="contact">
  <h2>Contact</h2>
  <p>For questions about these terms:<br>
  <a href="mailto:event-snap-support@danieljwilson.com">event-snap-support@danieljwilson.com</a></p>
</div>
</body>
</html>`;
}
