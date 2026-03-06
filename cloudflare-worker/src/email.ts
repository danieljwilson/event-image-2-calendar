import { EventPayload } from './types';

const ALLOWED_CALENDAR_HOSTS = new Set(['calendar.google.com', 'www.google.com']);

export function buildDigestEmail(events: EventPayload[]): { subject: string; html: string } {
  const today = new Date().toLocaleDateString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });

  const subject = `Event Snap Digest - ${events.length} event${events.length > 1 ? 's' : ''} (${today})`;

  const eventCards = events
    .map((event) => {
      const start = new Date(event.startDate);
      const dateStr = start.toLocaleDateString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      });
      const timeStr = start.toLocaleTimeString('en-US', {
        hour: '2-digit',
        minute: '2-digit',
      });
      const safeCalendarURL = sanitizeCalendarURL(event.googleCalendarURL);

      const location = [event.venue, event.address].filter(Boolean).join(', ');

      return `
      <div style="border:1px solid #e0e0e0; border-radius:12px; padding:20px; margin-bottom:16px; background:#fafafa;">
        <h2 style="margin:0 0 8px 0; color:#1a1a1a; font-size:18px;">${escapeHtml(event.title)}</h2>
        <p style="margin:4px 0; color:#666; font-size:14px;">
          &#128197; ${dateStr} at ${timeStr}
        </p>
        ${location ? `<p style="margin:4px 0; color:#666; font-size:14px;">&#128205; ${escapeHtml(location)}</p>` : ''}
        ${event.description ? `<p style="margin:8px 0 12px 0; color:#333; font-size:14px;">${escapeHtml(event.description)}</p>` : ''}
        ${
          safeCalendarURL
            ? `<a href="${safeCalendarURL}"
               style="display:inline-block; background:#4285f4; color:white; padding:10px 20px;
                      border-radius:6px; text-decoration:none; font-size:14px; font-weight:500;">
              Add to Google Calendar
            </a>`
            : ''
        }
      </div>
    `;
    })
    .join('');

  const html = `
    <!DOCTYPE html>
    <html>
    <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
                 max-width:600px; margin:0 auto; padding:20px; background:#ffffff;">
      <h1 style="font-size:24px; color:#1a1a1a; margin-bottom:4px;">Your Event Digest</h1>
      <p style="color:#888; margin-top:0; margin-bottom:24px;">${today}</p>
      ${eventCards}
      <p style="color:#aaa; font-size:12px; margin-top:24px; text-align:center;">
        Sent by Event Snap
      </p>
    </body>
    </html>
  `;

  return { subject, html };
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function sanitizeCalendarURL(rawURL: string): string | null {
  if (!rawURL) return null;

  let url: URL;
  try {
    url = new URL(rawURL);
  } catch {
    return null;
  }

  if (url.protocol !== 'https:') return null;
  if (!ALLOWED_CALENDAR_HOSTS.has(url.hostname)) return null;
  if (url.hostname === 'www.google.com' && !url.pathname.startsWith('/calendar')) return null;

  return escapeAttribute(url.toString());
}

function escapeAttribute(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
