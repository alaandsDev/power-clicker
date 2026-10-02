"""
remove_checker.py — turns AI images with a *painted* checkerboard "transparency"
into real transparent PNGs, keeping soft glows.

Algorithm (v4, checker-texture detection):
  A painted checker is periodic: shifting the image by one square (P px)
  swaps light/dark squares, shifting by 2P lands on the same tone. Art is not
  periodic. So for every pixel:
      T = median over 4 directions of ( |I - I(shift P)| - |I - I(shift 2P)| )
  On bare checker T ≈ Δ (tone contrast); under a glow of opacity a it is
  Δ·(1 - a); on solid art ≈ 0. Hence alpha = 1 - T/Δ, straight from the image
  and independent of the checker's colours (light or dark checkers both work).
  1. Estimate P and the tones from the image border.
  2. Compute alpha from the texture (PIL ImageChops).
  2b. Neutral pixels within the tone range, flooded from the border, are
     plain background (square edges, irregular hand-painted patches).
  3. Only pixels connected to the border through "not solid" pixels get alpha
     < 1 (art interiors can never be eaten).
  4. Un-blend their colour from the tone under them: F = B + (C - B) / alpha.
  4b. Halo cleanup: median on alpha erases thin grid lines, tiny islands go.
  5. Crop to the art, pad, fit into 512x512, save PNG with alpha.

Usage:
  python tools/remove_checker.py <file.jpg> [...]
  python tools/remove_checker.py --all   (icons, pets, eggs, badge, logo)
Outputs <same folder>/<name>.png ; previews in art/preview/.
"""

from __future__ import annotations

import glob
import os
import statistics
import sys
from collections import deque

from PIL import Image, ImageChops, ImageFilter, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW_DIR = os.path.join(ROOT, "art", "preview")

SIZE = 512
PADDING = 0.05
BAND = 40  # px strip along the border used to measure the checker
MIN_SQUARE, MAX_SQUARE = 4, 80
SQUARE_SCORE = 0.85  # smallest shift reaching this share of the best score wins
SOLID_ALPHA = 0.85  # texture alpha at which a pixel blocks the background flood
SOLID_DILATE = 3
ALPHA_FLOOR = 0.15  # below: pure background (JPEG noise)
ALPHA_CEIL = 0.95  # above: fully opaque
TEXTURE_BLUR = 1
NEUTRAL_SAT = 26  # max-min channel spread of a checker-coloured pixel
TONE_MARGIN = 16  # luma slack around the checker tones (JPEG, painted drift)
HALO_MEDIAN = 5  # median window that erases 1-2 px checker grid lines in glows
SPECK_ALPHA = 24  # alpha above which a pixel belongs to an island
HALO_BLUR = 1.5  # glows are smooth; blur hides the leftover checker mottling
MIN_ISLAND = 1500  # islands smaller than this (px, 1024 source) are stray checker bits


def flood(width: int, height: int, passable: bytes) -> bytearray:
    reached = bytearray(width * height)
    queue: deque[int] = deque()

    def seed(index: int):
        if passable[index] and not reached[index]:
            reached[index] = 1
            queue.append(index)

    for x in range(width):
        seed(x)
        seed((height - 1) * width + x)
    for y in range(height):
        seed(y * width)
        seed(y * width + width - 1)
    total = width * height
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
    return reached


def shift_diff(luma: Image.Image, dx: int, dy: int) -> Image.Image:
    return ImageChops.difference(luma, ImageChops.offset(luma, dx, dy))


def border_bands(image: Image.Image) -> list[Image.Image]:
    w, h = image.size
    return [image.crop((0, 0, w, BAND)), image.crop((0, h - BAND, w, h))]


