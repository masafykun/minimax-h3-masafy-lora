#!/usr/bin/env bash
# RTX 3090 上で「モデルDL → 環境構築 → CUDA修正 → 検証 → 本番800step」を連結する。
# H200での知見を全部先回りで適用済み。
set -uo pipefail

REPO=/workspace/masafy-h3-lora
VENV=/workspace/ai-toolkit-venv
STATE=/workspace/logs/chain.state
mkdir -p /workspace/logs

ts() { date -u +%FT%TZ; }
mark() { echo "[$(ts)] $*" | tee -a "$STATE"; }

mark "=== チェーン開始 (RTX 3090 / 本番800step) ==="
t0=$(date +%s)

# 1) モデルDL（GPUを使わないのでbootstrapと並行）
mark "モデルDL開始"
dl_start=$(date +%s)
pip install -q huggingface_hub > /dev/null 2>&1
(
  python3 "$REPO/scripts/download_h3_models.py" --models-path /workspace/models \
    > /workspace/logs/download.log 2>&1
  echo "$?" > /workspace/logs/download.rc
) &
DL_PID=$!

# 2) ai-toolkit 構築
mark "bootstrap開始"
bs=$(date +%s)
bash "$REPO/scripts/bootstrap_ai_toolkit.sh" > /workspace/logs/bootstrap.log 2>&1
rc=$?
mark "bootstrap完了 rc=$rc ($(( $(date +%s) - bs ))秒)"
[ "$rc" -eq 0 ] || { mark "NG: bootstrap失敗"; exit 1; }

# 3) CUDA不整合を先回りで修正（pip既定はcu130、ドライバは12.x）
mark "torch cu126 へ入れ替え"
tw=$(date +%s)
"$VENV/bin/pip" install --no-cache-dir \
  torch==2.13.0+cu126 torchvision==0.28.0+cu126 torchaudio==2.11.0+cu126 \
  --index-url https://download.pytorch.org/whl/cu126 > /workspace/logs/torch_cu126.log 2>&1
mark "torch入れ替え完了 ($(( $(date +%s) - tw ))秒)"

# 4) CUDA検証（Falseなら学習しない）
verdict=$("$VENV/bin/python" -c "import torch;print(torch.__version__,torch.version.cuda,torch.cuda.is_available())" 2>/dev/null | tail -1)
mark "torch判定: $verdict"
case "$verdict" in
  *True*) mark "CUDA利用可" ;;
  *)      mark "NG: CUDA不可のため中止"; exit 1 ;;
esac

# 5) モデルDL完了待ち
wait "$DL_PID"
mark "モデルDL完了 ($(( $(date +%s) - dl_start ))秒) rc=$(cat /workspace/logs/download.rc 2>/dev/null)"

# 6) 本番config（low_vram無効化。VRAM 24GBに対し実測4GBなので不要）
cd "$REPO/config" || exit 1
sed 's/low_vram: true/low_vram: false/' train_h3_masafy_full.yaml > train_h3_masafy_full_3090.yaml
mark "config用意: full 800step / low_vram=false / resolution [512,768]"

# 7) 本番学習
# --- RAMピーク計測を開始（RAM不足で3回死んだ反省。実測値は記事の核）---
setsid nohup bash "$REPO/scripts/runpod-automation/ram_watch.sh" /workspace/logs/ram_peak.txt 20 \
  > /dev/null 2>&1 < /dev/null &
RAMW_PID=$!
mark "RAM監視開始 pid=$RAMW_PID"

mark "=== 本番学習開始 (800 steps) ==="
tr=$(date +%s)
cd "$REPO" || exit 1
export MODELS_PATH=/workspace/models
export HF_HOME=/workspace/huggingface-cache
bash scripts/run_training.sh "$REPO/config/train_h3_masafy_full_3090.yaml" \
  > /workspace/logs/full_3090.log 2>&1
rc=$?
mark "=== 本番学習終了 rc=$rc ($(( $(date +%s) - tr ))秒) ==="
kill "$RAMW_PID" 2>/dev/null
mark "★RAMピーク実測: $(cat /workspace/logs/ram_peak.txt.latest 2>/dev/null || echo 取得失敗)"
mark "総所要 $(( $(date +%s) - t0 ))秒"
echo "$rc" > /workspace/logs/chain.rc
exit "$rc"
