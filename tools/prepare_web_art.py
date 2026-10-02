"""
prepare_web_art.py — sizes the images that are uploaded on the Roblox website
(not through the game): the experience icon, the thumbnails, and the picture of
each game pass / developer product.

These keep their filled background (no transparency), so they don't go through
remove_checker.py. Output: art/upload_web/ as PNG in the exact sizes Roblox asks
for; images are centre-cropped when the aspect ratio doesn't match.

  python tools/prepare_web_art.py
"""

from __future__ import annotations

import glob
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "upload_web")

# (source glob, output subfolder, target size) — Roblox's required sizes.
JOBS = [
    ("art/final/branding/game_icon.jpg", "icon", (512, 512)),
    ("art/final/thumbs/thumb_*.jpg", "thumbs", (1920, 1080)),
    ("art/final/passes/pass_*.jpg", "passes", (512, 512)),
    ("art/final/products/product_*.jpg", "products", (512, 512)),
]


def fit(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target = size[0] / size[1]
    width, height = image.size
    if width / height > target:  # too wide: trim the sides
        new_width = round(height * target)
        left = (width - new_width) // 2
        image = image.crop((left, 0, left + new_width, height))
    elif width / height < target:  # too tall: trim top and bottom
        new_height = round(width / target)
        top = (height - new_height) // 2
        image = image.crop((0, top, width, top + new_height))
    return image.resize(size, Image.LANCZOS)


def main() -> int:
    count = 0
    for pattern, folder, size in JOBS:
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            name = os.path.splitext(os.path.basename(path))[0] + ".png"
            out_path = os.path.join(OUT, folder, name)
            fit(Image.open(path).convert("RGB"), size).save(out_path, optimize=True)
            print(f"{folder}/{name}  {size[0]}x{size[1]}")
            count += 1
    print(f"{count} images in {os.path.relpath(OUT, ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
