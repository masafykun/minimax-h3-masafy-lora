#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_ROOT="${MASAFY_HOST_ROOT:-$(cd "${REPO_DIR}/.." && pwd)}"
RUNTIME_DIR="${HOST_ROOT}/runtime"
PYTHON_BIN="${PYTHON_BIN:-/home/user/.local/bin/python3.12}"

export AI_TOOLKIT_DIR="${AI_TOOLKIT_DIR:-${HOST_ROOT}/ai-toolkit}"
export AI_TOOLKIT_VENV="${AI_TOOLKIT_VENV:-${HOST_ROOT}/venv}"
export MODELS_PATH="${MODELS_PATH:-${HOST_ROOT}/models}"
export HF_HOME="${HF_HOME:-${HOST_ROOT}/hf-cache}"
export MASAFY_STORAGE_PATH="${MASAFY_STORAGE_PATH:-${HOST_ROOT}}"
export PYTHON_BIN
export LAUNCHER_OUTPUT="file"

prepare_dirs() {
  mkdir -p "${RUNTIME_DIR}/config" "${MODELS_PATH}" "${HF_HOME}"
}

render_config() {
  local profile="$1"
  local source="${REPO_DIR}/config/train_h3_masafy_${profile}.yaml"
  local output="${RUNTIME_DIR}/config/train_h3_masafy_${profile}.yaml"
  "${PYTHON_BIN}" "${REPO_DIR}/scripts/render_host_config.py" \
    --source "${source}" \
    --output "${output}" \
    --repo-dir "${REPO_DIR}" >/dev/null
  printf '%s\n' "${output}"
}

assert_gpu_idle() {
  local processes
  processes="$(nvidia-smi --query-compute-apps=pid,process_name,used_memory \
    --format=csv,noheader 2>/dev/null || true)"
  if [[ -n "${processes}" ]]; then
    echo "Refusing to start training because another GPU compute process is active:" >&2
    echo "${processes}" >&2
    echo "Stop it separately after confirming its owner and purpose; this script will not stop it." >&2
    exit 2
  fi
}

usage() {
  cat <<'EOF'
Usage: ./scripts/local_gpu.sh COMMAND

Commands:
  bootstrap       Install the pinned AI Toolkit into the isolated host root.
  preflight       Validate the 100-step config without starting training.
  launch-smoke    Start the 100-step run only when the GPU has no compute process.
  launch-full     Start the 800-step run only when the GPU has no compute process.
  gpu-check       Report whether the GPU guard considers the device idle.
  status          Show the latest local training heartbeat.
  paths           Print the isolated paths used by this experiment.
EOF
}

command="${1:-}"
case "${command}" in
  bootstrap)
    prepare_dirs
    # Dependency installation should not initialize or reserve the shared GPU.
    export CUDA_VISIBLE_DEVICES=""
    exec "${REPO_DIR}/scripts/bootstrap_ai_toolkit.sh"
    ;;
  preflight)
    prepare_dirs
    config="$(render_config smoke)"
    exec "${REPO_DIR}/scripts/preflight.sh" "${config}"
    ;;
  launch-smoke)
    prepare_dirs
    assert_gpu_idle
    config="$(render_config smoke)"
    exec "${REPO_DIR}/scripts/launch_detached.sh" "${config}"
    ;;
  launch-full)
    prepare_dirs
    assert_gpu_idle
    config="$(render_config full)"
    exec "${REPO_DIR}/scripts/launch_detached.sh" "${config}"
    ;;
  gpu-check)
    assert_gpu_idle
    echo "gpu_idle=yes"
    ;;
  status)
    exec "${REPO_DIR}/scripts/check_training.py"
    ;;
  paths)
    printf 'host_root=%s\n' "${HOST_ROOT}"
    printf 'repo=%s\n' "${REPO_DIR}"
    printf 'ai_toolkit=%s\n' "${AI_TOOLKIT_DIR}"
    printf 'venv=%s\n' "${AI_TOOLKIT_VENV}"
    printf 'models=%s\n' "${MODELS_PATH}"
    printf 'hf_home=%s\n' "${HF_HOME}"
    printf 'runtime=%s\n' "${RUNTIME_DIR}"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
