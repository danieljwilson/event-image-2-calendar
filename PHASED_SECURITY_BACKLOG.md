# Phased Security Backlog (Execution Plan)

Last updated: March 6, 2026

This backlog translates the security roadmap into ticket-sized implementation work with file-level diff plans per sprint.

## Scope

- Add Apple App Attest device provenance checks.
- Add real user auth/authz (Sign in with Apple first-class, Google optional provider).
- Replace KV rate-limit counters with stronger primitives (Durable Objects + WAF).
- Add centralized monitoring and alerting.
- Automate JWT signing key rotation with runbook validation.

## Assumptions

- Cloudflare Worker remains the API edge.
- iOS minimum remains iOS 17+.
- Existing event payload contract stays backward compatible where possible.
- New controls are rolled out behind feature flags.

## Milestones

1. M1: Attested device + user session auth in staging.
2. M2: Durable-object rate limiting + WAF live.
3. M3: Monitoring/alerting and automated key rotation production-ready.
4. M4: Legacy fallback paths removed.

---

## Sprint 1: Environment and Feature-Flag Foundation

### Goal

Create safe rollout rails and prevent hard cutovers.

### Tickets

#### SEC-101: Add staging/prod environment separation for Worker

- Type: Infra
- Estimate: 1 day
- Dependencies: none
- Acceptance criteria:
  - `wrangler.toml` contains explicit `staging` and `production` sections.
  - Separate bindings/secrets are documented.

Planned file-level diffs:

```diff
*** Update File: cloudflare-worker/wrangler.toml
@@
 name = "event-digest-worker"
 main = "src/index.ts"
 compatibility_date = "2024-01-01"
+[env.staging]
+name = "event-digest-worker-staging"
+...
+[env.production]
+name = "event-digest-worker"
+...
```

#### SEC-102: Add security feature flags and config surface

- Type: Backend
- Estimate: 1 day
- Dependencies: SEC-101
- Acceptance criteria:
  - Worker reads flags from env vars.
  - Defaults are non-breaking in staging.

Planned file-level diffs:

```diff
*** Update File: cloudflare-worker/src/types.ts
@@
 export interface Env {
   ...
+  ENFORCE_APP_ATTEST: string;
+  ENFORCE_USER_AUTH: string;
+  ENFORCE_DO_RATE_LIMIT: string;
 }
```

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
+const enforceAppAttest = env.ENFORCE_APP_ATTEST === 'true';
+const enforceUserAuth = env.ENFORCE_USER_AUTH === 'true';
+const enforceDORateLimit = env.ENFORCE_DO_RATE_LIMIT === 'true';
```

#### SEC-103: CI additions for env-aware integration runs

- Type: DevOps
- Estimate: 0.5 day
- Dependencies: SEC-101
- Acceptance criteria:
  - CI has staging integration job stubs (manual trigger).

Planned file-level diffs:

```diff
*** Update File: .github/workflows/ci-security.yml
@@
 jobs:
