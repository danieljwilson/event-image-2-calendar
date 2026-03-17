import { afterEach, describe, expect, it, vi } from 'vitest';
import { pendingEventKey, sendDailyDigest } from '../src/index';
import { Env } from '../src/types';

class FakeKV implements Partial<KVNamespace> {
  private readonly store = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }

  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }

  async delete(key: string): Promise<void> {
    this.store.delete(key);
  }

  async list(options?: KVNamespaceListOptions): Promise<KVNamespaceListResult<unknown>> {
    const prefix = options?.prefix ?? '';
    const limit = options?.limit ?? 1000;
    const start = options?.cursor ? Number(options.cursor) : 0;

    const matchingKeys = [...this.store.keys()]
      .filter((key) => key.startsWith(prefix))
      .sort();

    const pageKeys = matchingKeys.slice(start, start + limit);
    const nextIndex = start + pageKeys.length;

    return {
      keys: pageKeys.map((name) => ({ name })),
      list_complete: nextIndex >= matchingKeys.length,
      cursor: String(nextIndex),
    } as KVNamespaceListResult<unknown>;
  }

  keys(): string[] {
    return [...this.store.keys()].sort();
  }
}

function buildEvent(id: string) {
  return {
    id,
    title: `Event ${id}`,
    startDate: '2026-04-01T18:00:00Z',
    endDate: '2026-04-01T20:00:00Z',
    venue: 'Main Hall',
    address: '123 Street',
    description: 'desc',
    timezone: 'Europe/Paris',
    isAllDay: false,
    googleCalendarURL: 'https://calendar.google.com/calendar/render?action=TEMPLATE',
    createdAt: '2026-03-01T12:00:00Z',
    deviceId: 'device-1234567890',
  };
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('sendDailyDigest', () => {
  it('archives each successful chunk before attempting the next one', async () => {
    const kv = new FakeKV();

    for (let i = 0; i < 101; i++) {
      const id = `evt-${i}`;
      await kv.put(pendingEventKey('device-123', id), JSON.stringify(buildEvent(id)));
    }

    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 'email-1' }), { status: 200 }))
      .mockResolvedValueOnce(new Response('boom', { status: 500 }));

    vi.stubGlobal('fetch', fetchMock);

    const env: Env = {
      EVENTS: kv as KVNamespace,
      RESEND_API_KEY: 'resend',
      DIGEST_EMAIL_TO: 'digest@example.com',
      DIGEST_EMAIL_FROM: 'sender@example.com',
      JWT_SIGNING_SECRET: 'secret',
    };

    await sendDailyDigest(env);

    const keys = kv.keys();
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(keys.filter((key) => key.startsWith('sent:'))).toHaveLength(100);
    expect(keys.filter((key) => key.startsWith('pending:'))).toHaveLength(1);
  });
});
