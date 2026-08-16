# Qiita記事用ネタ帳: MiniMax H3のキャラLoRAをRunPodで学習する

このファイルは**記事の素材置き場**。作業しながら随時追記する。
数値・エラー全文・所要時間・費用は「あとで思い出せない」ので、その場で必ずここへ。

- 対象: MiniMax H3（33Bのオムニモーダル動画生成モデル）のキャラクターLoRA
- 環境: ローカル= RTX 3060 12GB / クラウド= RunPod
- リポジトリ: `/mnt/data/masafy-h3-lora/`（GPU機）

---

## 記事の骨子（案）

想定タイトル: 「33Bの動画生成モデルのLoRAを12GBのGPUで学習しようとして敗れ、RunPodへ逃げた話」

刺さりそうなポイントは3つ。

1. **「ローカルでもできる」と言われて実際にやったら0ステップだった**という実測
2. **RunPodはPodを停止しても課金が止まらない**という、金額つきの実害
3. 33Bクラスの動画モデルLoRAに実際いくらかかるのか（本記事の本題）

---

## 1章: ローカル（RTX 3060 12GB）で敗北した記録

### 何を試したか

| 項目 | 値 |
|---|---|
| モデル | MiniMax H3 Ref2VA **枝刈りINT8 ConvRot** 版 |
| transformer単体のサイズ | **20.9GB**（`minimax_h3_ref2va_pruned_int8_convrot.safetensors`） |
| モデル一式 | 約40GB（diffusion 20GB + text_encoders 15GB + vae 5.5GB） |
| 学習ツール | ostris/ai-toolkit |
| 設定 | LoRA rank 16 / alpha 16, 解像度512, `num_frames: 1`（静止画）, `low_vram: true` |
| データセット | train 12枚 / validation 2枚 / excluded 2枚（計16枚, 1000x1000） |
| 目標 | まず10ステップのスモークテスト |

### 結果

- 2026-08-08 20:52 UTC 開始 → 23:15 UTC まで **約2時間25分**
- ハートビートは終始 `"step": null` = **1ステップも進まず**
- GPU使用率は全サンプルで **0.0%**
- ログの最終到達点は `Quantizing transformer` → `quantizing extras`
- 出力された `.safetensors` は **ゼロ**

### なぜ動かなかったのか

- VRAM 12GB に対して transformer 単体が 20.9GB → そもそも載らない
- `low_vram: true` でCPUオフロードしたが、**モデル一式40GB > システムRAM 30GB**
- 結果、ディスクスワップまで落ちてGPUに仕事が回らない
- → **GPU使用率0%は「GPUが遊んでいる」のではなく「GPUに渡す前で詰まっている」サイン**

> 記事で強調したい教訓: 「low_vramオプションがある＝動く」ではない。
> VRAMだけでなく**システムRAMがモデル全体を抱えられるか**を先に確認すべきだった。

### 補足: 12GBで「できること」との線引き

| 対象 | 可否 |
|---|---|
| H3(33B)のLoRA学習 | ✗（本件） |
| H3での**推論**（動画生成） | ○ 864x480・5秒で約13分の実績あり |
| FLUX系の画像LoRA | ○ 一般的に実績のある領域 |

---

## 2章: RunPodの課金の罠（実害つき）

### 何が起きたか

8/8に検証用のPodを4つ作り、**stop（EXITED）したまま放置**していた。
8/11に確認したところ、以下が残っていた。

| Pod | Volume | Container | 計 |
|---|---:|---:|---:|
| masafy-h3-lora-smoke-4090-secure | 100GB | 60GB | 160GB |
| minimax-h3-ref2va-int8-compare | 100GB | 60GB | 160GB |
| minimax-h3-ref2va-int8-a6000-ephemeral | 0 | 100GB | 100GB |
| minimax-h3-ref2va（$13.16/h のPod） | 0 | 100GB | 100GB |
| ネットワークボリューム（AP-JP-1） | | | **250GB** |

