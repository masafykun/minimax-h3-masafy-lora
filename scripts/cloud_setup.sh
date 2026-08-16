#!/usr/bin/env bash
set -Eeuo pipefail

# Some CI and hosted environments expose secrets only while the setup script
# runs. Persist the optional RunPod token with owner-only permissions so that
# later steps can still read it.

token_dir="${RUNPOD_TOKEN_DIR:-${CODEX_RUNPOD_TOKEN_DIR:-${HOME}/.config/masafy-runpod}}"
token_file="${token_dir}/api-token"

if [[ -n "${RUNPOD_API_KEY:-}" ]]; then
  umask 077
  mkdir -p "${token_dir}"
  printf '%s' "${RUNPOD_API_KEY}" > "${token_file}"
  chmod 600 "${token_file}"
  echo "RunPod monitor credential configured."
else
  echo "RUNPOD_API_KEY was not provided; skipping credential setup."
fi

python3 -m compileall -q scripts
