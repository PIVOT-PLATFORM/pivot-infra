# pivot-infra

Terraform IaC provisioning the GCP host for the PIVOT MVP test deployment.

## Scope

Provisions **one Compute Engine VM** that runs `pivot-core`'s
`docker-compose.prod.yml` stack (nginx + pivot-core + postgres + redis +
activemq) — matching the architecture actually on `pivot-core`'s `main`
(EN07.1 docker-compose.prod.yml, EN07.3 ActiveMQ). It deliberately does
**not** target Cloud Run / GKE / managed Cloud SQL: that stack is a
single-host stateful Docker Compose deployment today, and reshaping it into
managed services is a separate, bigger decision — out of scope for an MVP
test. PgBouncer (EN07.4) is still Backlog upstream — not part of this stack.

Two layers:
- **Terraform** (`modules/`, `environments/`) — the VM, network, firewall, static IP.
- **Ansible** (`ansible/`) — everything on top: `docker-compose.prod.yml` +
  ActiveMQ config synced from a local `pivot-core` checkout, secrets (Postgres/OTP/mail
  passwords, GHCR PAT) encrypted at rest via `ansible-vault` and delivered with
  per-consumer-UID POSIX ACLs (not a blanket world-readable mode — Compose's
  non-swarm `secrets:` are plain bind mounts, so host file permissions apply
  verbatim inside each container), a self-signed TLS cert, and `docker compose up -d`.

This is a stand-in for `pivot-core`'s own `.github/workflows/deploy.yml`
(EN07.5, which SSHes in and runs `docker compose pull && up -d` against a
directory it assumes is already populated "out of CI") — the Ansible
playbook here is exactly that out-of-band population step, made repeatable.

## Layout

```
pivot-infra/
├── modules/compute-vm/       # Reusable module: VPC, firewall, static IP, VM, service account
├── environments/mvp-test/    # Root Terraform config for the MVP test environment
├── ansible/                  # App-level config + deploy — see ansible/playbook.yml
│   ├── group_vars/mvp_test/
│   │   ├── vars.yml          # non-secret config
│   │   └── vault.yml         # ansible-vault encrypted (postgres/otp/mail passwords, GHCR PAT)
│   └── roles/pivot_deploy/
└── bootstrap/                # One-time manual setup (gcloud, billing, state bucket) — README.md
```

## Getting started

1. Do the one-time manual setup: [`bootstrap/README.md`](bootstrap/README.md).
2. `cd environments/mvp-test && terraform init -backend-config="bucket=<state-bucket>"`
3. `terraform plan` — review before applying, this creates billed resources.
4. `terraform apply`
5. Update `ansible/group_vars/mvp_test/vars.yml` (`app_external_ip`,
   `pivot_core_repo_path`) with `terraform output external_ip` and your local
   `pivot-core` checkout path.
6. Get `ansible/.vault_pass` (not committed — share out of band) and run:
   ```
   cd ansible && ansible-playbook playbook.yml
   ```
   Idempotent — re-run any time `pivot-core`'s `docker-compose.prod.yml` changes,
   or to rotate a secret (edit via `ansible-vault edit group_vars/mvp_test/vault.yml`).
7. Optionally wire `PROD_SSH_HOST`/`PROD_SSH_USER`/`PROD_SSH_KEY`/`PROD_DEPLOY_PATH=/opt/pivot`
   as GitHub secrets on `pivot-core` so EN07.5's `deploy.yml` can also target this VM.

### Known gaps hit running this for real (2026-07-09)

- **GHCR image path bug** (`release.yml`, pivot-core *and* pivot-ui): images publish to
  `ghcr.io/pivot-platform/<repo>/<repo>` (doubled segment) instead of
  `ghcr.io/pivot-platform/<repo>` as `docker-compose.prod.yml` expects. The playbook pulls
  from the real path and retags — a workaround, not a fix. Needs a PR upstream.
- **Published `pivot-ui:latest` predates EN17.7** — no `backend` network alias needed by its
  baked-in `nginx.conf`, and no TLS listener at all. `ansible/roles/pivot_deploy/templates/
  docker-compose.override.yml.j2` restores the alias so nginx boots; **HTTPS won't work until
  pivot-ui publishes a newer image** — this stack is HTTP-only on this VM for now.

## Cost (europe-west1, MVP test defaults)

Rough always-on estimate — actual billing depends on region/usage:

| Resource | ~Monthly |
|---|---|
| `e2-medium` VM (2 vCPU / 4GB) | ~$25 |
| 30GB `pd-balanced` boot disk | ~$4 |
| Static external IP (in use) | ~$0 (charged only when reserved but unattached) |
| Egress | usage-based, negligible for a test |

**~$30/month** while the VM runs continuously. For a test that doesn't need to
be always-on, stop the instance between test sessions
(`gcloud compute instances stop pivot-mvp-vm --zone=<zone>`) — Compute Engine
doesn't bill the VM (only the disk, ~$4/mo) while stopped.

## Known limitations (acceptable for an MVP test, not for real prod)

- Postgres/Redis data lives on the boot disk, not a separate persistent disk —
  destroying the VM destroys the data. Fine for a disposable test; a real
  production Enabler would split this out (or move to managed Cloud SQL/Memorystore).
- No Cloud DNS / managed TLS cert automation — `docker-compose.prod.yml`
  already supports mounting a self-signed or Let's Encrypt cert manually per
  its own comments; wiring that up is a separate step, not done here.
- Single VM, no HA — matches the current single-host architecture, not a
  scaling concern for a first MVP test.
