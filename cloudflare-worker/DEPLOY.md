# Deploy & Promotion Flow

## Environments

| Environment | Worker Name | KV Namespace | Cron | iOS Build |
|-------------|-------------|-------------|------|-----------|
| Local dev | `wrangler dev` (in-memory KV) | local | n/a | n/a |
| Staging | `event-digest-worker-staging` | staging-EVENTS | none | DEBUG |
| Production | `event-digest-worker` | production-EVENTS | `0 8 * * *` | RELEASE |

## Day-to-day workflow

1. **Develop locally:**
   ```bash
   npm run dev
   ```
   Uses `.dev.vars` for secrets and in-memory KV.

2. **Deploy to staging:**
   ```bash
   npm run deploy:staging
   ```

3. **Verify staging:**
   - Test endpoints with curl or iOS debug build
   - Check admin dashboard at staging URL
   - Optionally trigger a test digest

4. **Promote to production:**
   ```bash
   npm run deploy:production
   ```
   Deploys the same code from your working directory. There is no "promote" step.

## iOS environment switching

Debug builds (`Cmd+R` in Xcode) hit **staging**. Release/archive builds hit **production**. Controlled by `#if DEBUG` in `APIConfiguration.swift`.

## Secrets management

Secrets are set per-environment and persist across deploys:
```bash
# Production
npx wrangler secret put SECRET_NAME

# Staging
npx wrangler secret put SECRET_NAME --env staging
```

List secrets: `npx wrangler secret list [--env staging]`

**Important:** Use different values for `JWT_SIGNING_SECRET` and `ADMIN_DASHBOARD_KEY` across environments so staging tokens cannot be used against production.

## Rolling back

```bash
npx wrangler rollback [--env staging]
```
Wrangler keeps recent deployment versions. This instantly reverts to the previous deploy.

## KV data

Staging and production use completely separate KV namespaces. Device registrations, events, and usage data do not cross environments.

```bash
# Production
npx wrangler kv key list --namespace-id=88cdb7c27c1d41169d84c817e2d86c34

# Staging
npx wrangler kv key list --namespace-id=<STAGING_ID>
```
