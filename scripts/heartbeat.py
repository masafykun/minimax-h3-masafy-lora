#!/usr/bin/env python3
"""Write an atomic training heartbeat and emit one bounded log line per interval."""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


STEP_PATTERNS = (
    re.compile(r"(?:step|steps?)\s*[:=/]?\s*(\d+)(?:\s*/\s*(\d+))?", re.I),
    re.compile(r"\d+%\|[^\r\n]*?\|\s*(\d+)\s*/\s*(\d+)\s*\["),
)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def tail_text(path: Path, max_bytes: int = 128 * 1024) -> str:
    if not path.exists():
        return ""
    with path.open("rb") as handle:
        handle.seek(0, os.SEEK_END)
        size = handle.tell()
        handle.seek(max(0, size - max_bytes))
        return handle.read().decode("utf-8", errors="replace")


def parse_step(text: str) -> tuple[int | None, int | None]:
    for pattern in STEP_PATTERNS:
        matches = list(pattern.finditer(text))
        if matches:
            match = matches[-1]
            current = int(match.group(1))
            total = int(match.group(2)) if match.lastindex and match.lastindex >= 2 and match.group(2) else None
            return current, total
    return None, None


def configured_steps(path: Path) -> int | None:
    try:
        import yaml

        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        return int(data["config"]["process"][0]["train"]["steps"])
    except (ImportError, OSError, KeyError, TypeError, ValueError):
        return None


def gpu_snapshot() -> list[dict[str, object]]:
    command = [
        "nvidia-smi",
        "--query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
        "--format=csv,noheader,nounits",
    ]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return []
    rows = []
    for line in result.stdout.splitlines():
        values = [value.strip() for value in line.split(",")]
        if len(values) != 7:
            continue
        rows.append(
            {
                "index": int(values[0]),
                "name": values[1],
                "utilization_percent": float(values[2]),
                "memory_used_mib": float(values[3]),
                "memory_total_mib": float(values[4]),
                "temperature_c": float(values[5]),
                "power_w": float(values[6]),
            }
        )
    return rows


def write_atomic(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--status", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--interval", default=60, type=int)
    args = parser.parse_args()

    stopped = False

    def stop_handler(_signum: int, _frame: object) -> None:
        nonlocal stopped
        stopped = True

    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)

    started = time.monotonic()
    config_total_steps = configured_steps(args.config)
    while not stopped:
        alive = process_alive(args.pid)
        log_tail = tail_text(args.log)
        current_step, parsed_total_steps = parse_step(log_tail)
        total_steps = parsed_total_steps or config_total_steps
        nonempty_lines = [line.strip() for line in log_tail.splitlines() if line.strip()]
        payload: dict[str, object] = {
            "schema_version": 1,
            "updated_at": utc_now(),
            "state": "running" if alive else "process_exited",
            "training_pid": args.pid,
            "process_alive": alive,
            "elapsed_seconds": round(time.monotonic() - started, 1),
            "config": str(args.config),
            "current_step": current_step,
            "total_steps": total_steps,
            "last_log_line": nonempty_lines[-1][-500:] if nonempty_lines else "",
            "gpus": gpu_snapshot(),
        }
        write_atomic(args.status, payload)
        compact = {
            "updated_at": payload["updated_at"],
            "state": payload["state"],
            "step": current_step,
            "total": total_steps,
            "gpu": payload["gpus"],
        }
        print("MASAFY_HEARTBEAT " + json.dumps(compact, ensure_ascii=False), flush=True)
        if not alive:
            break
        time.sleep(max(10, args.interval))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
