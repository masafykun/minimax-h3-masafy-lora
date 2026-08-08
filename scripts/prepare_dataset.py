#!/usr/bin/env python3
"""Prepare MASAFY LoRA images without modifying the source directory."""

from __future__ import annotations

import argparse
import hashlib
import json
import unicodedata
from collections import Counter
from pathlib import Path

from PIL import Image, ImageOps


REPO_ROOT = Path(__file__).resolve().parents[1]


def normalized_name(value: str) -> str:
    return unicodedata.normalize("NFC", value)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", default=REPO_ROOT / "dataset", type=Path)
    parser.add_argument("--manifest", default=REPO_ROOT / "dataset" / "manifest.json", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.source.expanduser().resolve()
    destination = args.destination.expanduser().resolve()

    if not source.is_dir():
        raise SystemExit(f"Source directory does not exist: {source}")

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    entries = manifest["entries"]
    source_index = {
        normalized_name(path.name): path
        for path in source.iterdir()
        if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
    }

    requested = [normalized_name(entry["source"]) for entry in entries]
    missing = sorted(name for name in requested if name not in source_index)
    if missing:
        raise SystemExit("Missing source images:\n- " + "\n- ".join(missing))

    output_names = [entry["output"] for entry in entries]
    duplicates = [name for name, count in Counter(output_names).items() if count > 1]
    if duplicates:
        raise SystemExit(f"Duplicate output names in manifest: {duplicates}")

    audit_entries: list[dict[str, object]] = []
    split_counts: Counter[str] = Counter()

    for entry in entries:
        split = entry["split"]
        if split not in {"train", "validation", "excluded"}:
            raise SystemExit(f"Unsupported split: {split}")

        source_path = source_index[normalized_name(entry["source"])]
        split_dir = destination / split
        split_dir.mkdir(parents=True, exist_ok=True)
        image_path = split_dir / f"{entry['output']}.png"
        caption_path = split_dir / f"{entry['output']}.txt"

        with Image.open(source_path) as opened:
            image = ImageOps.exif_transpose(opened)
            original_size = image.size
            has_alpha = "A" in image.getbands()
            if has_alpha:
                rgba = image.convert("RGBA")
                white = Image.new("RGBA", rgba.size, "white")
                white.alpha_composite(rgba)
                image = white.convert("RGB")
            else:
                image = image.convert("RGB")
            image.save(image_path, format="PNG", optimize=True)

        caption_path.write_text(entry["caption"].strip() + "\n", encoding="utf-8")
        split_counts[split] += 1
        audit_entries.append(
            {
                "source": entry["source"],
                "output": image_path.name,
                "split": split,
                "width": original_size[0],
                "height": original_size[1],
                "source_sha256": sha256(source_path),
                "prepared_sha256": sha256(image_path),
            }
        )

    audit = {
        "trigger": manifest["trigger"],
        "source": str(source),
        "counts": dict(sorted(split_counts.items())),
        "entries": audit_entries,
    }
    audit_path = destination / "dataset-audit.json"
    audit_path.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Prepared dataset in {destination}")
    for split in ("train", "validation", "excluded"):
        print(f"{split}: {split_counts[split]}")
    print(f"Audit: {audit_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