+  staging-integration:
+    if: github.event_name == 'workflow_dispatch'
+    ...
```

Sprint exit criteria:

- Staging/prod env split complete.
- Feature flags available.
- No runtime behavior change in production yet.

---

## Sprint 2: Apple App Attest (Device Provenance)

### Goal

Require hardware-backed app assertions before trusted token issuance.

### Tickets

#### SEC-201: Add iOS App Attest service and key lifecycle

- Type: iOS
- Estimate: 2 days
- Dependencies: SEC-101
- Acceptance criteria:
  - App creates App Attest key ID once and stores in Keychain.
  - App can request challenge + submit attestation/assertion payload.

Planned file-level diffs:

```diff
*** Add File: EventImage2Calendar/Services/AppAttestService.swift
+enum AppAttestService { ... }
```

```diff
*** Update File: EventImage2Calendar/Services/WorkerAuthService.swift
@@
-let registerBody = RegisterRequest(...)
+let attestation = try await AppAttestService.attest(...)
+let registerBody = RegisterRequest(..., appAttest: attestation)
```

#### SEC-202: Add Worker challenge + attestation verify pipeline

- Type: Backend
- Estimate: 2 days
- Dependencies: SEC-201
- Acceptance criteria:
  - `/attest/challenge` issues nonce challenge.
  - `/auth/register` validates attestation payload + nonce freshness.
  - Device record stores attestation metadata.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/src/appAttest.ts
+export async function verifyAppAttest(...) { ... }
```

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
+if (request.method === 'POST' && url.pathname === '/attest/challenge') {
+  return handleAttestChallenge(request, env);
+}
@@
-return handleRegisterDevice(request, env);
+return handleRegisterDeviceWithAttest(request, env);
```

```diff
*** Update File: cloudflare-worker/src/types.ts
@@
+export interface AppAttestEvidence { ... }
+export interface DeviceRecord { ..., appAttest: { ... } }
```

#### SEC-203: Replay and counter protections for assertions

- Type: Backend
- Estimate: 1 day
- Dependencies: SEC-202
- Acceptance criteria:
  - Assertion counter monotonic check enforced.
  - Reused challenge is rejected.

Planned file-level diffs:

```diff
*** Update File: cloudflare-worker/src/validation.ts
@@
+export function validateAppAttestPayload(...) { ... }
```

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
+if (isReplayChallenge(...)) return jsonError(401, 'Replay detected');
```

#### SEC-204: App Attest tests

- Type: Test
- Estimate: 1 day
- Dependencies: SEC-202
- Acceptance criteria:
  - Positive/negative attestation flows covered.
  - Replay tests present.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/test/appAttest.test.ts
+describe('App Attest verification', ...)
```

Sprint exit criteria:

- App Attest monitor mode active in staging.
- Token issuance includes device provenance checks.

---

## Sprint 3: User Identity and Authorization (Sign in with Apple)

### Goal

Shift from device-only trust to user + device trust.

### Tickets

#### SEC-301: iOS Sign in with Apple flow + session store

- Type: iOS
- Estimate: 2 days
- Dependencies: SEC-201
- Acceptance criteria:
  - User can sign in/out via Apple.
  - Session tokens stored in Keychain.

Planned file-level diffs:

```diff
*** Add File: EventImage2Calendar/Services/UserAuthService.swift
+import AuthenticationServices
+...
```

```diff
*** Update File: EventImage2Calendar/Views/ContentView.swift
@@
-EventListView()
+if UserAuthService.shared.isAuthenticated { EventListView() } else { SignInView() }
```

```diff
*** Add File: EventImage2Calendar/Views/SignInView.swift
+struct SignInView: View { ... }
```

#### SEC-302: Worker endpoint for Apple token exchange

- Type: Backend
- Estimate: 2 days
- Dependencies: SEC-301
- Acceptance criteria:
  - `/auth/apple/exchange` validates Apple identity token (JWKS).
  - Worker issues access+refresh tokens with user claims.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/src/appleAuth.ts
+export async function verifyAppleIdentityToken(...) { ... }
```

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
+if (request.method === 'POST' && url.pathname === '/auth/apple/exchange') {
+  return handleAppleExchange(request, env);
+}
```

```diff
*** Update File: cloudflare-worker/src/security.ts
@@
-scope: 'events:write'
+scope: 'events:write',
+user_id: string
```

#### SEC-303: Enforce user-bound auth on `/events`

- Type: Backend
- Estimate: 1 day
- Dependencies: SEC-302
- Acceptance criteria:
  - `/events` rejects tokens without `user_id`.
  - Stored event includes `userId` metadata for audit.

Planned file-level diffs:

```diff
*** Update File: cloudflare-worker/src/types.ts
@@
 export interface StoredEventPayload extends EventPayload {
   deviceId: string;
+  userId: string;
 }
```

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
-const claims = await authenticateEventRequest(...)
+const claims = await authenticateEventRequest(...)
+if (!claims.user_id) return jsonError(401, 'User auth required');
```

#### SEC-304: User auth tests

