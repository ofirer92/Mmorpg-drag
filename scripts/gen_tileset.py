#!/usr/bin/env python3
"""Generate a placeholder 32×32 pixel-art TileMapLayer tileset from a YAML spec.
Spec: { name: str, size: 32, tiles: [str, ...], colours: {tile: "#RRGGBB"} }
Tiles are laid out left→right in one row, in spec order — that order is the atlas
column index used by client/scripts/maps/clinic_lobby.gd and
client/tools/gen_tileset_resource.gd. Output: client/assets/generated/<name>.png +
<name>.png.import + a row in docs/art_needed.md.

The actual TileSet .tres (with physics collision polygons per tile) is built by
client/tools/gen_tileset_resource.gd, run through the Godot binary itself so the
resource format is engine-validated instead of hand-written:
    godot --headless --path client -s tools/gen_tileset_resource.gd
"""

from __future__ import annotations

import argparse
from pathlib import Path

import yaml
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "client/assets/generated"


def hex_to_rgb(colour: str) -> tuple[int, int, int]:
    colour = colour.lstrip("#")
    return int(colour[0:2], 16), int(colour[2:4], 16), int(colour[4:6], 16)


def draw_ground(d: ImageDraw.ImageDraw, x0: int, size: int, rgb: tuple[int, int, int]) -> None:
    dark = tuple(max(c - 40, 0) for c in rgb)
    d.rectangle([x0, 0, x0 + size - 1, size - 1], fill=rgb)
    for y in range(4, size, 8):
        d.line([(x0, y), (x0 + size - 1, y)], fill=dark)


def draw_ground_top(d: ImageDraw.ImageDraw, x0: int, size: int, rgb: tuple[int, int, int]) -> None:
    dark = tuple(max(c - 40, 0) for c in rgb)
    d.rectangle([x0, 0, x0 + size - 1, size - 1], fill=rgb)
    d.rectangle([x0, 0, x0 + size - 1, 5], fill=dark)


def draw_platform(d: ImageDraw.ImageDraw, x0: int, size: int, rgb: tuple[int, int, int]) -> None:
    dark = tuple(max(c - 50, 0) for c in rgb)
    d.rectangle([x0, 0, x0 + size - 1, size - 1], fill=rgb, outline=dark, width=2)
    d.line([(x0 + 4, size // 2), (x0 + size - 5, size // 2)], fill=dark)


def draw_wall(d: ImageDraw.ImageDraw, x0: int, size: int, rgb: tuple[int, int, int]) -> None:
    dark = tuple(max(c - 30, 0) for c in rgb)
    d.rectangle([x0, 0, x0 + size - 1, size - 1], fill=rgb)
    for x in range(x0, x0 + size, 8):
        d.line([(x, 0), (x, size - 1)], fill=dark)


def draw_background(d: ImageDraw.ImageDraw, x0: int, size: int, rgb: tuple[int, int, int]) -> None:
    dark = tuple(max(c - 20, 0) for c in rgb)
    d.rectangle([x0, 0, x0 + size - 1, size - 1], fill=rgb)
    d.rectangle([x0, 0, x0 + size - 1, size - 1], outline=dark)


def draw_accent(d: ImageDraw.ImageDraw, x0: int, size: int, rgb: tuple[int, int, int]) -> None:
    bg = (0xD7, 0xDE, 0xD9)
    d.rectangle([x0, 0, x0 + size - 1, size - 1], fill=bg)
    mid = size // 2
    arm = size // 6
    d.rectangle([x0 + mid - arm, mid - 2 * arm, x0 + mid + arm, mid + 2 * arm], fill=rgb)
    d.rectangle([x0 + mid - 2 * arm, mid - arm, x0 + mid + 2 * arm, mid + arm], fill=rgb)


DRAWERS = {
    "ground": draw_ground,
    "ground_top": draw_ground_top,
    "platform": draw_platform,
    "wall": draw_wall,
    "background": draw_background,
    "accent": draw_accent,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("spec")
    args = ap.parse_args()
    spec = yaml.safe_load(Path(args.spec).read_text())
    name, size = spec["name"], int(spec.get("size", 32))
    tiles: list[str] = spec["tiles"]
    colours: dict[str, str] = spec.get("colours", {})

    img = Image.new("RGBA", (len(tiles) * size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, tile in enumerate(tiles):
        rgb = hex_to_rgb(colours.get(tile, "#808080"))
        drawer = DRAWERS.get(tile, draw_background)
        drawer(d, i * size, size, rgb)

    OUT.mkdir(parents=True, exist_ok=True)
    png = OUT / f"{name}.png"
    img.save(png)
    (OUT / f"{name}.png.import").write_text(
        '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
        "compress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=true\n"
        "detect_3d/compress_to=0\n"
    )

    art = ROOT / "docs/art_needed.md"
    text = art.read_text()
    spec_rel = Path(args.spec).relative_to(ROOT).as_posix() if Path(args.spec).is_absolute() else args.spec
    tiles_desc = ", ".join(tiles)
    png_rel = f"client/assets/generated/{name}.png"
    row = f"| {png_rel} | gen_tileset.py {spec_rel} | {size}px tiles: {tiles_desc} | placeholder |"
    if row not in text:
        text = text.replace("| (none yet) | | | |\n", "")
        art.write_text(text.rstrip("\n") + "\n" + row + "\n")
    print(f"wrote {png.relative_to(ROOT)} ({len(tiles)} tiles of {size}px)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
