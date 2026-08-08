# Codex instructions for this repository

## Scope

This repository controls a MiniMax H3 character-LoRA experiment on RunPod.
Codex Cloud is a monitor and repository assistant; it is not the GPU host and
must not treat its container as persistent compute or storage.

## Safety

- Never print, commit, upload, or copy API keys, SSH private keys, tokens, or credentials.
- Never add files under `dataset/train`, `dataset/validation`, or `dataset/excluded` to Git.
- Never start, stop, restart, reset, terminate, or delete a RunPod Pod without explicit user authorization in the current request.
- Read-only Pod status and bounded log checks are allowed.
- Do not publish checkpoints, datasets, model cards, or findings without explicit approval.
- Preserve all outputs under `/workspace/masafy-h3-lora/output` until the user confirms a backup.

## Monitoring procedure

When asked to check training:

1. Use the RunPod MCP `get_pod` or `list_pods` tool if available.
2. Use `stream_pod_logs` with a bounded tail to inspect recent progress.
3. Report Pod status, GPU, hourly cost, last visible training step, most recent heartbeat, errors, and whether progress appears stale.
4. If MCP is unavailable, run `python scripts/check_runpod.py --pod-id "$RUNPOD_POD_ID"`.
5. Never expose the API token or full environment contents.

The initial Pod ID is documented as a non-secret default in
`docs/codex-cloud-monitoring.md`, but prefer the `RUNPOD_POD_ID` environment variable.
