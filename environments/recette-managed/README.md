# recette-managed — foundation stack

Phase 0 of the VM→managed migration (see `pivot-docs` plan). Builds the
managed-stack foundation **alongside** the live VM (`environments/recette`,
state prefix `mvp-test`) without touching it. This environment provisions no
traffic-serving resources yet — only the substrate later phases build on:

| Module | What it creates |
|---|---|
| `network` | Custom VPC `pivot-recette-vpc` (subnet `10.20.0.0/24`), Private Service Access range (for Cloud SQL/Memorystore private IP), IAP-SSH + internal-data firewall |
| `vpc-connector` | Serverless VPC Access connector (`10.20.8.0/28`) — Cloud Run → private IPs |
| `artifact-registry` | Docker repo `pivot` in `europe-west1` (replaces GHCR), immutable tags |
| `iam-wif` | Workload Identity pool/provider + per-repo deployer SAs (keyless CI) |
| `secrets` | Secret Manager containers (`postgres-password`, `mail-password`, `otp-secret`, `redis-auth`) — values added out of band |
| (env) | Runtime SAs `sa-pivot-core`, `sa-pivot-collaboratif` + orchestrator act-as bindings |

Distinct CIDRs (`10.20.0.0/24`) from the live VM VPC (`10.10.0.0/24`) so both
coexist during transition.

## First apply (bootstrap)

The very first `apply` creates the WIF pool itself, so it must run with a
human/owner identity (local Application Default Credentials), not WIF:

```bash
gcloud auth application-default login   # owner/editor on pivot-project-501905

cd environments/recette-managed
terraform init -backend-config="bucket=pivot-project-501905-tfstate"
terraform plan -out=tf.plan
terraform apply tf.plan
```

After this, CI authenticates keyless via the WIF provider — no SA keys, no
`PROD_SSH_*`, no `GH_PACKAGES_TOKEN`.

## Populate secret values (out of band, never in Terraform)

```bash
printf '%s' "<postgres-password>" | gcloud secrets versions add postgres-password --data-file=-
printf '%s' "<mail-password>"     | gcloud secrets versions add mail-password     --data-file=-
printf '%s' "<otp-secret>"        | gcloud secrets versions add otp-secret        --data-file=-
printf '%s' "<redis-auth>"        | gcloud secrets versions add redis-auth        --data-file=-
```
Import the current values from `ansible/group_vars/recette/vault.yml`
(`ansible-vault view`).

## What CI consumes (outputs)

```bash
terraform output wif_provider_name   # -> google-github-actions/auth: workload_identity_provider
terraform output deployer_emails     # -> per-repo: service_account
terraform output image_prefix        # -> <region>-docker.pkg.dev/<proj>/pivot ; push <prefix>/<service>@sha256:<digest>
terraform output registry_host       # -> gcloud auth configure-docker <host>
```

Wire these into each service repo's `release.yml` (Phase 1) — see the plan.

## Next phases

- **Phase 1** — `release.yml` pushes to Artifact Registry (keyless WIF), emits digest.
- **Phase 2** — add `cloud-sql`, `memorystore-redis`, `activemq-vm` modules here.
- **Phase 3** — add `cloud-run-service`, `load-balancer`, `dns`; serve `recette.pivot.<domain>`.
