# RunPod 無人実行セット（2026-08-11 実戦投入・完走実績あり）

RunPodで学習を「投げたら朝には終わって課金も止まっている」状態にするための3本。
2026-08-11のH3 LoRA本番800ステップは、この構成で**人の介在ゼロで完走**した。

## 構成

```
[ローカル/GPU機]                    [RunPod Pod]
 guardian.sh  ──監視──────────────▶  chain_full.sh
   │                                   ├ モデルDL(並行)
   │                                   ├ bootstrap
   │                                   ├ torch cu126 入れ替え
   │                                   ├ CUDA検証(NGなら中止)
   │                                   └ 学習 → chain.rc を書く
   ├ chain.rc を検知 ─────────────────┘
   ├ rsync で成果物回収
   └ DELETE /v1/pods/{id} で課金停止
```

**要点: 監視側をPodの外に置く。** Pod内に置くと、terminateで自分ごと消えて回収が終わらない。

## 1. chain_full.sh（Pod側・全工程の連結）

待ち時間をなくすため全工程を1本に繋ぐ。**節目ごとに人間の判断を挟むと、その待ち時間が全部課金される。**

先回りで潰してある罠:
- **CUDA不整合**: pip既定の torch は cu130 だが RunPod のドライバは 12.x。
  `torch==2.13.0+cu126` を明示指定で入れ直す。**ビルドタグまで書かないとpipは何もしない**
- **CUDA検証ガード**: `torch.cuda.is_available()` が False なら**学習を開始しない**。
  これが無いと「CPUで動き続けて課金だけ進む」状態になる
- **並行化**: モデルDL(GPU不使用)を bootstrap と並行実行
- **low_vram: false**: VRAMに余裕があるなら必ず切る。true だとシステムRAMへ退避してOOMする

最後に `chain.rc` を書く。**これが完了シグナル**。

## 2. guardian.sh（GPU機側・番人）

引数: `guardian.sh <POD_ID> <POD_IP> <POD_PORT>`

停止条件は3つ。どれか1つでも成立したら「回収 → terminate」へ進む。

| 条件 | 判定方法 |
|---|---|
| 正常完了 | **`chain.rc` ファイルの有無** |
| 時間切れ | 24時間経過 |
| 残高フロア | RunPod残高が $3 未満 |

**★ pgrepで完了判定してはいけない**
`ssh host "pgrep -f chain.sh"` は、**送り込んだコマンド文字列自身にマッチする**ため常に「実行中」を返す。
これで一度ウォッチャが機能せず、失敗後のPodを83分放置して$0.64溶かした。
`pgrep -f "[c]hain.sh"` と書くか、**ファイルの有無で判定する**（後者を採用）。
同じ理由で `pkill -f` は自分のシェルを殺す。

**★ 回収してから消す**
terminateはrsyncが終わってから。順序を逆にすると成果物ごと消える。

## 3. sample_ram.py（GPU種別のRAM実測）

**RunPodのシステムRAMは価格・VRAMと相関しない。** 料金ページの値はSECURE基準で、
COMMUNITYはホスト個体差でバラバラ。作って `memoryInGb` を読んで即消す、を繰り返して実測する。

安全策: 作成したIDは必ず `finally` で terminate。稼働中のPodは `PROTECTED` に入れて絶対に触らない。

実測例（2026-08-11）:
- RTX 3090 / COMMUNITY: **30GB, 41GB**（料金ページは125GBと表記）
- RTX 6000 Ada / SECURE: **188GB**（表記通り）
- A40 / SECURE: **50GB**（表記通り）
- H200 / SECURE: **233GB**（表記276GB）

## 再現手順

```bash
# 0) 認証: ~/.config/masafy-runpod/api-token (600) と ~/.ssh/runpod_masafy
# 1) RAMが足りるGPUを選ぶ（41GBのRTX4090などを掴まないこと）
python3 scripts/runpod-automation/sample_ram.py

# 2) Pod作成（gpuTypeIds は配列。在庫切れ対策に候補を優先順で並べる）
#    作成直後に memoryInGb を検証し、足りなければ即terminate

# 3) 転送 → チェーン起動
RUNPOD_SSH_HOST=... RUNPOD_SSH_PORT=... RUNPOD_SSH_KEY=... bash scripts/upload_to_runpod.sh
ssh pod "apt-get install -y rsync"        # Podにrsyncは入っていない
ssh pod "mkdir -p /workspace/logs && setsid nohup bash /workspace/chain_full.sh &"

# 4) 番人を起動（GPU機側で。setsidでPPID=1にする＝手元のPCを落としてもよい）
setsid nohup bash guardian.sh <POD_ID> <IP> <PORT> &

# 5) 保険: ホストが再起動しても番人が復帰するよう crontab に
#    @reboot sleep 60 && /path/guardian.sh <POD_ID> <IP> <PORT> &
```

## 落とし穴チェックリスト

- [ ] Podに `rsync` が無い → 先に `apt-get install`
- [ ] `/workspace` はネットワークFS → `rsync -a` の chown が失敗（exit 23）。中身は届くので無視可
- [ ] `gpuTypeIds` は配列 → 在庫切れ対策に候補を並べる
- [ ] 価格は GraphQL の `securePrice`/`communityPrice` を見る。
      `lowestPrice.uninterruptablePrice` は異常値が入っていることがある（H200 NVLで$0.50）
- [ ] **stop では課金が止まらない**（ストレージは停止中に単価が倍）。**terminate まで**やる
- [ ] 失敗時に自動で止める仕組みまで含めて初めて「自動化」
