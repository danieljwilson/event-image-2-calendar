import { describe, expect, it } from 'vitest';
import { issueAccessToken, verifyAccessToken, verifyDeviceSignature } from '../src/security';
import { Env } from '../src/types';

function toBase64url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function testEnv(secret = 'test-secret'): Env {
  return {
    EVENTS: {} as KVNamespace,
    RESEND_API_KEY: '',
    DIGEST_EMAIL_TO: '',
    DIGEST_EMAIL_FROM: '',
    JWT_SIGNING_SECRET: secret,
    CLAUDE_API_KEY: '',
  };
}

describe('JWT access tokens', () => {
  it('issues and verifies a token', async () => {
    const env = testEnv();
    const issued = await issueAccessToken(env, 'device-1234567890');
    const claims = await verifyAccessToken(env, issued.token);

    expect(claims).not.toBeNull();
    expect(claims?.device_id).toBe('device-1234567890');
    expect(claims?.scope).toBe('events:write');
  });

  it('rejects token with wrong secret', async () => {
    const issued = await issueAccessToken(testEnv('secret-a'), 'device-abc1234567890');
    const claims = await verifyAccessToken(testEnv('secret-b'), issued.token);
    expect(claims).toBeNull();
  });
});

describe('device signatures', () => {
  it('verifies valid ECDSA signatures', async () => {
    const keyPair = await crypto.subtle.generateKey(
      { name: 'ECDSA', namedCurve: 'P-256' },
      true,
      ['sign', 'verify']
    );

    const message = 'register:device-1234567890123456:1700000000';
    const signature = await crypto.subtle.sign(
      { name: 'ECDSA', hash: 'SHA-256' },
      keyPair.privateKey,
      new TextEncoder().encode(message)
    );
    const publicKeyRaw = await crypto.subtle.exportKey('raw', keyPair.publicKey);

    const valid = await verifyDeviceSignature(
      toBase64url(new Uint8Array(publicKeyRaw)),
      message,
      toBase64url(new Uint8Array(signature))
    );

    expect(valid).toBe(true);
  });

  it('rejects invalid signatures', async () => {
    const keyPair = await crypto.subtle.generateKey(
      { name: 'ECDSA', namedCurve: 'P-256' },
      true,
      ['sign', 'verify']
    );
    const publicKeyRaw = await crypto.subtle.exportKey('raw', keyPair.publicKey);

    const valid = await verifyDeviceSignature(
      toBase64url(new Uint8Array(publicKeyRaw)),
      'token:device-1234567890123456:1700000000',
      'invalidsignature'
    );

    expect(valid).toBe(false);
  });
});
