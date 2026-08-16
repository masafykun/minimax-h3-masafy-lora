#!/usr/bin/env python3
"""COMMUNITY/SECURE のRAM割当を実測する。作ってすぐ消すので費用は数円。

安全策: 作成したPodのIDは必ず finally で terminate する。
本番学習中のPod (ecevlzwh5m6ug5) には一切触れない。
"""
import json, os, sys, time, urllib.request, urllib.error

TOKEN = open(os.path.expanduser("~/.config/masafy-runpod/api-token")).read().strip()
PUBKEY = open(os.path.expanduser("~/.ssh/runpod_masafy.pub")).read().strip()
PROTECTED = {"ecevlzwh5m6ug5"}          # 本番学習中。絶対に消さない
BASE = "https://rest.runpod.io/v1"


def api(method, path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"},
        method=method,
    )
    try:
        r = urllib.request.urlopen(req, timeout=120)
        raw = r.read().decode()
        return r.status, (json.loads(raw) if raw.strip() else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:160]


def create(cloud, gpu):
    return api("POST", "/pods", {
        "name": f"ramprobe-{gpu.split()[-1]}-{cloud[:3]}".lower(),
        "cloudType": cloud, "computeType": "GPU",
        "imageName": "runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04",
        "gpuTypeIds": [gpu], "gpuCount": 1,
        "containerDiskInGb": 10, "volumeInGb": 0,
        "ports": ["22/tcp"], "env": {"PUBLIC_KEY": PUBKEY},
    })


def probe(cloud, gpu, n):
    out = []
    for i in range(n):
        pid = None
        try:
            code, res = create(cloud, gpu)
            if code not in (200, 201):
                out.append((None, None, None, f"作成失敗 HTTP{code}"))
                break
            pid = res.get("id")
            if pid in PROTECTED:
                raise RuntimeError("保護対象IDと衝突。中止")
            ram = res.get("memoryInGb")
            vcpu = res.get("vcpuCount")
            cost = res.get("costPerHr")
            mid = (res.get("machine") or {}).get("machineId") or res.get("machineId")
            out.append((ram, vcpu, cost, f"machine={str(mid)[:10]}"))
        finally:
            if pid and pid not in PROTECTED:
                c, _ = api("DELETE", f"/pods/{pid}")
                if c != 204:
                    print(f"  !! terminate失敗 {pid} HTTP{c} — 手動確認が必要", flush=True)
        time.sleep(2)
    return out


targets = [
    ("COMMUNITY", "NVIDIA GeForce RTX 3090", 4),
    ("SECURE",    "NVIDIA GeForce RTX 3090", 1),
    ("COMMUNITY", "NVIDIA RTX A6000", 2),
]

for cloud, gpu, n in targets:
    print(f"\n=== {gpu} / {cloud} を{n}回サンプリング ===", flush=True)
    for i, (ram, vcpu, cost, note) in enumerate(probe(cloud, gpu, n), 1):
        if ram is None:
            print(f"  #{i}: {note}", flush=True)
        else:
            print(f"  #{i}: RAM={ram}GB  vCPU={vcpu}  ${cost}/h  {note}", flush=True)

# 後片付けの検証
code, res = api("GET", "/pods")
pods = res if isinstance(res, list) else res.get("data", [])
print("\n=== 後片付け確認 ===")
print(f"残Pod数: {len(pods)}")
for p in pods:
    print(f"  - {p.get('id')} {p.get('name')} {p.get('desiredStatus')}")
