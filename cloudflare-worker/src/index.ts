import { Env, EventPayload } from './types';
import { buildDigestEmail } from './email';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'POST' && url.pathname === '/events') {
      return handleEventPost(request, env);
    }

    if (request.method === 'GET' && url.pathname === '/health') {
      return new Response('OK', { status: 200 });
    }

    return new Response('Not Found', { status: 404 });
  },

  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(sendDailyDigest(env));
  },
};

async function handleEventPost(request: Request, env: Env): Promise<Response> {
  // Auth check
  const authHeader = request.headers.get('X-Auth-Token');
  if (authHeader !== env.AUTH_TOKEN) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    const event: EventPayload = await request.json();

    if (!event.id || !event.title || !event.startDate) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const dateKey = new Date().toISOString().slice(0, 10);
    const key = `pending:${dateKey}:${event.id}`;

    await env.EVENTS.put(key, JSON.stringify(event), {
      expirationTtl: 60 * 60 * 24 * 30, // 30 day TTL
    });

    return new Response(JSON.stringify({ success: true, key }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid request body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

async function sendDailyDigest(env: Env): Promise<void> {
  const list = await env.EVENTS.list({ prefix: 'pending:' });

  if (list.keys.length === 0) {
    return;
  }

  const events: EventPayload[] = [];
  for (const key of list.keys) {
    const data = await env.EVENTS.get(key.name);
    if (data) {
      events.push(JSON.parse(data));
    }
  }

  if (events.length === 0) return;

  // Sort by event start date
  events.sort((a, b) => new Date(a.startDate).getTime() - new Date(b.startDate).getTime());

  const { subject, html } = buildDigestEmail(events);

  const resendResponse = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: env.DIGEST_EMAIL_FROM,
      to: [env.DIGEST_EMAIL_TO],
      subject,
      html,
    }),
  });

  if (resendResponse.ok) {
    // Move from pending to sent
    for (const key of list.keys) {
      const data = await env.EVENTS.get(key.name);
      if (data) {
        const sentKey = key.name.replace('pending:', 'sent:');
        await env.EVENTS.put(sentKey, data, { expirationTtl: 60 * 60 * 24 * 7 });
        await env.EVENTS.delete(key.name);
      }
    }
  }
}
