#!/bin/bash
# Runs once on first boot (GCE re-runs it on every boot, but every step here
# is idempotent). Installs Docker Engine + the Compose plugin that
# pivot-core/docker-compose.prod.yml (EN07.1) needs, and prepares the
# directory EN07.5's deploy.yml expects at PROD_DEPLOY_PATH.
set -euo pipefail

if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker

# EN07.5 deploy.yml SSHes in as PROD_SSH_USER and runs `docker compose` from
# PROD_DEPLOY_PATH — grant that user docker access without sudo.
DEPLOY_USER="${deploy_user}"
if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
  usermod -aG docker "$DEPLOY_USER"
fi

install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 0750 /opt/pivot
