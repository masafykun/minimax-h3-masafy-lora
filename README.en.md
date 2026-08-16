[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Paper](https://img.shields.io/badge/paper-JA%20%2F%20EN-blue.svg?style=flat-square)](paper/)
[![Model](https://img.shields.io/badge/%F0%9F%A4%97%20Hugging%20Face-LoRA-yellow.svg?style=flat-square)](https://huggingface.co/masafy/minimax-h3-masafy-lora)
[![ORCID](https://img.shields.io/badge/ORCID-0009--0000--7977--2756-a6ce39.svg?style=flat-square)](https://orcid.org/0009-0000-7977-2756)

# 🎬 MiniMax H3 Character LoRA

> What fine-tuning a 33B omni-modal video model actually taught us — **the binding constraint was system RAM, not VRAM**

A record of training a character LoRA for **MiniMax H3**, a 33B-parameter video generation model, on an original character. **Peak VRAM during training measured 3,959 MiB — 2.8% of the card** — while the run failed three times with OOM on hosts holding 50 GB of system RAM and completed only on a host with **188 GB**. Total spend, training through paper, was **about five US dollars**.

*[日本語](README.md)*

🔗 **Paper**: [English](paper/paper_en.pdf) / [日本語](paper/paper_ja.pdf) · 🤗 **Weights**: [Hugging Face](https://huggingface.co/masafy/minimax-h3-masafy-lora)

---

## 📸 Result

Same seed, same reference image, adapter toggled:

![Adapter ablation](paper/figures/fig_ablation_frames.png)

The reference image supplies the character's **structure**; it does not supply the **style**. The top row renders as flat illustration, the bottom row renders individual strands of fur.

## ✨ Findings

- **System RAM is the constraint** — two 48 GB-VRAM hosts sit on opposite sides of the outcome column, so VRAM carries no signal. System RAM separates cleanly between 50 GB and 188 GB
- **Under 4 GB of VRAM is enough** — peak measured 3,959 MiB. On VRAM alone, even a 12 GB RTX 3060 would have sufficed
- **RAM allocation ignores price** — the RTX 4090 ($0.69/h) ships 41 GB of RAM, less than the cheaper RTX 3090's 125 GB ($0.50/h). **Never infer RAM from the GPU tier**
- **Adapters cross quantization boundaries** — a LoRA trained on pruned INT8 applied to a GGUF Q3_K_M stack with **all 208 modules matching** and zero key mismatches
- **Inference stays local** — 9.3 GB of VRAM. Rent for training, run at home
- **The adapter carries style** — with reference-image conditioning, structural stability comes from the reference. The return on a character LoRA is rendering *in your own style*
- **800 steps was excessive** — cross-validation puts the optimum at **500 steps, strength 0.8**, cutting training from about two hours to about 1.25
- **Silent CPU fallback** — pip installs a CUDA 13 build by default; against a 12.8 driver `cuda.is_available()` stays false while training reports progress and burns hours on CPU

## 🛠️ Stack

| Category | Technology |
|---|---|
| Base model | MiniMax H3 Ref2VA (pruned INT8 ConvRot, 20.0 GB) |
| Text encoder | Qwen3-VL 32B (nvfp4 AWQ, 15.7 GB) |
| Training | [ai-toolkit](https://github.com/ostris/ai-toolkit) @ `f4e9130` |
| Inference | ComfyUI + ComfyUI-GGUF (Q3_K_M) |
| Training host | RunPod RTX 6000 Ada (48 GB VRAM / 188 GB RAM / $0.84h) |
| Inference host | RTX 3060 12 GB (local) |
| Typesetting | LuaLaTeX + luatexja (two-column) |

## 📁 Layout

```
.
├── paper/                  technical report (JA / EN)
│   ├── paper_ja.tex/.pdf     Japanese, 7 pages
│   ├── paper_en.tex/.pdf     English, 7 pages
│   └── figures/              7 figures
├── dataset/                training data (published)
│   ├── train/                12 images + captions
│   ├── validation/           2 held-out images
│   └── excluded/             2 images dropped for style divergence
├── logs/                   measurements
│   ├── training_loss.csv     799 loss points
│   ├── env_matrix.csv        VRAM / RAM / outcome per host
│   ├── ram_allocation.csv    advertised versus measured RAM
│   ├── timings.csv           seconds per phase
│   └── cost.csv              costs, estimated and measured kept apart
├── scripts/
│   ├── runpod-automation/    unattended-run kit (below)
│   └── ...                   training and monitoring scripts
├── config/                 training configs (smoke / coexist / full)
└── lora/README.md          where the weights live, recommended settings
```

## 🚀 Usage

### Inference (ComfyUI)

```bash
# 1. Fetch the weights from Hugging Face into models/loras/
# 2. Insert LoraLoaderModelOnly after UnetLoaderGGUF
# 3. Re-point every node that consumes the model (see the caveat below)
```

```
UnetLoaderGGUF → LoraLoaderModelOnly → BasicGuider
                                     → BasicScheduler
```

Re-point **both `BasicGuider` and `BasicScheduler`**. Patching only one leaves the guider and the scheduler looking at different models, and it fails quietly.

Start prompts with `masafy_character,` and then describe the appearance (brown aviator goggles, pink patterned scarf). **The trigger token alone is not enough** — see paper §8.4.

### Reproducing the training

```bash
# Choose a host by RAM, not by VRAM
python3 scripts/runpod-automation/sample_ram.py

# After the pod is up, upload and start the chain
RUNPOD_SSH_HOST=... RUNPOD_SSH_PORT=... RUNPOD_SSH_KEY=... bash scripts/upload_to_runpod.sh
ssh pod "apt-get install -y rsync"           # pods ship without rsync
ssh pod "setsid nohup bash /workspace/chain_full.sh &"

# Start the guardian locally: detect completion, harvest, terminate
setsid nohup bash scripts/runpod-automation/guardian.sh <POD_ID> <IP> <PORT> &
```

## 🤖 Unattended-run kit

`scripts/runpod-automation/` holds three scripts that make a metered host behave like "start it, and by morning it is finished and no longer billing." The full training run completed under this setup with no human in the loop.

| File | Role |
|---|---|
| `chain_full.sh` | On the pod: download → build → fix CUDA → **verify** → train, with no idle gaps |
| `guardian.sh` | Off the pod: on completion, 24 h, or a $3 balance floor — harvest, then terminate |
| `sample_ram.py` | Measure RAM per GPU type by creating a pod, reading, and destroying it |

Three design rules, each learned the hard way:

- **Keep the guardian outside the pod** — inside, terminating the pod kills the process before it finishes collecting
- **Detect completion by file, not by process name** — `pgrep -f xxx.sh` over SSH matches the command string you just sent, so it always returns true
- **Stopping does not stop billing** — storage bills at double rate while stopped. **Terminate**

See [scripts/runpod-automation/README.md](scripts/runpod-automation/README.md).

## 📄 Series

Third in a series on character LoRA fine-tuning against consumer hardware.

| | Model | Scale | Outcome |
|---|---|---|---|
| 1 | Stable Diffusion 1.5 | 1B | worked on an RTX 3060 |
| 2 | [Krea 2](https://github.com/masafykun/krea2-character-lora) | 12B | worked with FP8 and block swapping |
| **3** | **MiniMax H3 (this repo)** | **33B + 32B TE** | **did not work — and not because of VRAM** |

## 📚 Citation

```bibtex
@techreport{suzuki2026h3lora,
  author = {Suzuki, Masato},
  title  = {Character LoRA Fine-tuning of a 33B Omni-modal Video Model:
            System RAM, Not VRAM, Was the Binding Constraint},
  year   = {2026},
  url    = {https://github.com/masafykun/minimax-h3-masafy-lora}
}
```

## 🎨 About the character

"Masafy", the character in `dataset/`, is an original character created by the author. The images and captions are published so the experiment can be reproduced, but **the character design remains the author's work**. Please credit the author if you use it.

## License

- **Code** (`scripts/`): **MIT** — see [LICENSE](LICENSE)
- **Paper, figures and measurements** (`paper/`, `logs/`): **CC BY 4.0**
- **Model weights**: governed by the base model's license — see [NOTICE.md](NOTICE.md). Commercial use **requires attribution to "MiniMax H3"**
- **Character images** (`dataset/`): see "About the character" above

© 2026 masafykun (https://github.com/masafykun)
