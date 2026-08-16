# NOTICE

This repository contains a LoRA (Low-Rank Adaptation) adapter, its training
dataset, and a technical report. Please observe the following attributions and
licenses.

## Base model (not redistributed here)

The LoRA was trained on **MiniMax H3** (Ref2VA, pruned INT8 ConvRot variant)
and is intended for inference on the **GGUF Q3_K_M** quantization of the same
model. The MiniMax H3 weights are **not** redistributed in this repository.
The LoRA adapter is a derivative work of MiniMax H3 and its use is subject to
the **MiniMax H3 license**.

Commercial use of MiniMax H3 is permitted, and **attribution to "MiniMax H3"
is required** when the outputs are used commercially. The license also carries
a territorial clause; consult the official terms for your jurisdiction.

## Auxiliary models (not redistributed here)

- Text encoder: **Qwen3-VL 32B** (`qwen3vl_32b_minimax_h3_nvfp4_awq`) — subject to its own license.
- Autoencoders: MiniMax H3 video VAE (fp16) and audio VAE (fp32) — subject to their own licenses.

## Tooling

- Training: **ai-toolkit** by ostris (https://github.com/ostris/ai-toolkit), pinned at commit `f4e9130`.
- Inference: **ComfyUI** (https://github.com/comfyanonymous/ComfyUI) with ComfyUI-GGUF.
- Cloud compute: RunPod.

## Character

The character depicted in `dataset/` ("Masafy", a red panda) is an original
character created by the author. The images and captions are published here so
that the experiment can be reproduced. The character design itself remains the
author's work; please credit the author if you use it.
