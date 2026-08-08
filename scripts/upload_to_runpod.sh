#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNPOD_SSH_HOST="${RUNPOD_SSH_HOST:?Set RUNPOD_SSH_HOST to the Pod public IP}"
RUNPOD_SSH_PORT="${RUNPOD_SSH_PORT:?Set RUNPOD_SSH_PORT to the Pod SSH port}"
RUNPOD_SSH_KEY="${RUNPOD_SSH_KEY:?Set RUNPOD_SSH_KEY to the private key path}"
REMOTE_DIR="${REMOTE_DIR:-/workspace/masafy-h3-lora}"

[[ -f "${RUNPOD_SSH_KEY}" ]] || { echo "SSH key not found: ${RUNPOD_SSH_KEY}" >&2; exit 1; }
[[ -d "${REPO_DIR}/dataset/train" ]] || { echo "Prepare the dataset before uploading." >&2; exit 1; }

ssh -i "${RUNPOD_SSH_KEY}" -p "${RUNPOD_SSH_PORT}" \
  -o StrictHostKeyChecking=accept-new "root@${RUNPOD_SSH_HOST}" \
  "mkdir -p '${REMOTE_DIR}'"

rsync -az \
  --exclude '.git/' \
  --exclude '.venv/' \
  --exclude 'output/*' \
  --exclude 'status/*' \
  --exclude 'logs/*' \
  -e "ssh -i ${RUNPOD_SSH_KEY} -p ${RUNPOD_SSH_PORT} -o StrictHostKeyChecking=accept-new" \
  "${REPO_DIR}/" "root@${RUNPOD_SSH_HOST}:${REMOTE_DIR}/"

echo "Uploaded repository and prepared dataset to ${REMOTE_DIR}"
