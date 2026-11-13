"""Generate the torn-paper puzzle shape library.

Outputs (into the --out folder):
  tornMask4.png, tornMask6.png, tornMask9.png, tornMask12.png
      One mask atlas per piece count. White where a piece is, transparent
      elsewhere. Upload each as a CodeMod image resource of the same name.
  TornPuzzleShapes.lua
      The data the widget needs for every piece: where it sits in the image,
      where its mask sits in the atlas, its outline (for hit-testing), and the
      seams it shares with neighbours (for snapping and tape).
  preview_<count>.png
      Every variant's outlines drawn on a grid, for eyeballing the tears.

Coordinates: shapes are made in "unit" space, x right and y DOWN, 0..1 across the
whole image. The Lua side converts to texture UVs (y up) where it needs them.
Seams between two pieces are generated once and used by both pieces, so
neighbours always fit exactly. Outer edges stay straight, like a sheet's edge.

Run:  python make_torn_masks.py --out <folder> [--seed 1]
"""

import argparse
import math
import os
import random

from PIL import Image, ImageDraw

# piece count -> (columns, rows)
LAYOUTS = {4: (2, 2), 6: (3, 2), 9: (3, 3), 12: (4, 3)}
VARIANTS = 3

# Mask resolution: the whole image is RES x RES mask pixels. Boards display at
# up to ~720px wide, so this keeps edges crisp without bloating the atlases.
RES = 768
SUPERSAMPLE = 4
ATLAS_WIDTH = 2048
ATLAS_PAD = 8

# Tear roughness: first displacement as a fraction of the seam's length, and
# how much each halving keeps. Depth 5 gives 33 points per seam.
TEAR_AMPLITUDE = 0.13
TEAR_ROUGHNESS = 0.5
TEAR_DEPTH = 5

# How far interior grid points wander, as a fraction of a cell.
JITTER = 0.3

# Outline points kept for hit-testing (every Nth point of the full outline).
HIT_STRIDE = 2


def torn_line(a, b, rng):
    """Ragged polyline from a to b by midpoint displacement (ends fixed)."""
    pts = [a, b]
    length = math.dist(a, b)
    amp = TEAR_AMPLITUDE * length
    for _ in range(TEAR_DEPTH):
        nxt = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
            dx, dy = q[0] - p[0], q[1] - p[1]
            seg = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / seg, dx / seg
            off = rng.uniform(-amp, amp)
            nxt.append((mx + nx * off, my + ny * off))
            nxt.append(q)
        pts = nxt
        amp *= TEAR_ROUGHNESS
    return pts


def make_variant(cols, rows, rng):
    """Return (pieces, seams) for one tear pattern.

    pieces[k] = {"col", "row", "outline": [(x, y), ...]} in unit space.
    seams = [{"a": k1, "b": k2, "points": [...]}] for every interior edge.
    """
    # Grid points; interior ones jitter freely, edge ones only slide along the edge.
    grid = {}
    for j in range(rows + 1):
        for i in range(cols + 1):
            x, y = i / cols, j / rows
            jx = rng.uniform(-JITTER, JITTER) / cols
            jy = rng.uniform(-JITTER, JITTER) / rows
            if i in (0, cols):
                jx = 0
            if j in (0, rows):
                jy = 0
            grid[(i, j)] = (x + jx, y + jy)

    def edge(p, q, interior):
        a, b = grid[p], grid[q]
        return torn_line(a, b, rng) if interior else [a, b]

    # Horizontal edges h[(i, j)] run from (i, j) to (i+1, j); vertical v[(i, j)]
    # from (i, j) to (i, j+1). Interior edges are torn, border edges straight.
    h = {}
    for j in range(rows + 1):
        for i in range(cols):
            h[(i, j)] = edge((i, j), (i + 1, j), 0 < j < rows)
    v = {}
    for j in range(rows):
        for i in range(cols + 1):
            v[(i, j)] = edge((i, j), (i, j + 1), 0 < i < cols)

    def index(i, j):
        return j * cols + i

    pieces = []
    for j in range(rows):
        for i in range(cols):
            top = h[(i, j)]
            right = v[(i + 1, j)]
            bottom = list(reversed(h[(i, j + 1)]))
            left = list(reversed(v[(i, j)]))
            # Drop each edge's last point: it repeats the next edge's first.
            edges = [top[:-1], right[:-1], bottom[:-1], left[:-1]]
            outline = edges[0] + edges[1] + edges[2] + edges[3]
            # The hit-test outline thins each edge separately so every corner
            # (an edge's first point) survives; thinning the whole outline at
            # once skipped corners and cut them off.
            hit = []
            for e in edges:
                hit += e[::HIT_STRIDE]
            pieces.append({"col": i, "row": j, "outline": outline, "hit": hit})

    seams = []
    for j in range(1, rows):
        for i in range(cols):
            seams.append({"a": index(i, j - 1), "b": index(i, j), "points": h[(i, j)]})
    for j in range(rows):
        for i in range(1, cols):
            seams.append({"a": index(i - 1, j), "b": index(i, j), "points": v[(i, j)]})
    return pieces, seams


