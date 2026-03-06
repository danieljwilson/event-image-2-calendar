import { AccessTokenClaims, Env } from './types';

const encoder = new TextEncoder();
const decoder = new TextDecoder();

const JWT_ISSUER = 'event-digest-worker';
const JWT_AUDIENCE = 'event-digest-api';
const ACCESS_TOKEN_TTL_SECONDS = 10 * 60;

export async function issueAccessToken(env: Env, deviceId: string): Promise<{ token: string; expiresAt: number }> {
  const now = Math.floor(Date.now() / 1000);
  const expiresAt = now + ACCESS_TOKEN_TTL_SECONDS;

  const claims: AccessTokenClaims = {
    sub: deviceId,
    device_id: deviceId,
    scope: 'events:write',
    iss: JWT_ISSUER,
    aud: JWT_AUDIENCE,
    iat: now,
    exp: expiresAt,
  };

  const header = { alg: 'HS256', typ: 'JWT' };
  const encodedHeader = base64urlEncodeJSON(header);
  const encodedPayload = base64urlEncodeJSON(claims);
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await signHMAC(env.JWT_SIGNING_SECRET, signingInput);

  return {
    token: `${signingInput}.${signature}`,
    expiresAt,
  };
}

export async function verifyAccessToken(env: Env, token: string): Promise<AccessTokenClaims | null> {
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const jwtKey = await importJWTKey(env.JWT_SIGNING_SECRET);
  const signatureBytes = base64urlDecodeToBytes(encodedSignature);
  const isValidSignature = await crypto.subtle.verify(
    'HMAC',
    jwtKey,
    toArrayBuffer(signatureBytes),
    encoder.encode(signingInput)
  );
  if (!isValidSignature) return null;

  let payload: AccessTokenClaims;
  try {
    payload = JSON.parse(decoder.decode(base64urlDecodeToBytes(encodedPayload)));
  } catch {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  if (payload.iss !== JWT_ISSUER) return null;
  if (payload.aud !== JWT_AUDIENCE) return null;
  if (payload.scope !== 'events:write') return null;
  if (payload.device_id !== payload.sub) return null;
  if (!Number.isFinite(payload.iat) || !Number.isFinite(payload.exp)) return null;
  if (payload.exp <= now) return null;
  if (payload.iat > now + 60) return null;

  return payload;
}

export async function verifyDeviceSignature(
  publicKeyBase64url: string,
  message: string,
  signatureBase64url: string
): Promise<boolean> {
  try {
    const publicKeyBytes = base64urlDecodeToBytes(publicKeyBase64url);
    const signatureBytes = base64urlDecodeToBytes(signatureBase64url);

    if (publicKeyBytes.length !== 65) return false;
    if (signatureBytes.length !== 64) return false;

    const key = await crypto.subtle.importKey(
      'raw',
      toArrayBuffer(publicKeyBytes),
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify']
    );

    return crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      key,
      toArrayBuffer(signatureBytes),
      encoder.encode(message)
    );
  } catch {
    return false;
  }
}

async function importJWTKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify']
  );
}

async function signHMAC(secret: string, input: string): Promise<string> {
  const key = await importJWTKey(secret);
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(input));
  return base64urlEncodeBytes(new Uint8Array(signature));
}

function base64urlEncodeJSON(value: unknown): string {
  return base64urlEncodeBytes(encoder.encode(JSON.stringify(value)));
}

function base64urlEncodeBytes(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function base64urlDecodeToBytes(value: string): Uint8Array {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);

  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }

  return bytes;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}
