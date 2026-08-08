#!/usr/bin/env bash
set -Eeuo pipefail

# Codex Cloud secrets exist during the setup script but are removed before the
# agent phase. Persist the optional RunPod token with owner-only permissions.
# Prefer the account-level RunPod MCP whenever it is available.

token_dir="${CODEX_RUNPOD_TOKEN_DIR:-${HOME}/.config/masafy-runpod}"
token_file="${token_dir}/api-token"

if [[ -n "${RUNPOD_API_KEY:-}" ]]; then
  umask 077
  mkdir -p "${token_dir}"
  printf '%s' "${RUNPOD_API_KEY}" > "${token_file}"
  chmod 600 "${token_file}"
  echo "RunPod read-only monitor credential configured."
else
  echo "RUNPOD_API_KEY was not provided. Codex Cloud must use the RunPod MCP."
fi

python3 -m compileall -q scripts