def rasterize(outline):
    """Mask image for one piece plus its pixel rect (x0, y0, x1, y1) in RES space."""
    xs = [p[0] * RES for p in outline]
    ys = [p[1] * RES for p in outline]
    x0, y0 = math.floor(min(xs)) - 1, math.floor(min(ys)) - 1
    x1, y1 = math.ceil(max(xs)) + 1, math.ceil(max(ys)) + 1
    w, h = x1 - x0, y1 - y0
    big = Image.new("L", (w * SUPERSAMPLE, h * SUPERSAMPLE), 0)
    pts = [((x - x0) * SUPERSAMPLE, (y - y0) * SUPERSAMPLE) for x, y in zip(xs, ys)]
    ImageDraw.Draw(big).polygon(pts, fill=255)
    alpha = big.resize((w, h), Image.LANCZOS)
    img = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    img.putalpha(alpha)
    return img, (x0, y0, x1, y1)


def pack(images):
    """Shelf-pack images into one atlas; return (atlas, [(ax, ay)] per image)."""
    order = sorted(range(len(images)), key=lambda k: -images[k].height)
    spots = [None] * len(images)
    x = y = ATLAS_PAD
    shelf = 0
    for k in order:
        im = images[k]
        if x + im.width + ATLAS_PAD > ATLAS_WIDTH:
            x = ATLAS_PAD
            y += shelf + ATLAS_PAD
            shelf = 0
        spots[k] = (x, y)
        x += im.width + ATLAS_PAD
        shelf = max(shelf, im.height)
    height = y + shelf + ATLAS_PAD
    atlas = Image.new("RGBA", (ATLAS_WIDTH, height), (255, 255, 255, 0))
    for k, im in enumerate(images):
        atlas.paste(im, spots[k])
    return atlas, spots


def fmt(n):
    s = f"{n:.4f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