- Type: Test
- Estimate: 1 day
- Dependencies: SEC-302
- Acceptance criteria:
  - Exchange, refresh, revoke, invalid signature, expired token tests pass.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/test/userAuth.test.ts
+describe('Apple exchange + session auth', ...)
```

Sprint exit criteria:

- Staging requires user + device context for event writes.
- Device-only legacy path behind explicit off-by-default flag.

---

## Sprint 4: Durable Object + WAF Rate Limiting

### Goal

Replace eventually-consistent KV limits with atomic/edge controls.

### Tickets

#### SEC-401: Introduce Durable Object rate limiter

- Type: Backend
- Estimate: 2 days
- Dependencies: SEC-101
- Acceptance criteria:
  - DO enforces per-user/device/IP limits atomically.
  - Worker route uses DO when `ENFORCE_DO_RATE_LIMIT=true`.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/src/rateLimiterDO.ts
+export class RateLimiterDO { ... }
```

```diff
*** Update File: cloudflare-worker/src/types.ts
@@
 export interface Env {
   ...
+  RATE_LIMITER: DurableObjectNamespace;
 }
```

```diff
*** Update File: cloudflare-worker/wrangler.toml
@@
+[[durable_objects.bindings]]
+name = "RATE_LIMITER"
+class_name = "RateLimiterDO"
```

#### SEC-402: Remove KV counter dependency in write path

- Type: Backend
- Estimate: 1 day
- Dependencies: SEC-401
- Acceptance criteria:
  - No `ratelimit:*` KV writes in event path when DO enforced.

Planned file-level diffs:

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
-await env.EVENTS.put(`ratelimit:...`)
+await enforceWithDurableObject(...)
```

#### SEC-403: Add Cloudflare WAF rule definition and runbook

- Type: Infra
- Estimate: 1 day
- Dependencies: SEC-101
- Acceptance criteria:
  - WAF rate rule configured for `/events`.
  - Documented bypass logic for trusted internal traffic.

Planned file-level diffs:

```diff
*** Add File: docs/WAF_RATE_LIMIT_RUNBOOK.md
+# WAF Rule Setup and Rollback
```

#### SEC-404: Load tests for rate limiting

- Type: Test
- Estimate: 1 day
- Dependencies: SEC-401
- Acceptance criteria:
  - Concurrency tests prove deterministic 429 behavior.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/test/rateLimiter.test.ts
+describe('DO rate limiter', ...)
```

Sprint exit criteria:

- DO limits enforceable in staging.
- WAF rules deployed in monitor/challenge mode.

---

## Sprint 5: Centralized Monitoring and Alerting

### Goal

Turn security events into operationally actionable signals.

### Tickets

#### SEC-501: Standardize security event schema and emitters

- Type: Backend
- Estimate: 1.5 days
- Dependencies: SEC-202, SEC-302, SEC-401
- Acceptance criteria:
  - Structured JSON events emitted for auth, attestation, rate-limit, digest failures.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/src/telemetry.ts
+export function securityEvent(type, fields) { ... }
```

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
-console.error('Resend failure', ...)
+securityEvent('digest_send_failed', {...})
```

#### SEC-502: Log export and alert policy implementation

- Type: Infra
- Estimate: 1.5 days
- Dependencies: SEC-501
- Acceptance criteria:
  - Log export configured to centralized sink.
  - Alert thresholds defined and tested.

Planned file-level diffs:

```diff
*** Add File: docs/SECURITY_ALERTING.md
+# Alert rules, severities, and runbook links
```

#### SEC-503: Incident response runbook and ownership

- Type: Process
- Estimate: 0.5 day
- Dependencies: SEC-502
- Acceptance criteria:
  - On-call owner and escalation path documented.

Planned file-level diffs:

```diff
*** Update File: SECURITY.md
@@
+## Alerting and Incident Response
+...
```

Sprint exit criteria:

- Security events visible in dashboards.
- Test incident triggers alert end-to-end.

---

## Sprint 6: Automated JWT Key Rotation + Runbook Validation

### Goal

Eliminate manual, risky key lifecycle handling.

