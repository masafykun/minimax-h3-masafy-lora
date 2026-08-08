#!/usr/bin/env python3
"""Summarize the latest heartbeat on the RunPod filesystem."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--status", default=REPO_ROOT / "status" / "heartbeat.json", type=Path)
    parser.add_argument("--stale-after", default=180, type=int)
    args = parser.parse_args()

    if not args.status.exists():
        print(f"No heartbeat found: {args.status}")
        return 2

    payload = json.loads(args.status.read_text(encoding="utf-8"))
    updated = datetime.fromisoformat(payload["updated_at"].replace("Z", "+00:00"))
    age = (datetime.now(timezone.utc) - updated).total_seconds()
    state = payload.get("state", "unknown")
    step = payload.get("current_step")
    total = payload.get("total_steps")

    print(f"state={state}")
    print(f"updated_at={payload['updated_at']}")
    print(f"heartbeat_age_seconds={age:.1f}")
    print(f"step={step}/{total}")
    print(f"process_alive={payload.get('process_alive')}")
    print(f"elapsed_seconds={payload.get('elapsed_seconds')}")
    for gpu in payload.get("gpus", []):
        print(
            "gpu="
            f"{gpu.get('index')} {gpu.get('name')} "
            f"util={gpu.get('utilization_percent')}% "
            f"vram={gpu.get('memory_used_mib')}/{gpu.get('memory_total_mib')}MiB "
            f"temp={gpu.get('temperature_c')}C"
        )
    print(f"last_log_line={payload.get('last_log_line', '')}")

    if state == "failed":
        return 1
    if state == "running" and age > args.stale_after:
        print("warning=heartbeat is stale")
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
