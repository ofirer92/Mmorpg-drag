#!/usr/bin/env python3
"""Generate a placeholder 32×32 pixel-art spritesheet from a YAML spec.
Spec: { name: str, size: 32, frames: {idle: 2, run: 4, ...}, colour: "#RRGGBB" | archetype: stim }
Output: client/assets/generated/<name>.png + <name>.import + row in docs/art_needed.md."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

import yaml
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "client/assets/generated"


def archetype_colour(aid: str) -> str:
    classes = yaml.safe_load((ROOT / "docs/balance/classes.yaml").read_text())["archetypes"]
    return classes[aid]["colour"]


def draw_frame(img: Image.Image, x0: int, size: int, colour: str, anim: str, i: int, rng: random.Random) -> None:
    d = ImageDraw.Draw(img)
    r, g, b = int(colour[1:3], 16), int(colour[3:5], 16), int(colour[5:7], 16)
    dark = (max(r - 60, 0), max(g - 60, 0), max(b - 60, 0), 255)
    bob = (i % 2) if anim in ("idle", "run") else 0
    # body
    d.rectangle([x0 + size // 4, size // 4 + bob, x0 + 3 * size // 4, size - 2], fill=(r, g, b, 255), outline=dark)
    # head
    d.rectangle([x0 + size // 3, 2 + bob, x0 + 2 * size // 3, size // 4 + bob], fill=(r, g, b, 255), outline=dark)
    # eyes
    d.point([(x0 + size // 3 + 3, 6 + bob), (x0 + 2 * size // 3 - 3, 6 + bob)], fill=(0, 0, 0, 255))
    # limbs vary per frame
    leg = (i % 3) - 1
    d.line([(x0 + size // 3, size - 2), (x0 + size // 3 + leg * 3, size - 1)], fill=dark)
    d.line([(x0 + 2 * size // 3, size - 2), (x0 + 2 * size // 3 - leg * 3, size - 1)], fill=dark)
    if anim == "attack":
        d.line(
            [(x0 + 3 * size // 4, size // 2), (x0 + size - 1, size // 2 - i * 2)], fill=(255, 255, 255, 255), width=2
        )
    if anim == "hurt":
        d.rectangle([x0, 0, x0 + size - 1, size - 1], outline=(255, 0, 0, 255))
    if anim == "dead":
        d.rectangle([x0 + 2, size - 8, x0 + size - 2, size - 2], fill=(r, g, b, 255), outline=dark)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    spec = yaml.safe_load(Path(args.spec).read_text())
    name, size = spec["name"], int(spec.get("size", 32))
    colour = spec.get("colour") or archetype_colour(spec["archetype"])
    frames: dict[str, int] = spec.get("frames", {"idle": 2})
    cols = max(frames.values())
    rows = len(frames)
    img = Image.new("RGBA", (cols * size, rows * size), (0, 0, 0, 0))
    rng = random.Random(args.seed)
    for row, (anim, n) in enumerate(frames.items()):
        for i in range(n):
            frame = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            draw_frame(frame, 0, size, colour, anim, i, rng)
            img.paste(frame, (i * size, row * size))
    OUT.mkdir(parents=True, exist_ok=True)
    png = OUT / f"{name}.png"
    img.save(png)
    (OUT / f"{name}.png.import").write_text(
        '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
        "compress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=true\n"
        "detect_3d/compress_to=0\n"
    )
    (OUT / f"{name}.sheet.yaml").write_text(
        yaml.safe_dump(
            {"size": size, "rows": {a: {"row": r, "frames": n} for r, (a, n) in enumerate(frames.items())}},
            sort_keys=False,
        )
    )
    art = ROOT / "docs/art_needed.md"
    text = art.read_text()
    spec_rel = Path(args.spec).relative_to(ROOT).as_posix() if Path(args.spec).is_absolute() else args.spec
    frames_desc = ", ".join(f"{a}×{n}" for a, n in frames.items())
    png_rel = f"client/assets/generated/{name}.png"
    row = f"| {png_rel} | gen_sprite.py {spec_rel} | {size}px, {frames_desc}, {colour} | placeholder |"
    if row not in text:
        text = text.replace("| (none yet) | | | |\n", "")
        art.write_text(text.rstrip("\n") + "\n" + row + "\n")
    print(f"wrote {png.relative_to(ROOT)} ({cols}×{rows} frames of {size}px)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