### Tickets

#### SEC-601: Multi-key JWT model with `kid`

- Type: Backend
- Estimate: 2 days
- Dependencies: SEC-302
- Acceptance criteria:
  - Tokens include `kid`.
  - Verification supports active + grace keys.
  - Old keys retire after overlap window.

Planned file-level diffs:

```diff
*** Update File: cloudflare-worker/src/security.ts
@@
-const signature = await signHMAC(env.JWT_SIGNING_SECRET, input)
+const signature = await signWithKey(activeKey.kid, activeKey.secret, input)
@@
-verifyAccessToken(env, token)
+verifyAccessToken(env, token, keyset)
```

```diff
*** Update File: cloudflare-worker/src/types.ts
@@
+export interface JwtKeyConfig { kid: string; secret: string; status: 'active'|'grace'|'retired' }
```

#### SEC-602: Rotation automation workflow

- Type: DevOps
- Estimate: 1.5 days
- Dependencies: SEC-601
- Acceptance criteria:
  - Scheduled/manual workflow rotates keyset in staging then production.
  - Rotation emits audit event.

Planned file-level diffs:

```diff
*** Add File: .github/workflows/jwt-key-rotation.yml
+name: JWT Key Rotation
+on:
+  schedule: ...
+  workflow_dispatch:
```

#### SEC-603: Rotation runbook tests

- Type: Test
- Estimate: 1 day
- Dependencies: SEC-602
- Acceptance criteria:
  - Automated staging validation proves:
    - New tokens valid.
    - Existing grace-window tokens valid.
    - Retired-key tokens rejected.

Planned file-level diffs:

```diff
*** Add File: cloudflare-worker/test/keyRotation.test.ts
+describe('JWT key rotation', ...)
```

```diff
*** Update File: .github/workflows/ci-security.yml
@@
+  rotation-validation:
+    ...
```

Sprint exit criteria:

- Rotation can be executed safely without outage.
- Runbook and automated validation are green.

---

## Sprint 7: Legacy Path Removal and Production Enforcement

### Goal

Finalize migration and remove fallback risk.

### Tickets

#### SEC-701: Remove device-only and non-attested fallback paths

- Type: Backend/iOS
- Estimate: 1 day
- Dependencies: Sprints 2-6 complete
- Acceptance criteria:
  - All event writes require user JWT + App Attest-backed device context.

Planned file-level diffs:

```diff
*** Update File: cloudflare-worker/src/index.ts
@@
-if (!enforceUserAuth) { ...legacy... }
+if (!claims.user_id) return jsonError(401, 'User auth required');
```

```diff
*** Update File: EventImage2Calendar/Services/WorkerAuthService.swift
@@
-fallbackIfUnattested(...)
+hardFailIfUnattested(...)
```

#### SEC-702: Update architecture/security docs to final state

- Type: Documentation
- Estimate: 0.5 day
- Dependencies: SEC-701
- Acceptance criteria:
  - Security docs reflect final production architecture.

Planned file-level diffs:

```diff
*** Update File: SECURITY.md
*** Update File: SECURITY_ARCHITECTURE.md
```

Sprint exit criteria:

- Legacy auth paths removed from codebase.
- Production enforcement enabled.

---

## Backlog Prioritization

### P0 (Blocker before broad production scale)

- SEC-201, SEC-202, SEC-301, SEC-302, SEC-401, SEC-601

### P1

- SEC-203, SEC-303, SEC-402, SEC-501, SEC-602

### P2

- SEC-103, SEC-403, SEC-503, SEC-603, SEC-702

## Release Readiness Checklist

1. All P0/P1 tickets complete.
2. CI required checks passing.
3. Security alerts tested in staging.
4. Key rotation dry-run executed successfully.
5. Architecture/security docs updated and reviewed.

## Operational KPIs

- Auth token issuance success rate.
- App Attest verification pass/fail rate.
- Event write 401/429 rates by user/device/IP.
- Digest delivery success/failure count.
- JWT key rotation success rate and elapsed time.
