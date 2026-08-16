#!/usr/bin/env bash
# GPU機側で動く番人。Pod上の本番学習を見守り、終わったら回収してterminateする。
# 判定はファイルの有無で行う（pgrepの自己マッチ事故を構造的に排除）。
set -uo pipefail

POD_ID="$1"
POD_IP="$2"
POD_PORT="$3"

KEY="$HOME/.ssh/runpod_masafy"
TOKEN=$(cat "$HOME/.config/masafy-runpod/api-token")
DEST=/mnt/data/masafy-h3-lora/harvest_full
STATE=/mnt/data/masafy-h3-lora/guardian.state
SSHOPT="-i $KEY -p $POD_PORT -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -o ServerAliveInterval=30"

HARD_LIMIT=$((24*3600))   # ③ 24時間
BALANCE_FLOOR=3.0         # ④ 残高フロア

ts() { date -u +%FT%TZ; }
mark() { echo "[$(ts)] $*" | tee -a "$STATE"; }

mkdir -p "$DEST"
: > "$STATE"
mark "=== 番人 起動 pod=$POD_ID ==="
t0=$(date +%s)
reason=""

while :; do
  el=$(( $(date +%s) - t0 ))

  # ① 完了検知（chain.rc の出現で判定）
  if ssh $SSHOPT root@"$POD_IP" "test -f /workspace/logs/chain.rc" 2>/dev/null; then
    rc=$(ssh $SSHOPT root@"$POD_IP" "cat /workspace/logs/chain.rc" 2>/dev/null)
    reason="正常完了 rc=$rc"; break
  fi

  # ③ 時間切れ
  if [ "$el" -ge "$HARD_LIMIT" ]; then
    reason="24時間の上限に到達"; break
  fi

  # ④ 残高フロア（10分ごと）
  if [ $(( el % 600 )) -lt 60 ]; then
    bal=$(curl -s -X POST "https://api.runpod.io/graphql?api_key=${TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"query":"query { myself { clientBalance } }"}' \
      | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["data"]["myself"]["clientBalance"])
except Exception: print("")' 2>/dev/null)
    if [ -n "$bal" ]; then
      low=$(python3 -c "print(1 if float('$bal') < $BALANCE_FLOOR else 0)" 2>/dev/null)
      if [ "$low" = "1" ]; then reason="残高が\$${BALANCE_FLOOR}を下回った (\$$bal)"; break; fi
    fi
  fi

  # 生存ログ（30分ごと）
  if [ $(( el % 1800 )) -lt 60 ]; then
    prog=$(ssh $SSHOPT root@"$POD_IP" "tail -1 /workspace/masafy-h3-lora/logs/train_h3_masafy_full_3090.log 2>/dev/null | grep -oE '[0-9]+/800 \[[^]]*' | tail -1" 2>/dev/null)
    mark "経過$(( el/60 ))分 進捗: ${prog:-（ロード中/未取得）}"
  fi

  sleep 60
done

mark "停止理由: $reason"

# --- 回収 ---
mark "成果物を回収 -> $DEST"
rsync -az -e "ssh $SSHOPT" root@"$POD_IP":/workspace/masafy-h3-lora/output/ "$DEST/output/" 2>>"$STATE"
rsync -az -e "ssh $SSHOPT" root@"$POD_IP":/workspace/logs/ "$DEST/logs/" 2>>"$STATE"
rsync -az -e "ssh $SSHOPT" root@"$POD_IP":/workspace/masafy-h3-lora/logs/ "$DEST/train_logs/" 2>>"$STATE"

n=$(find "$DEST/output" -name "*.safetensors" 2>/dev/null | wc -l)
mark "回収したsafetensors: ${n}個 / $(du -sh "$DEST" 2>/dev/null | cut -f1)"
find "$DEST/output" -name "*.safetensors" 2>/dev/null | tee -a "$STATE"

# --- terminate ---
code=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  -H "Authorization: Bearer $TOKEN" "https://rest.runpod.io/v1/pods/${POD_ID}")
mark "terminate HTTP=$code"

sleep 5
remaining=$(curl -s -H "Authorization: Bearer $TOKEN" https://rest.runpod.io/v1/pods \
  | python3 -c 'import json,sys
d=json.load(sys.stdin); p=d if isinstance(d,list) else d.get("data",[])
print(len(p))' 2>/dev/null)
bal=$(curl -s -X POST "https://api.runpod.io/graphql?api_key=${TOKEN}" \
  -H "Content-Type: application/json" -d '{"query":"query { myself { clientBalance } }"}' \
  | python3 -c 'import json,sys
print(round(json.load(sys.stdin)["data"]["myself"]["clientBalance"],2))' 2>/dev/null)
mark "残Pod=$remaining / 残高=\$$bal"
mark "=== 番人 終了 ==="