def seam_info(seam):
    """Midpoint and direction (degrees, unit space) of a seam, for tape placement."""
    pts = seam["points"]
    mid = pts[len(pts) // 2]
    a, b = pts[0], pts[-1]
    angle = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
    return mid, angle


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rng = random.Random(args.seed)

    lua = [
        "local mod = dmhub.GetModLoading()",
        "",
        "--GENERATED by tools/tornpuzzle/make_torn_masks.py -- do not hand-edit; re-run the",
        "--script instead. Shape library for the torn-paper puzzle. Unit space: x right,",
        "--y DOWN, 0..1 across the whole image. Per piece: bbox = where it sits in the",
        "--image, atlas = its mask's rect in the atlas image (texture UVs, y UP, ready for",
        "--bgimageMaskRect), poly = flat x,y outline for hit-testing. Per seam: the two",
        "--pieces it joins, its midpoint and its direction in degrees (for tape).",
        "",
        "---@class TornPuzzleShapePiece",
        "---@field col integer",
        "---@field row integer",
        "---@field bbox number[]",
        "---@field atlas number[]",
        "---@field poly number[]",
        "",
        "---@class TornPuzzleShapeSeam",
        "---@field a integer",
        "---@field b integer",
        "---@field mid number[]",
        "---@field angle number",
        "",
        "---@class TornPuzzleShapeVariant",
        "---@field pieces TornPuzzleShapePiece[]",
        "---@field seams TornPuzzleShapeSeam[]",
        "",
        "---@class TornPuzzleShapeSet",
        "---@field cols integer",
        "---@field rows integer",
        "---@field atlas string",
        "---@field variants TornPuzzleShapeVariant[]",
        "",
        "---@type table<integer, TornPuzzleShapeSet>",
        "TornPuzzleShapes = {",
    ]

    for count, (cols, rows) in LAYOUTS.items():
        variants = [make_variant(cols, rows, rng) for _ in range(VARIANTS)]

        images, rects = [], []
        for pieces, _ in variants:
            for p in pieces:
                img, rect = rasterize(p["outline"])
                images.append(img)
                rects.append(rect)
        atlas, spots = pack(images)
        atlas.save(os.path.join(args.out, f"tornMask{count}.png"), optimize=True)
        aw, ah = atlas.size

        lua.append(f"    [{count}] = {{")
        lua.append(f"        cols = {cols}, rows = {rows}, atlas = \"tornMask{count}\",")
        lua.append("        variants = {")
        k = 0
        for pieces, seams in variants:
            lua.append("            {")
            lua.append("                pieces = {")
            for p in pieces:
                x0, y0, x1, y1 = rects[k]
                ax, ay = spots[k]
                k += 1
                bbox = [x0 / RES, y0 / RES, x1 / RES, y1 / RES]
                w, h = x1 - x0, y1 - y0
                # atlas rect as texture UVs: x1, y1 (bottom), x2, y2 (top)
                atl = [ax / aw, 1 - (ay + h) / ah, (ax + w) / aw, 1 - ay / ah]
                poly = []
                for x, y in p["hit"]:
                    poly += [x, y]
                lua.append(
                    "                    { col = %d, row = %d, bbox = {%s}, atlas = {%s},"
                    % (p["col"], p["row"], ", ".join(fmt(n) for n in bbox), ", ".join(fmt(n) for n in atl))
                )
                lua.append("                      poly = {%s} }," % ", ".join(fmt(n) for n in poly))
            lua.append("                },")
            lua.append("                seams = {")
            for s in seams:
                mid, angle = seam_info(s)
                lua.append(
                    "                    { a = %d, b = %d, mid = {%s, %s}, angle = %s },"
                    % (s["a"] + 1, s["b"] + 1, fmt(mid[0]), fmt(mid[1]), fmt(angle))
                )
            lua.append("                },")
            lua.append("            },")
        lua.append("        },")
        lua.append("    },")

        # Preview: each variant's outlines, side by side.
        cell = 300
        prev = Image.new("RGB", (cell * VARIANTS, cell), (40, 40, 40))
        draw = ImageDraw.Draw(prev)
        for vi, (pieces, _) in enumerate(variants):
            for p in pieces:
                pts = [(vi * cell + 10 + x * (cell - 20), 10 + y * (cell - 20)) for x, y in p["outline"]]
                draw.polygon(pts, outline=(230, 220, 200))
        prev.save(os.path.join(args.out, f"preview_{count}.png"))
        print(f"{count} pieces: atlas {aw}x{ah}, {len(images)} masks")

    lua.append("}")
    lua.append("")
    with open(os.path.join(args.out, "TornPuzzleShapes.lua"), "w", encoding="ascii", newline="\n") as f:
        f.write("\n".join(lua))


if __name__ == "__main__":
    main()
