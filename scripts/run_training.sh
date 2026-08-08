#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${1:-${REPO_DIR}/config/train_h3_masafy_smoke.yaml}"
AI_TOOLKIT_DIR="${AI_TOOLKIT_DIR:-/workspace/ai-toolkit}"
AI_TOOLKIT_VENV="${AI_TOOLKIT_VENV:-/workspace/ai-toolkit-venv}"
HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-60}"

CONFIG_PATH="$(cd "$(dirname "${CONFIG_PATH}")" && pwd)/$(basename "${CONFIG_PATH}")"
run_name="$(basename "${CONFIG_PATH}" .yaml)"
run_name="${run_name%.yml}"
LOG_DIR="${REPO_DIR}/logs"
STATUS_DIR="${REPO_DIR}/status"
LOG_PATH="${LOG_DIR}/${run_name}.log"
STATUS_PATH="${STATUS_DIR}/heartbeat.json"
PID_PATH="${STATUS_DIR}/training.pid"

mkdir -p "${LOG_DIR}" "${STATUS_DIR}" "${REPO_DIR}/output" "${REPO_DIR}/records"

if [[ -f "${PID_PATH}" ]]; then
  existing_pid="$(tr -dc '0-9' < "${PID_PATH}")"
  if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    echo "Training already appears to be running with PID ${existing_pid}." >&2
    exit 1
  fi
fi

"${REPO_DIR}/scripts/preflight.sh" "${CONFIG_PATH}"

if [[ -d /workspace/ComfyUI/models ]]; then
  export MODELS_PATH="${MODELS_PATH:-/workspace/ComfyUI/models}"
else
  export MODELS_PATH="${MODELS_PATH:-/workspace/models}"
fi
export HF_HOME="${HF_HOME:-/workspace/huggingface-cache}"
export PYTHONUNBUFFERED=1
mkdir -p "${MODELS_PATH}" "${HF_HOME}"

echo "Starting training"
echo "config=${CONFIG_PATH}"
echo "models_path=${MODELS_PATH}"
echo "log=${LOG_PATH}"
echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

: > "${LOG_PATH}"
cd "${AI_TOOLKIT_DIR}"
"${AI_TOOLKIT_VENV}/bin/python" -u run.py "${CONFIG_PATH}" > "${LOG_PATH}" 2>&1 &
training_pid=$!
printf '%s\n' "${training_pid}" > "${PID_PATH}"

tail --pid="${training_pid}" -n +1 -F "${LOG_PATH}" &
tail_pid=$!

"${AI_TOOLKIT_VENV}/bin/python" "${REPO_DIR}/scripts/heartbeat.py" \
  --pid "${training_pid}" \
  --log "${LOG_PATH}" \
  --status "${STATUS_PATH}" \
  --config "${CONFIG_PATH}" \
  --interval "${HEARTBEAT_INTERVAL}" &
heartbeat_pid=$!

set +e
wait "${training_pid}"
exit_code=$?
set -e

kill "${heartbeat_pid}" 2>/dev/null || true
wait "${heartbeat_pid}" 2>/dev/null || true
wait "${tail_pid}" 2>/dev/null || true

"${AI_TOOLKIT_VENV}/bin/python" - "${STATUS_PATH}" "${CONFIG_PATH}" "${training_pid}" "${exit_code}" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

status_path = Path(sys.argv[1])
config_path = sys.argv[2]
pid = int(sys.argv[3])
exit_code = int(sys.argv[4])
payload = {}
if status_path.exists():
    try:
        payload = json.loads(status_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        payload = {}
payload.update(
    {
        "schema_version": 1,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "state": "completed" if exit_code == 0 else "failed",
        "process_alive": False,
        "training_pid": pid,
        "config": config_path,
        "exit_code": exit_code,
    }
)
if exit_code == 0 and payload.get("total_steps") is not None:
    payload["current_step"] = payload["total_steps"]
temporary = status_path.with_suffix(status_path.suffix + ".tmp")
temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
os.replace(temporary, status_path)
print("MASAFY_TRAINING_FINAL " + json.dumps(payload, ensure_ascii=False))
PY

rm -f "${PID_PATH}"
echo "Training finished with exit_code=${exit_code}"
exit "${exit_code}"
