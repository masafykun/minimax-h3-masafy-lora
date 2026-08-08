# MiniMax H3 MASAFY Character LoRA

MASAFY（マサフィー）の既存イラストから、MiniMax H3 `Ref2VA Pruned INT8 ConvRot` 用の
キャラクターLoRAを学習する再現可能な実験リポジトリです。

初回はRunPodのRTX 4090 24GBで静止画LoRAを100ステップだけ試し、VRAM、速度、
安定性を確認してから800ステップの本学習へ進みます。学習中はheartbeatとログを
永続領域へ保存し、RunPod MCPまたはCodex CloudからMacを停止した状態でも確認できる
構成にします。

## 重要な方針

- 学習画像、APIキー、SSH秘密鍵はGitHubへ保存しません。
- 学習成果は必ず `/workspace/masafy-h3-lora/output` へ保存します。
- 既存4090 Podの永続領域を使い、コンテナ再起動で消える場所へ成果を置きません。
- Codex Cloudからは既定で読み取り確認だけを行います。
- Podの開始、停止、再起動、削除はユーザーの明示承認なしに行いません。

## 現在のデータセット

`提出バージョン` には1000×1000の画像が16枚あります。完全重複はありません。

| 区分 | 枚数 | 用途 |
|---|---:|---|
| train | 12 | v1の外見学習 |
| validation | 2 | 未学習画像での評価 |
| excluded | 2 | 闇マサフィー系。通常外見と差が大きいためv1では除外 |

16枚は初回実験には利用できますが、強い汎化性能を狙う最終版では25～40枚程度へ
増やす余地があります。詳細は [docs/dataset-audit.md](docs/dataset-audit.md) を参照してください。

## ローカルでデータセットを準備

Pillowを入れます。

```bash
python3 -m venv .venv
./.venv/bin/pip install -r requirements-local.txt
```

元画像を変更せず、学習用PNGとキャプションを `dataset/` 以下へ生成します。

```bash
./.venv/bin/python scripts/prepare_dataset.py \
  --source "/Users/masatosuzuki/Downloads/提出バージョン" \
  --destination ./dataset
```

## RunPodへ転送

Podを起動してSSH接続情報を取得してから実行します。

```bash
RUNPOD_SSH_HOST=<PUBLIC_IP> \
RUNPOD_SSH_PORT=<SSH_PORT> \
RUNPOD_SSH_KEY="$HOME/.ssh/runpod_ed25519" \
./scripts/upload_to_runpod.sh
```

## RunPodで100ステップ試験

```bash
cd /workspace/masafy-h3-lora
./scripts/bootstrap_ai_toolkit.sh
./scripts/preflight.sh config/train_h3_masafy_smoke.yaml
./scripts/launch_detached.sh config/train_h3_masafy_smoke.yaml
```

状態確認:

```bash
./scripts/check_training.py
tail -n 100 logs/train-smoke.log
```

100ステップが正常終了したら本学習を開始します。

```bash
./scripts/launch_detached.sh config/train_h3_masafy_full.yaml
```

## Codex Cloud監視

[docs/codex-cloud-monitoring.md](docs/codex-cloud-monitoring.md) の手順でCloud環境を作ります。
RunPod MCPがCloudタスクでも利用できる場合は、APIキーをCloudコンテナへ渡す必要は
ありません。利用できない場合だけ、読み取り用REST確認スクリプトを使用します。

## 固定したモデル構成

- Architecture: `minimax_h3`
- Partition: `ref2va_pruned`
- DiT: `minimax_h3_ref2va_pruned_int8_convrot.safetensors`
- Text encoder: `qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`
- Video VAE: `minimax_h3_video_vae_fp16.safetensors`
- Audio VAE: `minimax_h3_audio_vae_fp32.safetensors`
- LoRA rank/alpha: 16/16
- AI Toolkit commit: `f4e91305471a3727d52886ef6d410eb570cd484f`

AI ToolkitのMiniMax H3対応は新しいため、設定は必ず100ステップ試験で確認してから
本学習へ進めます。