### 金額

- Podディスク 520GB x **$0.20/GB/月**（停止中レート）= **$104.00/月**
- ネットワークボリューム 250GB x $0.07/GB/月 = **$17.50/月**
- **合計 約$121/月（約¥18,000/月、1日あたり約¥600）**

### 一番の落とし穴

**停止中のストレージ単価は稼働中の「倍」**。

- 稼働中: $0.10/GB/月
- **停止中: $0.20/GB/月**

「使わないから止めておこう」が、単価を倍にして課金し続ける動作だった。
GPU課金は確かに止まるので、**請求書を見るまで気づきにくい**。

> 記事で強調したい教訓: RunPodは **stop ≠ 課金停止**。終わったら **terminate** まで到達する。
> そして「停止中は単価が倍」は直感に反するので、これは声を大にして書く。

### 検出に使ったAPI（読み取り専用なので安全）

```bash
TOKEN=$(cat ~/.config/masafy-runpod/api-token)
curl -s -H "Authorization: Bearer $TOKEN" https://rest.runpod.io/v1/pods
curl -s -H "Authorization: Bearer $TOKEN" https://rest.runpod.io/v1/networkvolumes
```

削除は `DELETE /v1/pods/{id}` と `DELETE /v1/networkvolumes/{id}`（どちらも成功時 HTTP 204）。

### ハマりどころ: 存在しないエンドポイント

GPU一覧を取ろうとして `/v1/gputypes`, `/v1/gpus`, `/v1/gputypes/available` を試したが**全部HTTP 400**。
エラーメッセージが「そのパスは仕様に存在しない」と明示してくれるので、そこは親切。

---

## 3章: RunPodでの本番（ここから追記していく）

### 構成

| 項目 | 値 |
|---|---|
| GPU | RTX 4090 24GB |
| イメージ | `runpod/pytorch:2.8.0-py3.11-cuda12.8.1-cudnn-devel-ubuntu22.04` |
| ai-toolkit | commit `f4e9130` にピン留め |
| 学習 | smoke 10step → full 800step |

### 記録すべき項目（埋めていく）

- [ ] Pod作成〜SSH疎通までの所要時間
- [ ] モデル40GBのDL所要時間（**課金されている時間**なのでシビアに）
- [ ] smoke 10step: VRAM実測ピーク / 1ステップあたり秒数
- [ ] full 800step: 総時間と総額
- [ ] 失敗・リトライがあればエラー全文
- [ ] 出来上がったLoRAの品質（R2V単体との比較）
- [ ] **最終的な合計金額**（記事の一番の関心事）

---

## 執筆時の注意

- APIキー・SSH秘密鍵・トークンは記事に載せない（マスクする）
- データセットの画像そのものは公開しない
- 公開前にPII確認（漢字氏名NG、ローマ字表記はOK）

---

## 4章: 実際に借りたPodと課金の内訳（2026-08-11）

### GPUガチャの結果: 4090が取れずA40が当たった

`POST /v1/pods` に `gpuTypeIds: ["NVIDIA GeForce RTX 4090"]` 単体を指定 → **HTTP 500 `There are no instances currently available`**。

対策: **gpuTypeIds は配列なので候補を優先順に並べられる**。

```json
"gpuTypeIds": ["NVIDIA GeForce RTX 4090","NVIDIA GeForce RTX 5090","NVIDIA L40S","NVIDIA RTX A6000","NVIDIA A40"]
```

これで A40 が確保できた（HTTP 201）。**在庫切れ対策として候補を並べるのは実用的なテクニック**。

### 4090 vs A40（今回の選択の是非）

| | RTX 4090 | **A40（今回）** |
|---|---:|---:|
| RunPod単価(SECURE) | $0.74/h | **$0.44/h** |
| VRAM | 24GB | **48GB** |
| FP32 | 約82 TFLOPS | 約37 TFLOPS |
| メモリ帯域 | 約1,008 GB/s | 約696 GB/s |

