#!/usr/bin/env bash
# Startup script for the ActiveMQ broker VM.
# Idempotent: safe to re-run on every boot.
set -euo pipefail

# --- 1. Mount the dedicated KahaDB persistent disk at /opt/activemq/data ------
# Only when the ActiveMQ broker runs (managed-min is Redis-only: no disk).
MOUNT=/opt/activemq/data
if [ "${run_activemq}" = "true" ]; then
  DEVICE=/dev/disk/by-id/google-kahadb
  mkdir -p "$MOUNT"

  # Format only if the disk has no filesystem yet (first boot). Never reformat an
  # existing store — that would wipe the message store on a VM recreation.
  if ! blkid "$DEVICE" >/dev/null 2>&1; then
    mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard "$DEVICE"
  fi
  grep -q "$MOUNT" /etc/fstab || echo "$DEVICE $MOUNT ext4 discard,defaults,nofail 0 2" >>/etc/fstab
  mountpoint -q "$MOUNT" || mount "$MOUNT"
fi

# --- 2. Install Docker Engine -------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
fi

# --- 3. Run the broker, KahaDB on the persistent disk -------------------------
# TODO(EN07.3 parity): mount the custom docker/activemq/activemq.xml (per-domain
# DLQ policy) from pivot-core, and set a non-default console password. The
# default image already exposes the STOMP connector on ${stomp_port}; the broker
# is only reachable from the VPC (private IP, firewall), never public.
if [ "${run_activemq}" = "true" ]; then
  docker rm -f activemq 2>/dev/null || true
  docker run -d --name activemq --restart unless-stopped \
    -p ${stomp_port}:${stomp_port} \
    -v "$MOUNT":/opt/apache-activemq/data \
    ${activemq_image}
fi

# --- 4. Optional co-located Redis (dev cost saver) ----------------------------
# In BUILD/recette we self-host Redis here instead of paying for Memorystore
# (~$35/mo). Cache only (module-status TTL 60s) — ephemeral, no persistence, no
# AUTH/TLS: reachable only from Cloud Run over the private VPC (firewall-scoped),
# never public. Prod uses managed Memorystore (AUTH+TLS) instead.
if [ "${run_redis}" = "true" ]; then
  docker rm -f redis 2>/dev/null || true
  docker run -d --name redis --restart unless-stopped \
    -p ${redis_port}:6379 \
    ${redis_image}
fi
