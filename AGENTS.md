# Codex instructions for this repository

## Scope

This repository controls a MiniMax H3 character-LoRA experiment on RunPod.
Codex Cloud is a monitor and repository assistant; it is not the GPU host and
must not treat its container as persistent compute or storage.

## Safety

- Never print, commit, upload, or copy API keys, SSH private keys, tokens, or credentials.
- Never start, stop, restart, reset, terminate, or delete a RunPod Pod without explicit user authorization in the current request.
- Read-only Pod status and bounded log checks are allowed.
- Preserve all outputs under `/workspace/masafy-h3-lora/output` until the user confirms a backup.

### Publication status (updated 2026-08-15)

The dataset restriction that previously appeared here has been lifted by the
author. The current state of this repository is:

- **`dataset/` is published.** The 12 training images, 2 validation images,
  2 excluded images and their captions are committed here on purpose, so that
  the experiment can be reproduced. Do not remove them.
- **Model weights are not stored in Git.** The LoRA adapter and its
  checkpoints live on Hugging Face; see `lora/README.md` for the location.
  `.gitignore` excludes `*.safetensors` accordingly.
- **The findings are published** as a technical report under `paper/`
  (Japanese and English, LaTeX source plus PDF) together with the measured
  data under `logs/`.

Publishing anything *further* — new datasets, new weights, or results from a
different subject — still requires explicit approval in the current request.
The lifted restriction applies to this experiment only.

## Monitoring procedure

When asked to check training:

1. Use the RunPod MCP `get_pod` or `list_pods` tool if available.
2. Use `stream_pod_logs` with a bounded tail to inspect recent progress.
3. Report Pod status, GPU, hourly cost, last visible training step, most recent heartbeat, errors, and whether progress appears stale.
4. If MCP is unavailable, run `python scripts/check_runpod.py --pod-id "$RUNPOD_POD_ID"`.
5. Never expose the API token or full environment contents.

The initial Pod ID is documented as a non-secret default in
`docs/codex-cloud-monitoring.md`, but prefer the `RUNPOD_POD_ID` environment variable.
