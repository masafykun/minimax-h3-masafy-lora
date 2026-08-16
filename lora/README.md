# LoRA weights

The weights are **not stored in this repository** (155 MB for the final
adapter, 1.1 GB including checkpoints). They are distributed via Hugging Face:

**https://huggingface.co/masafy/minimax-h3-masafy-lora**

| File | Steps | Note |
|---|---:|---|
| `masafy_h3_ref2va_lora_v1.safetensors` | 800 | final |
| `masafy_h3_ref2va_lora_v1_000000700.safetensors` | 700 | |
| `masafy_h3_ref2va_lora_v1_000000600.safetensors` | 600 | |
| `masafy_h3_ref2va_lora_v1_000000500.safetensors` | 500 | **best style fidelity in the ablation** |
| `masafy_h3_ref2va_lora_v1_000000400.safetensors` | 400 | |
| `masafy_h3_ref2va_lora_v1_000000300.safetensors` | 300 | |

## Usage (ComfyUI)

Place the file under `models/loras/` and insert `LoraLoaderModelOnly` between
`UnetLoaderGGUF` and the nodes that consume the model. **Both `BasicGuider`
and `BasicScheduler` must be re-pointed at the LoRA node** — patching only one
of them silently mixes two different models.

```
UnetLoaderGGUF -> LoraLoaderModelOnly -> BasicGuider
                                      -> BasicScheduler
```

The adapter was trained against the pruned INT8 safetensors variant but applies
cleanly to the GGUF Q3_K_M build: all 208 modules attach with no key mismatches.

## Trigger

Begin the prompt with `masafy_character`, then describe the appearance
(brown aviator goggles, pink patterned scarf). The trigger word alone is not
sufficient — see the ablation in the paper.

## Recommended settings

- strength `0.6` for a balance of style and structural accuracy
- strength `1.0`–`1.2` when style fidelity matters more than fine detail
- checkpoint `500` is sufficient; `800` showed no improvement