def square_size(luma: Image.Image) -> tuple[int, float]:
    def mean_shift(s: int) -> float:
        total = 0.0
        for band in border_bands(luma):
            w = band.width
            total += ImageStat.Stat(ImageChops.difference(band.crop((0, 0, w - s, BAND)), band.crop((s, 0, w, BAND)))).mean[0]
        return total / 2

    means = {s: mean_shift(s) for s in range(MIN_SQUARE, 2 * MAX_SQUARE + 1)}
    scores = {s: means[s] - means[2 * s] for s in range(MIN_SQUARE, MAX_SQUARE + 1)}
    best = max(scores.values())
    size = min(s for s, score in scores.items() if score >= best * SQUARE_SCORE)
    return size, max(means[size], 1.0)


def checker_tones(img: Image.Image) -> tuple[tuple[float, ...], tuple[float, ...]]:
    samples = []
    for band in border_bands(img):
        for r, g, b in band.get_flattened_data():
            if max(r, g, b) - min(r, g, b) < 24:
                samples.append((r, g, b))
    if not samples:
        return (255.0, 255.0, 255.0), (204.0, 204.0, 204.0)
    brightness = sorted(sum(s) / 3 for s in samples)
    split = (brightness[len(brightness) // 6] + brightness[-len(brightness) // 6]) / 2

    def median_of(group):
        return tuple(float(statistics.median(channel)) for channel in zip(*group))

    lights = [s for s in samples if sum(s) / 3 > split]
    darks = [s for s in samples if sum(s) / 3 <= split]
    light = median_of(lights) if lights else (255.0, 255.0, 255.0)
    return light, median_of(darks) if darks else light


def texture(luma: Image.Image, p: int) -> Image.Image:
    per_direction = []
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        near = shift_diff(luma, dx * p, dy * p)
        far = shift_diff(luma, dx * 2 * p, dy * 2 * p)
        per_direction.append(ImageChops.subtract(near, far))
    a, b, c, d = per_direction
    high = ImageChops.lighter(ImageChops.lighter(a, b), ImageChops.lighter(c, d))
    low = ImageChops.darker(ImageChops.darker(a, b), ImageChops.darker(c, d))
    # median of 4 = (sum - max - min) / 2
    median = Image.new("L", luma.size)
    median.putdata(
        [
            (w + x + y + z - hi - lo) // 2
            for w, x, y, z, hi, lo in zip(a.get_flattened_data(), b.get_flattened_data(), c.get_flattened_data(), d.get_flattened_data(), high.get_flattened_data(), low.get_flattened_data())
        ]
    )
    return median.filter(ImageFilter.BoxBlur(TEXTURE_BLUR))


def clean_alpha(alpha: Image.Image, outside: bytearray, width: int, height: int) -> Image.Image:
    """Halo only: drop thin checker grid lines (median) and tiny floating specks."""
    median = (
        alpha.filter(ImageFilter.MedianFilter(HALO_MEDIAN))
        .filter(ImageFilter.GaussianBlur(HALO_BLUR))
        .get_flattened_data()
    )
    values = list(alpha.get_flattened_data())
    for i in range(width * height):
        if outside[i] and median[i] < values[i]:
            values[i] = median[i]
    seen = bytearray(width * height)
    for start in range(width * height):
        if values[start] <= SPECK_ALPHA or seen[start]:
            continue
        component = [start]
        seen[start] = 1
        cursor = 0
        while cursor < len(component):
            i = component[cursor]
            cursor += 1
            x = i % width
            for n in (i - 1 if x > 0 else -1, i + 1 if x + 1 < width else -1, i - width, i + width):
                if 0 <= n < width * height and not seen[n] and values[n] > SPECK_ALPHA:
                    seen[n] = 1
                    component.append(n)
        if len(component) < MIN_ISLAND:
            for i in component:
                values[i] = 0
    cleaned = Image.new("L", (width, height))
    cleaned.putdata(values)
    return cleaned


def process(path: str) -> str:
    img = Image.open(path).convert("RGB")
    width, height = img.size
    luma = img.convert("L")
    p, contrast = square_size(luma)
    light, dark = checker_tones(img)
    alphas = [max(0.0, min(1.0, 1 - t / contrast)) for t in texture(luma, p).get_flattened_data()]

    # checker-coloured: neutral and within the tone range (catches square edges
    # and the irregular patches where the painted grid isn't periodic)
    low_luma = sum(dark) / 3 - TONE_MARGIN
    high_luma = sum(light) / 3 + TONE_MARGIN
    checkerish = bytearray(
        1 if max(px) - min(px) <= NEUTRAL_SAT and low_luma <= sum(px) / 3 <= high_luma else 0
        for px in img.get_flattened_data()
    )
    background = flood(width, height, checkerish)

    solid = Image.new("L", (width, height))
    solid.putdata([255 if a >= SOLID_ALPHA and not background[i] else 0 for i, a in enumerate(alphas)])
    solid = solid.filter(ImageFilter.MaxFilter(SOLID_DILATE))
    outside = flood(
        width,
        height,
        bytes(1 if background[i] or not v else 0 for i, v in enumerate(solid.get_flattened_data())),
    )

    source = img.load()
    lum = luma.load()
    out = Image.new("RGBA", (width, height))
    out_pixels = out.load()
    for y in range(height):
        for x in range(width):
            index = y * width + x
            colour = source[x, y]
            if not outside[index]:
                out_pixels[x, y] = colour + (255,)
                continue
            alpha = alphas[index]
            if checkerish[index] or alpha < ALPHA_FLOOR:
                out_pixels[x, y] = (0, 0, 0, 0)
            elif alpha >= ALPHA_CEIL:
                out_pixels[x, y] = colour + (255,)
            else:
                neighbours = (lum[(x + p) % width, y] + lum[(x - p) % width, y]) / 2
                back = light if lum[x, y] >= neighbours else dark
                fixed = tuple(int(max(0, min(255, bc + (c - bc) / alpha))) for c, bc in zip(colour, back))
                out_pixels[x, y] = fixed + (int(alpha * 255),)

    out.putalpha(clean_alpha(out.getchannel("A"), outside, width, height))
    bbox = out.getchannel("A").point(lambda value: 255 if value > 40 else 0).getbbox()
    if bbox:
        out = out.crop(bbox)
    inner = int(SIZE * (1 - 2 * PADDING))
    out.thumbnail((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.paste(out, ((SIZE - out.width) // 2, (SIZE - out.height) // 2), out)
    out_path = os.path.splitext(path)[0] + ".png"
    canvas.save(out_path, optimize=True)
    return out_path


def preview(pngs: list[str], name: str) -> str:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    tile = 200
    per_row = 3
    backgrounds = [(24, 26, 40), (70, 210, 110), (245, 245, 245)]
    rows = (len(pngs) + per_row - 1) // per_row
    sheet = Image.new("RGB", (tile * per_row * len(backgrounds), tile * rows), (0, 0, 0))
    for i, png in enumerate(pngs):
        art = Image.open(png).convert("RGBA").resize((tile, tile), Image.LANCZOS)
        r, c = divmod(i, per_row)
        for k, color in enumerate(backgrounds):
            cell = Image.new("RGBA", (tile, tile), color + (255,))
            cell.alpha_composite(art)
            sheet.paste(cell.convert("RGB"), ((k * per_row + c) * tile, r * tile))
    out = os.path.join(PREVIEW_DIR, name)
    sheet.save(out)
    return out


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["--all"]:
        paths = []
        for folder in ("icons", "pets", "eggs"):
            paths += sorted(glob.glob(os.path.join(ROOT, "art", "final", folder, "*.jpg")))
        paths += [os.path.join(ROOT, "art", "final", "branding", n) for n in ("badge_vip.jpg", "logo_title.jpg")]
    else:
        paths = args
    outputs = []
    for path in paths:
        outputs.append(process(path))
        print("ok", os.path.relpath(outputs[-1], ROOT), flush=True)
    for start in range(0, len(outputs), 9):
        chunk = outputs[start : start + 9]
        print("preview", os.path.relpath(preview(chunk, f"preview_{start // 9 + 1}.png"), ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
