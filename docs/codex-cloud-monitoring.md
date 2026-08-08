# Codex Cloud monitoring

## 目的

Macをシャットダウンした後も、Codex CloudからRunPod PodとMiniMax H3 LoRA学習の
生存状態を確認します。CloudコンテナはGPUホストでも永続ストレージでもありません。

Codex Cloud環境の仕様:
https://developers.openai.com/codex/environments/cloud-environment

## 監視対象

- 初回Pod ID: `wkiv0ouzkys4vo`
- GPU: NVIDIA GeForce RTX 4090
- リージョン: `EU-RO-1`
- 学習ログ: `/workspace/masafy-h3-lora/logs/`
- heartbeat: `/workspace/masafy-h3-lora/status/heartbeat.json`

Pod IDは秘密情報ではありませんが、Cloud環境では環境変数として設定します。

```text
RUNPOD_POD_ID=wkiv0ouzkys4vo
```

## 1. GitHubリポジトリをCodex Cloudへ接続

Codex SettingsからCloud environmentを作成し、この非公開リポジトリを選択します。
Cloudは指定ブランチをチェックアウトして監視スクリプトを実行します。

## 2. RunPod MCPを先に試す

Cloudタスクで次の読み取り専用プロンプトを実行します。

```text
RunPod MCPを使い、Pod wkiv0ouzkys4vo の状態と直近100行のログを確認してください。
開始・停止・再起動・削除は行わないでください。最新のMASAFY_HEARTBEAT、現在ステップ、
GPU使用率、エラー、時間単価を短く報告してください。
```

これが成功すればAPIキー設定は不要です。

## 3. MCPが使えない場合だけREST監視を設定

Cloud environmentのAgent internet accessで、次のドメインだけを許可します。

- `api.runpod.io`
- `rest.runpod.io`（v1フォールバック用）

読み取り監視だけならHTTPメソッドは `GET` と `HEAD` に限定します。

Cloud environmentのSecretへ `RUNPOD_API_KEY` を設定し、Setup scriptを次にします。

```bash
./scripts/cloud_setup.sh
```

Codex CloudではSecretがセットアップ終了後にエージェントから取り除かれるため、
セットアップスクリプトが所有者だけ読めるファイルへ保存します。RunPod APIキーが
広い権限を持つ場合は、REST方式よりRunPod MCPを優先してください。

確認コマンド:

```bash
python scripts/check_runpod.py --pod-id "$RUNPOD_POD_ID"
```

このスクリプトはPod状態の読み取りだけを行い、ライフサイクル操作は実装していません。

## 4. 定期確認

最初の100ステップ試験中は15分ごと、本学習中は30分ごとが目安です。

定期タスク用プロンプト:

```text
RunPod Pod wkiv0ouzkys4vo のMiniMax H3 MASAFY LoRA学習を読み取り専用で確認してください。
Pod状態、直近のMASAFY_HEARTBEAT、ステップ、heartbeatの鮮度、GPU使用率、OOM/例外、
推定経過時間と費用を報告してください。変化がないだけでは停止と断定しないでください。
開始・停止・再起動・削除は行わないでください。
```

## 5. Macを切る前の合格条件

- 100ステップ試験が実際に進行している。
- `MASAFY_HEARTBEAT` がRunPodログから読める。
- heartbeatの更新間隔が3分を超えていない。
- 50ステップのチェックポイントが永続領域に作成される。
- Codex CloudからPod状態とログを取得できる。
- 学習終了後にPodを停止する担当と方法を決めている。

## 自動停止について

このリポジトリには意図的に自動停止処理を実装していません。誤検知で学習を止めたり、
永続領域を失ったりするのを避けるためです。完了後の自動停止を追加する場合は、Podの
`stop` だけを対象にし、`terminate` や削除を使用しない設計を別途レビューします。
