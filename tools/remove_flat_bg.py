"""
remove_flat_bg.py — cuts a magenta backdrop out of generated art.

Image models rarely output real transparency, so the prompts ask for a magenta
(#FF00FF) backdrop: a colour this game's art never uses. What comes back is not
flat, though — there is a gradient across the canvas and JPEG noise on top — so
matching one colour does not work. Instead each pixel is measured by HOW
MAGENTA it is:

    magenta = (R + B) / 2 - G

That is large on the backdrop and near zero on the art, whatever the shading.
Pixels are only cut when they are also reachable from the border, so a magenta
eye or gem inside the character survives. The fringe left on the outline is
de-spilled, otherwise every edge glows pink over a dark background.

  python tools/remove_flat_bg.py art/monsters/mob_Meadow.png
  python tools/remove_flat_bg.py --all        # everything in art/monsters
  python tools/remove_flat_bg.py --green ...  # for a green screen instead
  python tools/remove_flat_bg.py --chroma 120 <file>   # art that is itself purple

`--chroma` raises the bar for what counts as backdrop. Purple or pink art scores
high on this measure too, so a monster like the cosmic titan needs a stricter
threshold. When the art scores HIGHER than the backdrop (a magenta jellyfish on
magenta), no threshold can separate them: regenerate that one on a green
backdrop and use --green.

Writes <name>.png (converting .jpg/.jfif on the way) and a preview sheet.
"""

from __future__ import annotations

import glob
import os
import sys
from collections import deque

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MONSTERS = os.path.join(ROOT, "art", "monsters")
PREVIEW_DIR = os.path.join(ROOT, "art", "preview")

SIZE = 1024
PADDING = 0.04
# Backdrop when the measure is above BG, art below EDGE, fading in between.
CHROMA_BG = 60
CHROMA_EDGE = 18
EDGE_RATIO = CHROMA_EDGE / CHROMA_BG  # kept when --chroma moves the bar
EDGE_BLUR = 0.8
# How far the de-spill reaches inside the art, in pixels.
SPILL_RADIUS = 3
MIN_ALPHA = 24  # below this a pixel is treated as fully cut when cropping


def magenta_score(pixel: tuple[int, int, int]) -> float:
    red, green, blue = pixel
    return (red + blue) / 2 - green


def green_score(pixel: tuple[int, int, int]) -> float:
    red, green, blue = pixel
    return green - (red + blue) / 2