演算力は4090が約2倍。**しかし transformer 単体が20.9GBあるため、24GBだと残り3GBしかなくオフロード必須**＝ローカルで0ステップに終わった構図の再現になる。
48GBなら素直に載る。**「速いが載らない」より「遅いが確実に載る」、しかも4割安い**。

> 記事のネタ: GPU選びは TFLOPS ではなく **「モデルが載るか」** で決まる場面がある。

### 課金の内訳（GPUを借りると何にお金がかかるか）

| 項目 | 課金 |
|---|---|
| GPU | $0.44/h |
| **vCPU (9コア) / RAM (50GB)** | **GPU料金に込み。別課金なし** |
| ストレージ（container 60GB + volume 100GB = 160GB） | $0.10/GB/月（稼働中）≒ **$0.022/h** |
| データ転送（ingress/egress） | **無料** |

→ 実際の燃焼レートは **約 $0.46/h**。40GBのモデルDLに転送課金はかからない。
（停止するとストレージだけ$0.20/GB/月＝**倍**になる。2章参照）

### ハマりどころ: コンテナ内の `free` は嘘をつく

```
$ free -g          → Mem: 503   ← ホスト機全体の物理RAM
$ cat /sys/fs/cgroup/memory.max → 49999998976 (= 50GB)  ← 実際の割当
$ nproc            → 96          ← ホストのコア数
$ (APIのvcpuCount) → 9           ← 実際の割当
```

**`free` も `nproc` もホスト機の値を見せてしまう。** 実際の割当を知りたいなら cgroup を見るか、
RunPod APIの `memoryInGb` / `vcpuCount` を見る。危うく「RAM 503GBもある！」と誤認するところだった。

> 記事のネタ: これはRunPod固有ではなくコンテナ全般の話なので、汎用的に刺さるはず。

### 環境構築でのつまずき

1. **Podに `rsync` が入っていない** → `upload_to_runpod.sh` が `rsync: command not found` で失敗。
   `apt-get install -y rsync` を先に打つ必要がある。
2. **`/workspace` がネットワークFS（mfs）なので chown できない**
   → `rsync -a` が `chown ... Operation not permitted` を出して exit code 23。
   ファイル自体は転送されているので実害なし。気になるなら `-a` から `-o -g` を外す。
3. `HF_HUB_ENABLE_HF_TRANSFER` は**非推奨になっていた**（`HF_XET_HIGH_PERFORMANCE` へ移行）。

### 所要時間の実測

| 工程 | 時間 |
|---|---|
| Pod作成 → SSH疎通 | 約1分 |
| **H3モデル 40GB のDL** | **約3分**（転送無料・回線が非常に速い） |
| ai-toolkit 構築 | 計測中 |

---

## 5章: ついに成功。そして「VRAMは要らなかった」という結論（2026-08-11）

### 成功構成: RunPod H200 SXM

| 項目 | 値 |
|---|---|
| GPU | NVIDIA H200 SXM（VRAM 141GB） |
| **システムRAM** | **233GB**（cgroup実測） |
| vCPU | 24 |
| 単価 | $4.59/h（SECURE） |
| 結果 | **state=completed / exit_code=0** |

### 各工程の実測（チェーン総所要 1,237秒 = 20.6分）

| 工程 | 所要 |
|---|---:|
| bootstrap（ai-toolkit + 依存） | 366秒 |
| torch cu126 へ入れ替え | 142秒 |
| モデル40GB DL（bootstrapと並行） | 516秒 |
| **smoke学習 100step** | **721秒** |

※ A40（9 vCPU）では bootstrap に **35分**かかった。H200（24 vCPU）では **6分**。
**高いGPUほどセットアップも速い**ので、「高いGPUはセットアップ時間の固定費が痛い」は思ったほど成立しない。

### ★ 核心の実測値

