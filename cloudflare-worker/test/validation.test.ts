import { describe, expect, it } from 'vitest';
import { validateEventPayload, validateIssueTokenRequest, validateRegisterRequest } from '../src/validation';

function buildValidEvent() {
  return {
    id: 'evt-1234',
    title: 'Gallery Opening',
    startDate: '2026-04-01T18:00:00Z',
    endDate: '2026-04-01T20:00:00Z',
    venue: 'Main Hall',
    address: '123 Street, Paris',
    description: 'An event',
    timezone: 'Europe/Paris',
    isAllDay: false,
    googleCalendarURL: 'https://calendar.google.com/calendar/render?action=TEMPLATE',
    createdAt: '2026-03-01T12:00:00Z',
  };
}

describe('validateEventPayload', () => {
  it('accepts valid payload', () => {
    expect(validateEventPayload(buildValidEvent())).not.toBeNull();
  });

  it('rejects invalid date ordering', () => {
    const payload = buildValidEvent();
    payload.endDate = '2026-04-01T17:59:59Z';
    expect(validateEventPayload(payload)).toBeNull();
  });

  it('rejects excessively long titles', () => {
    const payload = buildValidEvent();
    payload.title = 'x'.repeat(500);
    expect(validateEventPayload(payload)).toBeNull();
  });
});

describe('auth payload validation', () => {
  it('accepts valid register payload', () => {
    const payload = {
      deviceId: '5CF8A7FA-1DE5-4F80-9E0F-8AA9DEB6FD0A',
      publicKey: 'AbCdEf123_-XYZ',
      timestamp: 123456,
      signature: 'AbCdEf123_-XYZ',
    };
    expect(validateRegisterRequest(payload)).not.toBeNull();
  });

  it('rejects register payload with bad device id', () => {
    const payload = {
      deviceId: 'short',
      publicKey: 'AbCdEf123_-XYZ',
      timestamp: 123456,
      signature: 'AbCdEf123_-XYZ',
    };
    expect(validateRegisterRequest(payload)).toBeNull();
  });

  it('accepts valid token payload', () => {
    const payload = {
      deviceId: '5CF8A7FA-1DE5-4F80-9E0F-8AA9DEB6FD0A',
      timestamp: 123456,
      signature: 'AbCdEf123_-XYZ',
    };
    expect(validateIssueTokenRequest(payload)).not.toBeNull();
  });
});
