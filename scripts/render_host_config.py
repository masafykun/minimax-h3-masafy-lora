#!/usr/bin/env python3
"""Render a host-local config without mutating the tracked base YAML."""

from __future__ import annotations

import argparse
import os
from pathlib import Path


RUNPOD_REPO = "/workspace/masafy-h3-lora"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--repo-dir", required=True, type=Path)
    args = parser.parse_args()

    source = args.source.resolve(strict=True)
    repo_dir = args.repo_dir.resolve(strict=True)
    output = args.output.resolve(strict=False)
    text = source.read_text(encoding="utf-8")
    if RUNPOD_REPO not in text:
        raise SystemExit(f"Expected path marker not found in {source}: {RUNPOD_REPO}")

    rendered = text.replace(RUNPOD_REPO, str(repo_dir))
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.write_text(rendered, encoding="utf-8")
    os.replace(temporary, output)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