```
1ステップ      = 3.66秒   (resolution 512, batch 1, LoRA rank 16)
VRAMピーク     = 3,959 MiB / 143,771 MiB  (2.8%)
GPU使用率ピーク = 29%
生成物         = 447MB の safetensors
```

### ★★ 記事の結論: 律速はVRAMではなくシステムRAMだった

3回の失敗と1回の成功を並べると構造が完全に見える。

| 試行 | VRAM | **システムRAM** | 結果 |
|---|---:|---:|---|
| ローカル RTX 3060 | 12GB | 30GB | ✗ 2時間25分で0ステップ |
| RunPod A40 | 48GB | 50GB | ✗ ロード中に OOM Kill (137) |
| RunPod A40（low_vram=false） | 48GB | 50GB | ✗ 同上 |
| **RunPod H200** | 141GB | **233GB** | **✓ 3.66秒/step** |

**実際に使ったVRAMは4GB。** つまり手持ちのRTX 3060(12GB)でもVRAMは足りていた。
失敗の原因は終始「モデル41GBをCPU側に展開する経路」で、GPUに届いた後は余裕だった。

死んだ位置も毎回同じ:
```
Loading Qwen3-VL text encoder from qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors
 - attached 351 pre-quantized nvfp4/int8 layers
Text encoder is already nvfp4/int8 quantized; skipping quantize_te
Killed                      ← transformer 20GB + TE 15.7GB = 36GB で50GBを突破
```

**H3は本体33Bだけでなく、テキストエンコーダもQwen3-VLの32B。** 実質65B級をロードしている。
「動画モデル＝VRAMが要る」という直感が、そもそも間違いだった。

### ★★★ RunPodのシステムRAMは価格と相関しない（最重要の実用情報）

料金ページに system RAM が明記されている。RAM 100GB以上で絞ると:

| GPU | VRAM | **システムRAM** | vCPU | $/h |
|---|---:|---:|---:|---:|
| **RTX 3090** | 24GB | **125GB** | 16 | **$0.50** |
| RTX 6000 Ada | 48GB | 167GB | 10 | $0.84 |
| A100 PCIe | 80GB | 117GB | 8 | $1.39 |
| RTX Pro 6000 | 96GB | 188GB | 16 | $1.99 |
| H100 PCIe | 80GB | 188GB | 16 | $2.89 |
| H200 | 141GB | 276GB | 24 | $4.39 |

**罠**:
- **RTX 4090 は システムRAM 41GB しかない**（$0.69）。当初4090で行く計画だったが、
  引いていたらA40(50GB)より早く死んでいた。在庫切れで引けなかったのは幸運だった。
- H100 NVL は $3.19 出しても RAM 94GB で100GBに届かない。
- **RTX 3090 は $0.50 で 125GB**。4090より安いのにRAMは3倍。

→ **「高いGPUを選べばRAMも増える」は完全な誤り。** これが今日の遠回りの正体。

### 費用の実績

| 項目 | 金額 |
|---|---:|
| A40での失敗2回（うち遊休83分） | $1.25 |
| H200（セットアップ+smoke完走、約34分） | $1.54 |
| **合計** | **$2.79（約¥420）** |

当初見積もり「初回$30〜60」に対し、**1/10以下**で「動く構成」の確定まで到達した。

### やらかし集（記事の"あるある"枠）

1. **pipのバージョン判定**: `pip install torch==2.13.0 --index-url .../cu128` は
   `2.13.0+cu130` が入っていると「既に満たしている」と判断して**何もしない**。
   ビルドタグを見てくれないので `torch==2.13.0+cu126` と明示するか `--force-reinstall`。
2. **cu128 index には torch 2.13.0 が無い**（最新2.11.0）。cu126 index には 2.13.0 がある。
   **バージョンを変えずにCUDAビルドだけ落とす**のが正解だった。
