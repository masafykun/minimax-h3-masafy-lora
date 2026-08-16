#!/usr/bin/env bash
# システムRAMのピークを記録する。学習と並行して動かす。
#
# 2026-08-11のH3 LoRA学習でRAM不足に3回やられたのに、ピーク実測値を
# 記録し損ねた反省から追加。cgroupのパスは環境で違うので複数経路を試す。
#
# 出力: /workspace/logs/ram_peak.txt  （最終行に "PEAK_GB=..." を書く）
set -uo pipefail

OUT="${1:-/workspace/logs/ram_peak.txt}"
INTERVAL="${2:-20}"

# 現在のRAM使用量(バイト)を返す。取得できなければ空。
current_bytes() {
  # cgroup v2
  if [ -r /sys/fs/cgroup/memory.current ]; then
    cat /sys/fs/cgroup/memory.current 2>/dev/null && return
  fi
  # cgroup v1
  if [ -r /sys/fs/cgroup/memory/memory.usage_in_bytes ]; then
    cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null && return
  fi
  # 最終手段: 全プロセスのRSS合計（コンテナ外の値を拾う可能性はある）
  ps -eo rss --no-headers 2>/dev/null | awk '{s+=$1} END {if(s>0) print s*1024}'
}

# カーネルが持っているピーク値（あればこれが最も正確）
kernel_peak_bytes() {
  [ -r /sys/fs/cgroup/memory.peak ] && cat /sys/fs/cgroup/memory.peak 2>/dev/null && return
  [ -r /sys/fs/cgroup/memory/memory.max_usage_in_bytes ] && \
    cat /sys/fs/cgroup/memory/memory.max_usage_in_bytes 2>/dev/null && return
}

limit_bytes() {
  [ -r /sys/fs/cgroup/memory.max ] && cat /sys/fs/cgroup/memory.max 2>/dev/null && return
  [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ] && \
    cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null && return
}

gb() { awk -v b="$1" 'BEGIN{ if(b=="" || b=="max"){print "?"} else {printf "%.1f", b/1073741824} }'; }

: > "$OUT"
{
  echo "# RAM監視開始 $(date -u +%FT%TZ)"
  echo "# 上限: $(gb "$(limit_bytes)") GB"
} >> "$OUT"

peak=0
while :; do
  cur=$(current_bytes)
  if [ -n "${cur:-}" ] && [ "$cur" -gt "$peak" ] 2>/dev/null; then
    peak=$cur
    echo "$(date -u +%H:%M:%S) 更新 $(gb "$peak") GB" >> "$OUT"
  fi

  # カーネル側のピークが取れるならそれも反映（サンプリングの取りこぼしを補正）
  kp=$(kernel_peak_bytes)
  if [ -n "${kp:-}" ] && [ "$kp" -gt "$peak" ] 2>/dev/null; then
    peak=$kp
    echo "$(date -u +%H:%M:%S) kernel峰 $(gb "$peak") GB" >> "$OUT"
  fi

  echo "PEAK_GB=$(gb "$peak")" > "${OUT}.latest"
  sleep "$INTERVAL"
done
