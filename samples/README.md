# Verification clips

The 24 clips behind the ablations in the paper. Every clip holds the same
seed (`20260812`), the same reference image (`../dataset/validation/masafy_004.png`,
unseen during training), the same prompt, 864x480 and 20 sampler steps —
only the noted condition changes.

`ref016` and `seed2` are the two exceptions, changing the reference image and
the seed respectively.

**Output size is a proxy for style displacement, not for quality.** The training
art is flat-shaded, so as the style converges the codec compresses better. The
smallest files here (`str12`, `ckpt700`) are also the ones carrying artifacts.

| Clip | Aspect | Condition | Steps | Strength | Size |
|---|---|---|---:|---:|---:|
| [`OFF.mp4`](OFF.mp4) | baseline | no adapter | - | - | 1087 KB |
| [`ON.mp4`](ON.mp4) | baseline | final checkpoint | 800 | 1.0 | 525 KB |
| [`str02.mp4`](str02.mp4) | strength | strength sweep | 800 | 0.2 | 866 KB |
| [`str04.mp4`](str04.mp4) | strength | strength sweep | 800 | 0.4 | 840 KB |
| [`str06.mp4`](str06.mp4) | strength | strength sweep | 800 | 0.6 | 792 KB |
| [`str08.mp4`](str08.mp4) | strength | strength sweep | 800 | 0.8 | 667 KB |
| [`str12.mp4`](str12.mp4) | strength | strength sweep, over-applied | 800 | 1.2 | 492 KB |
| [`ckpt300.mp4`](ckpt300.mp4) | checkpoint | checkpoint sweep | 300 | 1.0 | 542 KB |
| [`ckpt400.mp4`](ckpt400.mp4) | checkpoint | checkpoint sweep | 400 | 1.0 | 498 KB |
| [`ckpt500.mp4`](ckpt500.mp4) | checkpoint | checkpoint sweep | 500 | 1.0 | 505 KB |
| [`ckpt600.mp4`](ckpt600.mp4) | checkpoint | checkpoint sweep | 600 | 1.0 | 541 KB |
| [`ckpt700.mp4`](ckpt700.mp4) | checkpoint | checkpoint sweep | 700 | 1.0 | 447 KB |
| [`notrig_on.mp4`](notrig_on.mp4) | trigger | trigger token removed | 800 | 1.0 | 747 KB |
| [`onlytrig.mp4`](onlytrig.mp4) | trigger | trigger only, no appearance | 800 | 1.0 | 412 KB |
| [`night_on.mp4`](night_on.mp4) | unseen | neon street at night | 800 | 1.0 | 831 KB |
| [`night_off.mp4`](night_off.mp4) | unseen | neon street at night, no adapter | - | - | 1210 KB |
| [`bike_on.mp4`](bike_on.mp4) | unseen | riding a bicycle | 800 | 1.0 | 968 KB |
| [`bike_off.mp4`](bike_off.mp4) | unseen | riding a bicycle, no adapter | - | - | 1422 KB |
| [`ref016.mp4`](ref016.mp4) | robustness | different held-out reference | 800 | 1.0 | 525 KB |
| [`seed2.mp4`](seed2.mp4) | robustness | different seed | 800 | 1.0 | 834 KB |
| [`x_c400_s06.mp4`](x_c400_s06.mp4) | cross | cross-validation | 400 | 0.6 | 770 KB |
| [`x_c500_s06.mp4`](x_c500_s06.mp4) | cross | cross-validation | 500 | 0.6 | 660 KB |
| [`x_c500_s08.mp4`](x_c500_s08.mp4) | cross | cross-validation, RECOMMENDED | 500 | 0.8 | 537 KB |
| [`x_c500_s12.mp4`](x_c500_s12.mp4) | cross | cross-validation | 500 | 1.2 | 549 KB |

24 clips. See `../paper/` for the analysis.