def cut(path: str, score, chroma_bg: float = CHROMA_BG) -> str:
    chroma_edge = chroma_bg * EDGE_RATIO
    img = Image.open(path).convert("RGB")
    width, height = img.size
    pixels = list(img.get_flattened_data())
    total = width * height
    scores = [score(pixel) for pixel in pixels]

    # 1. Backdrop pixels reachable from the border (keeps magenta inside the art).
    passable = bytearray(1 if value >= chroma_edge else 0 for value in scores)
    outside = bytearray(total)
    queue: deque[int] = deque()

    def seed(index: int):
        if passable[index] and not outside[index]:
            outside[index] = 1
            queue.append(index)

    for x in range(width):
        seed(x)
        seed((height - 1) * width + x)
    for y in range(height):
        seed(y * width)
        seed(y * width + width - 1)
    while queue:
        index = queue.popleft()
        x = index % width
        if x + 1 < width:
            seed(index + 1)
        if x > 0:
            seed(index - 1)
        if index + width < total:
            seed(index + width)
        if index >= width:
            seed(index - width)

    # 2. Alpha: out where clearly backdrop, fading across the edge band.
    alpha = bytearray(total)
    for index in range(total):
        if not outside[index]:
            alpha[index] = 255
            continue
        value = scores[index]
        if value >= chroma_bg:
            alpha[index] = 0
        else:
            span = chroma_bg - chroma_edge
            alpha[index] = int((1 - (value - chroma_edge) / span) * 255)
    mask = Image.new("L", (width, height))
    mask.putdata(alpha)
    mask = mask.filter(ImageFilter.GaussianBlur(EDGE_BLUR))

    # 3. De-spill: near the cut, pull the backdrop's colour out of the pixel.
    #    Restricted to a thin band so pink art elsewhere is untouched.
    band = Image.new("L", (width, height))
    band.putdata([255 if outside[index] else 0 for index in range(total)])
    band = band.filter(ImageFilter.MaxFilter(SPILL_RADIUS * 2 + 1))
    near_edge = list(band.get_flattened_data())

    faded = list(mask.get_flattened_data())
    result = []
    for index in range(total):
        a = faded[index]
        if a == 0:
            result.append((0, 0, 0, 0))
            continue
        red, green, blue = pixels[index]
        if near_edge[index] > 0:
            spill = max(scores[index], 0)
            if score is magenta_score:
                red = int(max(0, red - spill))
                blue = int(max(0, blue - spill))
            else:
                green = int(max(0, green - spill))
        result.append((red, green, blue, a))
    out = Image.new("RGBA", (width, height))
    out.putdata(result)

    # 4. Crop to the art and centre it on a square canvas.
    box = out.getchannel("A").point(lambda value: 255 if value > MIN_ALPHA else 0).getbbox()
    if box:
        out = out.crop(box)
    inner = int(SIZE * (1 - 2 * PADDING))
    out.thumbnail((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(out, ((SIZE - out.width) // 2, (SIZE - out.height) // 2), out)

    # Browsers save these as .png.jfif; keep the intended name.
    name = os.path.basename(path)
    for suffix in (".png.jfif", ".png.jpg", ".jfif", ".jpg", ".jpeg"):
        if name.lower().endswith(suffix):
            name = name[: -len(suffix)] + ".png"
            break
    out_path = os.path.join(os.path.dirname(path), name)
    canvas.save(out_path, optimize=True)
    if out_path != path:
        os.remove(path)
    return out_path


def preview(paths: list[str], name: str) -> str:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    tile = 200
    per_row = 3
    backgrounds = [(24, 26, 40), (70, 210, 110), (245, 245, 245)]
    rows = (len(paths) + per_row - 1) // per_row
    sheet = Image.new("RGB", (tile * per_row * len(backgrounds), tile * rows), (0, 0, 0))
    for index, path in enumerate(paths):
        art = Image.open(path).convert("RGBA").resize((tile, tile), Image.LANCZOS)
        row, column = divmod(index, per_row)
        for slot, colour in enumerate(backgrounds):
            cell = Image.new("RGBA", (tile, tile), colour + (255,))
            cell.alpha_composite(art)
            sheet.paste(cell.convert("RGB"), ((slot * per_row + column) * tile, row * tile))
    output = os.path.join(PREVIEW_DIR, name)
    sheet.save(output)
    return output


def main() -> int:
    args = sys.argv[1:]
    score = magenta_score
    if "--green" in args:
        score = green_score
        args.remove("--green")
    chroma_bg = CHROMA_BG
    if "--chroma" in args:
        position = args.index("--chroma")
        chroma_bg = float(args[position + 1])
        del args[position : position + 2]

    if args[:1] == ["--all"]:
        paths = []
        for pattern in ("*.png", "*.jfif", "*.jpg", "*.jpeg"):
            paths += glob.glob(os.path.join(MONSTERS, pattern))
        paths.sort()
        if not paths:
            print(f"No images in {os.path.relpath(MONSTERS, ROOT)} — put the generated files there first.")
            return 1
    else:
        paths = args
    if not paths:
        print(__doc__)
        return 1

    done = []
    for path in paths:
        done.append(cut(path, score, chroma_bg))
        print("ok", os.path.relpath(done[-1], ROOT), flush=True)
    for start in range(0, len(done), 9):
        sheet = preview(done[start : start + 9], f"monsters_{start // 9 + 1}.png")
        print("preview", os.path.relpath(sheet, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
