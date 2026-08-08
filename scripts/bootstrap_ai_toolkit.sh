#!/usr/bin/env bash
set -Eeuo pipefail

AI_TOOLKIT_DIR="${AI_TOOLKIT_DIR:-/workspace/ai-toolkit}"
AI_TOOLKIT_COMMIT="${AI_TOOLKIT_COMMIT:-f4e91305471a3727d52886ef6d410eb570cd484f}"
AI_TOOLKIT_VENV="${AI_TOOLKIT_VENV:-/workspace/ai-toolkit-venv}"

if [[ ! -d "${AI_TOOLKIT_DIR}/.git" ]]; then
  git clone --recursive https://github.com/ostris/ai-toolkit.git "${AI_TOOLKIT_DIR}"
fi

if [[ -n "$(git -C "${AI_TOOLKIT_DIR}" status --porcelain)" ]]; then
  echo "AI Toolkit has local changes; refusing to change commits." >&2
  exit 1
fi

git -C "${AI_TOOLKIT_DIR}" fetch --depth 1 origin "${AI_TOOLKIT_COMMIT}"
git -C "${AI_TOOLKIT_DIR}" checkout --detach "${AI_TOOLKIT_COMMIT}"
git -C "${AI_TOOLKIT_DIR}" submodule update --init --recursive

python3 -m venv "${AI_TOOLKIT_VENV}"
"${AI_TOOLKIT_VENV}/bin/python" -m pip install --upgrade pip setuptools wheel

if [[ ! -f "${AI_TOOLKIT_VENV}/.masafy-dependencies-complete" ]]; then
  "${AI_TOOLKIT_VENV}/bin/pip" install --no-cache-dir \
    torch==2.13.0 torchvision==0.28.0 torchaudio==2.11.0 \
    --index-url https://download.pytorch.org/whl/cu130
  "${AI_TOOLKIT_VENV}/bin/pip" install -r "${AI_TOOLKIT_DIR}/requirements.txt"
  touch "${AI_TOOLKIT_VENV}/.masafy-dependencies-complete"
fi

"${AI_TOOLKIT_VENV}/bin/python" - <<'PY'
import torch
print(f"torch={torch.__version__}")
print(f"cuda_available={torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"gpu={torch.cuda.get_device_name(0)}")
PY

echo "AI Toolkit is ready at ${AI_TOOLKIT_DIR}"
