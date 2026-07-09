# pivot-infra

Terraform IaC provisioning the GCP host for the PIVOT MVP test deployment.

## Scope

Provisions **one Compute Engine VM** that runs `pivot-core`'s
`docker-compose.prod.yml` stack (nginx + pivot-core + pgbouncer + postgres +
redis) — matching the architecture already built in `pivot-core` (EN07.1
docker-compose.prod.yml, EN07.5 deploy.yml). It deliberately does **not**
target Cloud Run / GKE / managed Cloud SQL: that stack is a single-host
stateful Docker Compose deployment today, and reshaping it into managed
services is a separate, bigger decision — out of scope for an MVP test.

This repo provisions the **infrastructure** (VM, network, firewall, static
IP). It does not deploy the application — that's `pivot-core`'s
`.github/workflows/deploy.yml` (EN07.5), which SSHes in and runs
`docker compose pull && up -d`.

## Layout

```
pivot-infra/
├── modules/compute-vm/       # Reusable module: VPC, firewall, static IP, VM, service account
├── environments/mvp-test/    # Root config for the MVP test environment
└── bootstrap/                # One-time manual setup (gcloud, billing, state bucket) — README.md
```

## Getting started

1. Do the one-time manual setup: [`bootstrap/README.md`](bootstrap/README.md).
2. `cd environments/mvp-test && terraform init -backend-config="bucket=<state-bucket>"`
3. `terraform plan` — review before applying, this creates billed resources.
4. `terraform apply`
5. Take `terraform output external_ip` and:
   - Point a DNS A record at it (if you have a domain), or use the IP directly.
   - Set it as the `PROD_SSH_HOST` GitHub secret on `pivot-core` (EN07.5 `deploy.yml`).
   - Set `PROD_SSH_USER` / `PROD_SSH_KEY` from the key pair generated in bootstrap step 6.
   - Set `PROD_DEPLOY_PATH=/opt/pivot` (created by the VM's startup script).
6. Sync `docker-compose.prod.yml`, `pgbouncer/`, and the `secrets/` files (EN07.2) to
   `/opt/pivot` on the VM — this repo doesn't manage that; it's the same
   "synchronised out of CI" step `EN07.5`'s spec already assumes.

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
