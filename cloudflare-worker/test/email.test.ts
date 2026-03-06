import { describe, expect, it } from 'vitest';
import { sanitizeCalendarURL } from '../src/email';

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
