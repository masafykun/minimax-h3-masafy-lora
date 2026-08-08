#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${1:-${REPO_DIR}/config/train_h3_masafy_smoke.yaml}"
AI_TOOLKIT_DIR="${AI_TOOLKIT_DIR:-/workspace/ai-toolkit}"
AI_TOOLKIT_VENV="${AI_TOOLKIT_VENV:-/workspace/ai-toolkit-venv}"
MASAFY_STORAGE_PATH="${MASAFY_STORAGE_PATH:-/workspace}"
EXPECTED_COMMIT="f4e91305471a3727d52886ef6d410eb570cd484f"

[[ -f "${CONFIG_PATH}" ]] || { echo "Missing config: ${CONFIG_PATH}" >&2; exit 1; }
[[ -x "${AI_TOOLKIT_VENV}/bin/python" ]] || { echo "Run scripts/bootstrap_ai_toolkit.sh first." >&2; exit 1; }
[[ -d "${AI_TOOLKIT_DIR}/.git" ]] || { echo "Missing AI Toolkit: ${AI_TOOLKIT_DIR}" >&2; exit 1; }

current_commit="$(git -C "${AI_TOOLKIT_DIR}" rev-parse HEAD)"
if [[ "${current_commit}" != "${EXPECTED_COMMIT}" ]]; then
  echo "Unexpected AI Toolkit commit: ${current_commit}" >&2
  exit 1
fi

train_images="$(find "${REPO_DIR}/dataset/train" -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
train_captions="$(find "${REPO_DIR}/dataset/train" -maxdepth 1 -type f -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${train_images}" != "12" || "${train_captions}" != "12" ]]; then
  echo "Expected 12 training images and captions; found images=${train_images}, captions=${train_captions}." >&2
  exit 1
fi

nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
df -h "${MASAFY_STORAGE_PATH}"

"${AI_TOOLKIT_VENV}/bin/python" - "${CONFIG_PATH}" <<'PY'
import sys
from pathlib import Path
import yaml

path = Path(sys.argv[1])
data = yaml.safe_load(path.read_text(encoding="utf-8"))
process = data["config"]["process"][0]
assert process["model"]["arch"] == "minimax_h3"
assert process["model"]["model_kwargs"]["partition"] == "ref2va_pruned"
assert process["model"]["qtype"] == "convrot8"
assert process["model"]["qtype_te"] == "nvfp4"
assert process["datasets"][0]["num_frames"] == 1
assert process["network"]["linear"] == 16
print(f"config_ok={path}")
print(f"steps={process['train']['steps']}")
print(f"resolutions={process['datasets'][0]['resolution']}")
PY

if [[ -n "${MODELS_PATH:-}" ]]; then
  echo "models_path=${MODELS_PATH}"
elif [[ -d /workspace/ComfyUI/models ]]; then
  echo "models_path=/workspace/ComfyUI/models"
else
  echo "models_path=/workspace/models (missing files will be downloaded)"
fi

echo "Preflight passed."
