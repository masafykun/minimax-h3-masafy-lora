#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${1:-${REPO_DIR}/config/train_h3_masafy_smoke.yaml}"
LAUNCHER_LOG="${REPO_DIR}/logs/launcher.log"
mkdir -p "${REPO_DIR}/logs" "${REPO_DIR}/status"

if [[ -f "${REPO_DIR}/status/training.pid" ]]; then
  existing_pid="$(tr -dc '0-9' < "${REPO_DIR}/status/training.pid")"
  if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    echo "Training is already running with PID ${existing_pid}." >&2
    exit 1
  fi
fi

if [[ -w /proc/1/fd/1 && -w /proc/1/fd/2 ]]; then
  stdout_target=/proc/1/fd/1
  stderr_target=/proc/1/fd/2
else
  stdout_target="${LAUNCHER_LOG}"
  stderr_target="${LAUNCHER_LOG}"
fi

nohup setsid "${REPO_DIR}/scripts/run_training.sh" "${CONFIG_PATH}" \
  > "${stdout_target}" 2> "${stderr_target}" < /dev/null &
launcher_pid=$!
printf '%s\n' "${launcher_pid}" > "${REPO_DIR}/status/launcher.pid"

echo "Detached launcher started: pid=${launcher_pid}"
echo "Status: ${REPO_DIR}/status/heartbeat.json"
echo "Logs: ${REPO_DIR}/logs"
echo "Do not stop or terminate the Pod until outputs are backed up."
