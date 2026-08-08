#!/usr/bin/env python3
"""Download the pinned MiniMax H3 training weights without importing torch."""

from __future__ import annotations

import argparse
from pathlib import Path

from huggingface_hub import hf_hub_download


COMFY_REPO = "Comfy-Org/MiniMax-H3"
COMFY_FILES = (
    "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors",
    "text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors",
    "vae/minimax_h3_video_vae_fp16.safetensors",
    "vae/minimax_h3_audio_vae_fp32.safetensors",
)
ADAPTER_REPO = "ostris/minimax_h3_training_adapter"
ADAPTER_FILE = "minimax_h3_training_adapter_alpha.safetensors"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models-path", required=True, type=Path)
    args = parser.parse_args()
    models_path = args.models_path.resolve(strict=False)
    models_path.mkdir(parents=True, exist_ok=True)

    for filename in COMFY_FILES:
        path = hf_hub_download(
            repo_id=COMFY_REPO,
            filename=filename,
            local_dir=models_path,
        )
        size = Path(path).stat().st_size
        print(f"ready={path} bytes={size}", flush=True)

    adapter_dir = models_path / "loras" / "training_adapters"
    adapter_dir.mkdir(parents=True, exist_ok=True)
    adapter = hf_hub_download(
        repo_id=ADAPTER_REPO,
        filename=ADAPTER_FILE,
        local_dir=adapter_dir,
    )
    print(f"ready={adapter} bytes={Path(adapter).stat().st_size}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
