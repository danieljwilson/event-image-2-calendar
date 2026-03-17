import { describe, expect, it } from 'vitest';
import { buildDigestEmail, sanitizeCalendarURL } from '../src/email';

describe('sanitizeCalendarURL', () => {
  it('allows https calendar.google.com links', () => {
    const value = sanitizeCalendarURL('https://calendar.google.com/calendar/render?action=TEMPLATE');
    expect(value).toBe('https://calendar.google.com/calendar/render?action=TEMPLATE');
  });

  it('rejects non-https links', () => {
    expect(sanitizeCalendarURL('http://calendar.google.com/calendar/render')).toBeNull();
  });

  it('rejects javascript links', () => {
    expect(sanitizeCalendarURL('javascript:alert(1)')).toBeNull();
  });

  it('rejects non-calendar hosts', () => {
    expect(sanitizeCalendarURL('https://evil.example.com/calendar')).toBeNull();
  });
});

describe('buildDigestEmail', () => {
  it('renders all-day events without a midnight time label', () => {
    const { html } = buildDigestEmail([
      {
        id: 'evt-1',
        title: 'Open Studios',
        startDate: '2026-04-12T00:00:00Z',
        endDate: '2026-04-13T00:00:00Z',
        venue: 'Gallery',
        address: '123 Street',
        description: 'desc',
        timezone: 'Europe/Paris',
        isAllDay: true,
        googleCalendarURL: '',
        createdAt: '2026-03-01T12:00:00Z',
      },
    ]);

    expect(html).toContain('(All day)');
    expect(html).not.toContain('12:00 AM');
  });
});
