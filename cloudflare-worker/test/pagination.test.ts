import { describe, expect, it } from 'vitest';
import { listPendingEvents } from '../src/index';
import { Env } from '../src/types';

class FakeKV implements Partial<KVNamespace> {
  private readonly store = new Map<string, string>();

  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }

  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
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
    googleCalendarURL: 'https://calendar.google.com/calendar/render?action=TEMPLATE',
    createdAt: '2026-03-01T12:00:00Z',
    deviceId: 'device-1234567890',
  };
}

describe('listPendingEvents pagination', () => {
  it('returns all records across KV cursors', async () => {
    const kv = new FakeKV();

    for (let i = 0; i < 1001; i++) {
      const id = `evt-${i}`;
      await kv.put(`pending:2026-03-06:device-123:${id}`, JSON.stringify(buildEvent(id)));
    }

    const env: Env = {
      EVENTS: kv as KVNamespace,
      RESEND_API_KEY: '',
      DIGEST_EMAIL_TO: '',
      DIGEST_EMAIL_FROM: '',
      JWT_SIGNING_SECRET: 'secret',
    };

    const entries = await listPendingEvents(env);
    expect(entries.length).toBe(1001);
  });
});
