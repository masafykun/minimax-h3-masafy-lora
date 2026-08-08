#!/usr/bin/env python3
"""Read-only RunPod Pod status check for Codex Cloud."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_TOKEN_FILE = Path.home() / ".config" / "masafy-runpod" / "api-token"
DEFAULT_POD_ID = "wkiv0ouzkys4vo"


def read_token(token_file: Path) -> str:
    token = os.environ.get("RUNPOD_API_KEY", "").strip()
    if not token and token_file.exists():
        token = token_file.read_text(encoding="utf-8").strip()
    if not token:
        raise RuntimeError(
            "RunPod token is unavailable. Prefer the RunPod MCP; otherwise configure "
            "RUNPOD_API_KEY as a Codex Cloud setup secret."
        )
    return token


def get_json(url: str, token: str) -> dict[str, object]:
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def fetch_pod(pod_id: str, token: str) -> tuple[dict[str, object], str]:
    bases = []
    configured = os.environ.get("RUNPOD_API_BASE", "").strip().rstrip("/")
    if configured:
        bases.append(configured)
    bases.extend(["https://api.runpod.io/v2", "https://rest.runpod.io/v1"])

    errors = []
    for base in dict.fromkeys(bases):
        url = f"{base}/pods/{pod_id}?includeMachine=true&includeNetworkVolume=true"
        try:
            payload = get_json(url, token)
            return payload, base
        except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError) as error:
            errors.append(f"{base}: {type(error).__name__}")
    raise RuntimeError("Unable to query RunPod API (" + ", ".join(errors) + ")")


def parse_time(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pod-id", default=os.environ.get("RUNPOD_POD_ID", DEFAULT_POD_ID))
    parser.add_argument("--token-file", default=DEFAULT_TOKEN_FILE, type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    try:
        token = read_token(args.token_file)
        pod, api_base = fetch_pod(args.pod_id, token)
    except RuntimeError as error:
        print(f"error={error}", file=sys.stderr)
        return 2

    status = pod.get("status") or pod.get("desiredStatus") or "UNKNOWN"
    gpu = pod.get("gpu") if isinstance(pod.get("gpu"), dict) else {}
    runtime = pod.get("runtime") if isinstance(pod.get("runtime"), dict) else {}
    cost = pod.get("cost") or pod.get("adjustedCostPerHr") or pod.get("costPerHr")
    started_at = parse_time(pod.get("startedAt") or pod.get("lastStartedAt"))
    elapsed_hours = None
    estimated_cost = None
    if started_at and str(status).upper() == "RUNNING":
        elapsed_hours = (datetime.now(timezone.utc) - started_at).total_seconds() / 3600
        try:
            estimated_cost = elapsed_hours * float(cost)
        except (TypeError, ValueError):
            pass

    summary = {
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "api_base": api_base,
        "pod_id": pod.get("id", args.pod_id),
        "name": pod.get("name"),
        "status": status,
        "cloud": pod.get("cloud"),
        "data_center": pod.get("dataCenterId") or (pod.get("machine") or {}).get("dataCenterId"),
        "gpu": gpu.get("id") or gpu.get("displayName"),
        "gpu_count": gpu.get("count"),
        "hourly_cost_usd": cost,
        "started_at": started_at.isoformat() if started_at else None,
        "elapsed_hours": round(elapsed_hours, 3) if elapsed_hours is not None else None,
        "estimated_session_cost_usd": round(estimated_cost, 3) if estimated_cost is not None else None,
        "runtime": runtime,
    }

    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        for key, value in summary.items():
            if key != "runtime":
                print(f"{key}={value}")

    return 0 if str(status).upper() == "RUNNING" else 1


if __name__ == "__main__":
    raise SystemExit(main())