3. **`pgrep -f foo.sh` の自己マッチ**: SSH越しに実行するとコマンド文字列自体にマッチして
   常に「実行中」を返す。完了検知が永久に成立しない。`pgrep -f "[f]oo.sh"` と書く。
   （同じ理由で `pkill -f` は自分のシェルを殺す）
4. **失敗後の遊休課金**: OOMで死んだ後、Podを83分放置して$0.64を溶かした。
   **失敗時に自動で止める仕組みまで含めて初めて自動化**と言える。
5. **GraphQLの `lowestPrice.uninterruptablePrice` を実勢価格と誤認**:
   H200 NVLで$0.50という異常値が入っていた。正しくは `securePrice` / `communityPrice`。
   9倍の見積もりミスをやらかした。

### 次の検証（未実施）

- **RTX 3090（$0.50/h・RAM 125GB）で800ステップ**を回し、H200との総額を比較する。
  GPU使用率が29%しかない＝律速はCPU側なので、**GPUを落としても速度はさほど落ちない**という仮説。
  これが正しければ、H200($3.74)に対し3090は$1〜3で済む。
- 本番configは `resolution: [512, 768]` で smoke(512のみ)より重い。1ステップは1.5〜2.5倍を見込む。

---

## 6章: 学習したLoRAは本当に使えるのか（2026-08-12 検証）

### 事前の懸念: 学習時と推論時でモデル形式が違う

| | ファイル | 形式 |
|---|---|---|
| 学習(ai-toolkit) | `minimax_h3_ref2va_pruned_int8_convrot.safetensors` | 枝刈りINT8 ConvRot (20.9GB) |
| 推論(ComfyUI) | `MiniMax-H3-Ref2VA-Q3_K_M.gguf` | **GGUF Q3_K_M (15.6GB)** |

量子化方式がまったく違うので、LoRAのキーが噛み合わない恐れがあった。

### 結果: 完全に移植できた

```
Model MiniMaxH3 prepared for dynamic VRAM loading.
14877MB Staged. 208 patches attached.      ← 208モジュール全部に適用
```

- 「lora key not loaded」警告は **0件**
- LoRAの構造: 50ブロック(0-49) × 4モジュール(attn.qkv_proj / attn.out_proj / mlp.fc1 / mlp.fc2) + token_refiner = **208**
- **`208 patches attached` と完全一致**

> **量子化形式が違ってもレイヤー名の構造が同じならLoRAは移植できる。**
> 「学習はsafetensorsの枝刈りINT8、推論はGGUF」という組み合わせが成立した。

### 推論時のVRAM: 9.3GB

LoRA適用込みで **9,326 MiB**。**RTX 3060(12GB)にも収まる**。
学習には233GBのRAMを積んだマシンが必要だったが、**推論は手元の3060で足りる**という非対称性。

生成時間は 864×480・5秒で **約13分**（RTX 3060）。

### 検証の設計（対照実験）

R2Vは参照画像でキャラを固定するモデルなので、そのままだと
「LoRAの効果か参照画像の効果か」が分離できない。そこで:

- 参照画像に **validationセットの1枚**（学習に使っていない画像）を使う
- **seed・プロンプト・解像度・ステップを完全に固定**し、LoRAの有無だけを変える

```python
w["21"] = {"class_type": "LoraLoaderModelOnly",
           "inputs": {"model": ["1",0], "lora_name": LORA, "strength_model": 1.0}}
for nid in ("8","10"):            # BasicGuider と BasicScheduler
    w[nid]["inputs"]["model"] = ["21", 0]
```

`UnetLoaderGGUF` の後ろに `LoraLoaderModelOnly` を挟み、**modelを受け取る全ノードを差し替える**のがポイント。
片方だけ差し替えると、guiderとschedulerで別モデルを見て事故る。

### トリガーワードの設計

configの `trigger_word` は `null` だが、**キャプション側に手書きで仕込む**方式だった。

