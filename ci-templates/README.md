# CI templates — service-repo adoption (migration Phase 1 & 4)

These are **reference templates**, not live workflows. They belong in the
governed service repos and must be ported there through each repo's ACDD
workflow (branch `feat/{en-id}-…`, GitHub issue first, draft PR, Gates 1–4,
squash-merge). Nothing here bypasses that.

| File | Ports into | Purpose |
|---|---|---|
| `release-artifact-registry.snippet.yml` | each service `release.yml` | Add keyless-WIF push to Artifact Registry (+ digest), dual-push with GHCR during Phase 1 |
| `deploy-notifier.yml` | each service `deploy.yml` | Replace SSH deploy / TODO stubs with a thin "resolve digest → notify orchestrator" job |
| (orchestrator) `../.github/workflows/deploy-orchestrator.yml` | **pivot-infra** (already here) | Central Cloud Run rollout: auto recette, gated+canary prod |

## Per-repo mapping

| Repo | SERVICE / image | Notes |
|---|---|---|
| `pivot-core` | `pivot-core` (8080) | `deploy.yml` exists (SSH) → replace with notifier |
| `pivot-collaboratif-core` | `pivot-collaboratif-core` (8083) | `deploy.yml` is a TODO stub → implement as notifier |
| `pivot-collaboratif-ui` | (SPA) | no Cloud Run service — CI uploads `dist/` to the SPA bucket (see pivot-ui pattern), stub → SPA-upload job |
| `pivot-ui` | (SPA) | `deploy.yml` (SSH nginx) → SPA-upload-to-bucket + CDN invalidate; no nginx image built anymore |

## Required repo configuration (all keyless — no GCP keys)

Set as repository (or org) **variables**, from the `recette-managed` Terraform outputs:

```
vars.WIF_PROVIDER = $(terraform output -raw wif_provider_name)
vars.DEPLOYER_SA  = $(terraform output -json deployer_emails | jq -r '.["<repo>"]')
vars.AR_HOST      = europe-west1-docker.pkg.dev
vars.AR_IMAGE     = $(terraform output -raw image_prefix)/<service>
```

One **secret** (a GitHub credential, not GCP): `ORCHESTRATOR_DISPATCH_TOKEN` —
a fine-grained PAT or GitHub App token scoped to `PIVOT-PLATFORM/pivot-infra`
with `repository_dispatch`. This is the only long-lived credential; everything
touching GCP is keyless via WIF.

Grant the deployer SA `roles/artifactregistry.reader` (in addition to writer)
so the notifier can resolve the released digest — add it to the deployer's
`project_roles` in `modules/iam-wif` if not already present.

## App-config coordination (MUST land with the workflow PRs)

These preserve the compose runtime contract on Cloud Run — each is a small,
coordinated change in the service repo, flagged as TODO in
`environments/recette-managed/main.tf`:

1. **Actuator probe port** — Cloud Run probes hit the *serving* port only.
   pivot-core's actuator is on `:8081`, collaboratif on `:9083`. Either expose
   the readiness/liveness groups on the serving port for the `prod` profile, or
   set `management.server.port` = serving port. Otherwise Cloud Run startup
   probes never pass.
2. **Secret delivery** — RESOLVED, no app change. pivot-core `application.yml`
   already reads env FIRST with a configtree fallback:
   `${SPRING_DATASOURCE_PASSWORD:${secret.datasource-password:pivot}}`,
   `${SPRING_MAIL_PASSWORD:…}`, `${PIVOT_AUTH_OTP_SECRET:…}`,
   `${SPRING_DATA_REDIS_PASSWORD:${secret.redis-password:}}`. The Cloud Run
   module injects those exact env names from Secret Manager — no file mount, no
   shim. (Verified in recette-managed/main.tf.)
3. **Redis AUTH + TLS** — Memorystore now requires a password
   (`SPRING_DATA_REDIS_PASSWORD` from the `redis-auth` secret) and in-transit
   TLS (`SPRING_DATA_REDIS_SSL_ENABLED=true`). The compose stack ran Redis
   unauthenticated — this closes that gap but needs the client config.
4. **Trusted proxy** — behind the managed LB, set the trusted-proxy ranges so
   `X-Forwarded-For` / `X-Forwarded-Proto` (HTTPS detection, client IP logging)
   stay correct (collaboratif-core `internal-proxies`, pivot-core equivalent).
5. **Security headers / CSP** — nginx emitted HSTS/CSP/X-Frame-Options. Move
   HSTS to the LB, and CSP/frame headers into the SPA build + each service's
   `HttpSecurity#headers`, to keep header parity without the nginx container.

## Suggested Enabler breakdown (one branch/PR per item, per repo)

- `EN-deploy-ar-wif` — release.yml → Artifact Registry keyless push + digest (dual-push).
- `EN-deploy-notifier` — deploy.yml → orchestrator notifier (closes collaboratif stubs).
- `EN-cloudrun-config` — the 5 app-config coordination points above.
- `EN-spa-bucket` (pivot-ui / collaboratif-ui) — build → SPA bucket upload + CDN invalidate.
