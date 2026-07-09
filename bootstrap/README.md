# Bootstrap — one-time manual setup

Terraform can't create the thing it needs to store its own state in, and (without
existing credentials) can't be the first thing to authenticate against a brand
new project either. These steps are manual, run once, before `terraform init`
ever runs in `environments/mvp-test/`.

Project already created: **pivot-project-501905** (project number `25190701001`).

## 1. Install the gcloud CLI

```bash
brew install --cask google-cloud-sdk
gcloud init
```

## 2. Authenticate

```bash
gcloud auth login
gcloud config set project pivot-project-501905

# Application Default Credentials — what the Terraform google provider
# actually uses locally. Prefer this over a static service-account JSON key
# on a laptop.
gcloud auth application-default login
```

## 3. Confirm billing is linked

A project with no billing account can't create Compute Engine resources.

```bash
gcloud billing accounts list
gcloud billing projects describe pivot-project-501905
```

If `billingEnabled: false`, link one (create a billing account in the Cloud
Console first if you don't have one yet — that step requires a human with a
payment method, it's not scriptable):

```bash
gcloud billing projects link pivot-project-501905 \
  --billing-account=YOUR-BILLING-ACCOUNT-ID
```

## 4. Enable required APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project=pivot-project-501905
```

## 5. Create the Terraform state bucket

```bash
gcloud storage buckets create gs://pivot-project-501905-tfstate \
  --project=pivot-project-501905 \
  --location=europe-west1 \
  --uniform-bucket-level-access

gcloud storage buckets update gs://pivot-project-501905-tfstate \
  --versioning
```

Versioning matters here specifically because this bucket has no other backup —
a bad `apply` or an accidental `state rm` should still be recoverable from a
prior object version.

## 6. Generate an SSH key pair for the deploy user

Reused by `terraform.tfvars` (`ssh_public_key`) and later as the `PROD_SSH_KEY`
GitHub secret for `pivot-core`'s `deploy.yml` (EN07.5):

```bash
ssh-keygen -t ed25519 -C "pivot-mvp-deploy" -f ~/.ssh/pivot_mvp_deploy -N ""
```

## 7. Init Terraform against the bucket

```bash
cd environments/mvp-test
cp terraform.tfvars.example terraform.tfvars   # fill in real values
terraform init -backend-config="bucket=pivot-project-501905-tfstate"
terraform plan
```

Review the plan before `terraform apply` — it creates billed resources (see
`../README.md` for the cost estimate).