```
masafy_character, a cute anthropomorphic red panda wearing brown aviator goggles
and a pink patterned scarf, smiling and making an OK hand gesture, ...
```

- 全キャプションが `masafy_character,` で始まる → キャラの同一性がこの語に紐づく
- 外見の特徴（ゴーグル、スカーフ）も**毎回明記** → 言葉でも制御できる余地を残す
- ポーズ・表情・背景は画像ごとに違う記述 → **可変要素として分離**され固定されない
- `caption_dropout_rate: 0.05` → 5%はキャプション無しで学習

### 結果

**成功。** LoRA適用版の動画は、キャラの同一性・デザインの細部とも良好に再現された。
（対照実験のLoRA無し版との差分は別途比較）

### 全体のまとめ（記事の締め）

| フェーズ | 必要なもの | 手元の3060で足りるか |
|---|---|---|
| **LoRA学習** | **システムRAM 100GB超** / VRAMは4GBで足りる | ✗ RAMが足りない |
| **推論** | VRAM 9.3GB | **✓ 足りる** |

「動画モデルのファインチューニングにはVRAMが要る」という直感は誤り。
**要るのはシステムRAM**で、しかもそれは**推論では要らない**。
借りるべきは「VRAMの大きいGPU」ではなく「**RAMの大きいマシン**」だった。

総額 **約$5.45（¥820）** で、学習から検証まで到達した。

---

## 7章: 対照実験の結果 —「参照画像があるならLoRAは要らないのでは？」への回答

### 実験条件（LoRAの有無だけを変える）

| 項目 | 値 |
|---|---|
| 参照画像 | `masafy_004.png`（**validationセット＝学習に使っていない1枚**） |
| プロンプト | `masafy_character, ...`（手を振る→サムズアップ、晴れた公園） |
| seed | 20260812（固定） |
| 解像度 / ステップ | 864×480 / 20（固定） |
| LoRA強度 | 1.0 |

### 結果

| 評価項目 | LoRA ON | LoRA OFF |
|---|---|---|
| キャラの安定性 | 良好 | **良好（破綻なし）** |
| フレーム間のちらつき | なし | **なし** |
| **デザインの忠実さ** | **良好** | **全然違う** |
| 絵のタッチ | 学習データ準拠 | **別物** |
| 出力ファイルサイズ | **538 KB** | **1,114 KB（2.07倍）** |

### ★ 役割分担が明確に分かれた

```
参照画像(R2V)  → 「何が写っているか」: 構造・安定性・ゴーグルとスカーフの存在
LoRA           → 「どう描かれるか」  : 絵柄・デザインの忠実さ
```

**LoRA無しでも、参照画像のおかげでキャラは破綻せず出る。** ゴーグルもスカーフも掛かっているし、
ちらつきもない。**しかしタッチが別物になる。** ここをLoRAが埋めた。

> つまり「参照画像でキャラ固定できるならLoRAは不要」は**誤り**。
> 参照画像が伝えるのは被写体であって、**画風は伝わらない**。

### ファイルサイズが2倍になった理由（考察）

同一の解像度・長さ・コーデック設定で **OFFが2.07倍**。
当初は「ON版が安定していて圧縮が効いた」と推測したが、**OFFにもちらつきは無かった**ので外れ。

より妥当な説明は**画風の差**。学習データはフラットな塗りのステッカー風イラストで、
LoRAが効くと階調が少なくH.264がよく圧縮される。OFFはベースモデル寄りの描き込まれたタッチに
なるため情報量が増える。

> **ファイルサイズは「画風がどちらに寄ったか」の定量指標として使える。**
> 目視評価しかできないと思われがちなスタイル転移に、数値的な傍証を与えられる。

### 記事としての結論

キャラLoRAの投資対効果は「キャラが出せるようになること」ではなく
「**自分の絵柄で出せるようになること**」にある。
R2Vのような参照画像方式が使えるモデルでは、この区別が特に重要になる。

かかった費用は **$5.45（¥820）**。
