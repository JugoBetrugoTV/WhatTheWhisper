"""Generates WhatTheWhisper/Art/Icons.tga -- an 8x8 atlas of 64px line icons.

Icons are pure white with an alpha channel so the addon can tint any of them to
any theme colour at runtime with SetVertexColor.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402
from draw import Pen  # noqa: E402
from tga import write_tga  # noqa: E402

CELL = 64
COLS = 8
ROWS = 8
SS = 6          # supersample factor
W = 5.0         # default stroke width in 64-unit space
CLEAR = (0, 0, 0, 0)   # ImageDraw writes raw pixels, so this erases

ICONS = []


def icon(name):
    def deco(fn):
        ICONS.append((name, fn))
        return fn
    return deco


def rotated(pen_fn, angle, size=CELL, ss=SS):
    """Draw via pen_fn onto a temp layer then rotate it about the centre."""
    pad = size // 2
    img = Image.new("RGBA", ((size + pad * 2) * ss, (size + pad * 2) * ss), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    p = Pen(d, ss)
    p.d = d
    # shift origin so the caller can keep using 0..64 coordinates
    class Shifted(Pen):
        def __init__(self, draw, scale, dx, dy):
            super().__init__(draw, scale)
            self.dx, self.dy = dx, dy

        def line(self, x1, y1, x2, y2, w, fill=(255, 255, 255, 255), cap=True):
            super().line(x1 + self.dx, y1 + self.dy, x2 + self.dx, y2 + self.dy, w, fill, cap)

        def circle(self, cx, cy, r, fill=None, outline=None, w=0):
            super().circle(cx + self.dx, cy + self.dy, r, fill, outline, w)

        def rrect(self, x1, y1, x2, y2, r, fill=None, outline=None, w=0):
            super().rrect(x1 + self.dx, y1 + self.dy, x2 + self.dx, y2 + self.dy, r, fill, outline, w)

        def rect(self, x1, y1, x2, y2, fill=(255, 255, 255, 255)):
            super().rect(x1 + self.dx, y1 + self.dy, x2 + self.dx, y2 + self.dy, fill)

        def poly(self, pts, fill=(255, 255, 255, 255), outline=None, w=0):
            super().poly([(x + self.dx, y + self.dy) for (x, y) in pts], fill, outline, w)

        def arc(self, cx, cy, r, a0, a1, w, fill=(255, 255, 255, 255), steps=64):
            super().arc(cx + self.dx, cy + self.dy, r, a0, a1, w, fill, steps)

    pen_fn(Shifted(d, ss, pad, pad))
    img = img.rotate(angle, resample=Image.BICUBIC, center=((size / 2 + pad) * ss, (size / 2 + pad) * ss))
    return img.crop((pad * ss, pad * ss, (pad + size) * ss, (pad + size) * ss))


# ---------------------------------------------------------------- icons ----

@icon("close")
def _(p):
    p.line(21, 21, 43, 43, W)
    p.line(43, 21, 21, 43, W)


@icon("minimize")
def _(p):
    p.line(20, 32, 44, 32, W)


@icon("maximize")
def _(p):
    p.rrect(20, 20, 44, 44, 4, outline=(255, 255, 255, 255), w=W)


@icon("restore")
def _(p):
    p.rrect(20, 26, 40, 46, 4, outline=(255, 255, 255, 255), w=W)
    p.polyline([(26, 20), (44, 20), (44, 38)], W)


@icon("pin")
def _(p):
    p.circle(32, 25, 9, outline=(255, 255, 255, 255), w=W)
    p.line(32, 34, 32, 48, W)


@icon("pin_filled")
def _(p):
    p.circle(32, 25, 10, fill=(255, 255, 255, 255))
    p.line(32, 34, 32, 48, W + 1)


@icon("bell")
def _(p):
    p.arc(32, 31, 11, 180, 360, W)
    p.line(21, 31, 21, 40, W)
    p.line(43, 31, 43, 40, W)
    p.line(17, 41, 47, 41, W)
    p.arc(32, 44, 5, 10, 170, W)
    p.line(32, 16, 32, 20, W)


@icon("bell_off")
def _(p):
    p.arc(32, 31, 11, 180, 360, W)
    p.line(21, 31, 21, 40, W)
    p.line(43, 31, 43, 40, W)
    p.line(17, 41, 47, 41, W)
    p.arc(32, 44, 5, 10, 170, W)
    p.line(32, 16, 32, 20, W)
    p.line(15, 49, 49, 15, W + 4.5, fill=CLEAR)
    p.line(16, 48, 48, 16, W)


@icon("search")
def _(p):
    p.circle(29, 29, 11, outline=(255, 255, 255, 255), w=W)
    p.line(37, 37, 46, 46, W)


@icon("plus")
def _(p):
    p.line(32, 19, 32, 45, W)
    p.line(19, 32, 45, 32, W)


@icon("minus")
def _(p):
    p.line(19, 32, 45, 32, W)


@icon("check")
def _(p):
    p.polyline([(20, 33), (28, 42), (45, 22)], W)


@icon("check_double")
def _(p):
    p.polyline([(12, 33), (20, 42), (35, 23)], 4.2)
    p.polyline([(24, 33), (32, 42), (47, 23)], 8.4, fill=CLEAR)
    p.polyline([(24, 33), (32, 42), (47, 23)], 4.2)


@icon("chevron_down")
def _(p):
    p.polyline([(21, 27), (32, 39), (43, 27)], W)


@icon("chevron_up")
def _(p):
    p.polyline([(21, 39), (32, 27), (43, 39)], W)


@icon("chevron_left")
def _(p):
    p.polyline([(38, 21), (26, 32), (38, 43)], W)


@icon("chevron_right")
def _(p):
    p.polyline([(26, 21), (38, 32), (26, 43)], W)


@icon("dots")
def _(p):
    for x in (19, 32, 45):
        p.circle(x, 32, 3.6, fill=(255, 255, 255, 255))


@icon("dots_v")
def _(p):
    for y in (19, 32, 45):
        p.circle(32, y, 3.6, fill=(255, 255, 255, 255))


@icon("send")
def _(p):
    p.poly([(15, 47), (49, 32), (15, 17), (21, 32)])


@icon("arrow_up")
def _(p):
    p.line(32, 47, 32, 19, W)
    p.polyline([(21, 30), (32, 18), (43, 30)], W)


@icon("arrow_down")
def _(p):
    p.line(32, 17, 32, 45, W)
    p.polyline([(21, 34), (32, 46), (43, 34)], W)


@icon("arrow_left")
def _(p):
    p.line(46, 32, 20, 32, W)
    p.polyline([(30, 21), (18, 32), (30, 43)], W)


@icon("arrow_right")
def _(p):
    p.line(18, 32, 44, 32, W)
    p.polyline([(34, 21), (46, 32), (34, 43)], W)


@icon("smiley")
def _(p):
    p.circle(32, 32, 15, outline=(255, 255, 255, 255), w=4.2)
    p.circle(26, 28, 2.2, fill=(255, 255, 255, 255))
    p.circle(38, 28, 2.2, fill=(255, 255, 255, 255))
    p.arc(32, 32, 8, 25, 155, 3.4)


@icon("sliders")
def _(p):
    for y, kx in ((22, 27), (32, 39), (42, 23)):
        p.line(17, y, 47, y, 3.4)
        p.circle(kx, y, 5.2, fill=(255, 255, 255, 255))


@icon("gear")
def _(p):
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        x1, y1 = 32 + math.cos(a) * 10, 32 + math.sin(a) * 10
        x2, y2 = 32 + math.cos(a) * 18, 32 + math.sin(a) * 18
        p.line(x1, y1, x2, y2, 7.5)
    p.circle(32, 32, 14, fill=(255, 255, 255, 255))
    p.circle(32, 32, 7.2, fill=CLEAR)


@icon("trash")
def _(p):
    p.line(16, 23, 48, 23, W)
    p.polyline([(26, 23), (26, 16), (38, 16), (38, 23)], W - 0.8)
    p.rrect(22, 28, 42, 49, 3, outline=(255, 255, 255, 255), w=W - 0.5)
    p.line(29, 34, 29, 43, 3.2)
    p.line(35, 34, 35, 43, 3.2)


@icon("copy")
def _(p):
    p.rrect(24, 15, 48, 39, 4, outline=(255, 255, 255, 255), w=W - 0.5)
    p.rrect(16, 25, 40, 49, 4, outline=(255, 255, 255, 255), w=W - 0.5)


@icon("person")
def _(p):
    p.circle(32, 24, 8, outline=(255, 255, 255, 255), w=W)
    p.arc(32, 52, 14, 200, 340, W)


@icon("person_plus")
def _(p):
    p.circle(26, 24, 8, outline=(255, 255, 255, 255), w=W - 0.4)
    p.arc(26, 52, 14, 205, 335, W - 0.4)
    p.line(48, 24, 48, 38, W - 0.6)
    p.line(41, 31, 55, 31, W - 0.6)


@icon("users")
def _(p):
    p.circle(25, 25, 7.5, outline=(255, 255, 255, 255), w=W - 0.6)
    p.arc(25, 51, 13, 205, 335, W - 0.6)
    p.arc(44, 24, 7.5, 250, 470, W - 0.6)
    p.arc(44, 51, 13, 285, 340, W - 0.6)


@icon("export")
def _(p):
    p.polyline([(18, 32), (18, 48), (46, 48), (46, 32)], W)
    p.line(32, 41, 32, 18, W)
    p.polyline([(24, 26), (32, 17), (40, 26)], W)


@icon("grid")
def _(p):
    for x in (17, 35):
        for y in (17, 35):
            p.rrect(x, y, x + 12, y + 12, 3, outline=(255, 255, 255, 255), w=W - 0.8)


@icon("popout")
def _(p):
    p.polyline([(40, 17), (17, 17), (17, 47), (47, 47), (47, 26)], W)
    p.line(33, 31, 48, 16, W)
    p.polyline([(38, 15), (49, 15), (49, 26)], W - 0.6)


@icon("clock")
def _(p):
    p.circle(32, 32, 14, outline=(255, 255, 255, 255), w=W)
    p.line(32, 32, 32, 22, W - 0.6)
    p.line(32, 32, 40, 36, W - 0.6)


@icon("globe")
def _(p):
    p.circle(32, 32, 14, outline=(255, 255, 255, 255), w=4.2)
    p.line(19.5, 32, 44.5, 32, 3.2)
    p.ellipse(32, 32, 6.6, 13.9, outline=(255, 255, 255, 255), w=3.0)


@icon("star")
def _(p):
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = 17 if i % 2 == 0 else 7.4
        pts.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    p.polyline(pts + [pts[0]], 3.6)


@icon("star_filled")
def _(p):
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = 17 if i % 2 == 0 else 7.4
        pts.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    p.poly(pts)


@icon("block")
def _(p):
    p.circle(32, 32, 14, outline=(255, 255, 255, 255), w=W)
    p.line(22, 22, 42, 42, W)


@icon("info")
def _(p):
    p.circle(32, 32, 15, fill=(255, 255, 255, 255))
    p.circle(32, 23.5, 2.6, fill=CLEAR)
    p.line(32, 30.5, 32, 42, 4.4, fill=CLEAR)


@icon("warning")
def _(p):
    p.poly([(32, 13), (51, 48), (13, 48)])
    p.polyline([(32, 13), (51, 48), (13, 48), (32, 13)], 7.0)
    p.line(32, 28, 32, 38, 4.4, fill=CLEAR)
    p.circle(32, 43.5, 2.6, fill=CLEAR)


@icon("message")
def _(p):
    p.rrect(15, 17, 49, 42, 7, outline=(255, 255, 255, 255), w=W)
    p.poly([(24, 40), (24, 51), (35, 41)])


@icon("message_plus")
def _(p):
    p.rrect(15, 17, 49, 42, 7, outline=(255, 255, 255, 255), w=W - 0.4)
    p.poly([(23, 40), (23, 51), (34, 41)])
    p.line(32, 23, 32, 36, W - 0.6)
    p.line(25.5, 29.5, 38.5, 29.5, W - 0.6)


@icon("filter")
def _(p):
    p.line(17, 22, 47, 22, W)
    p.line(23, 32, 41, 32, W)
    p.line(28, 42, 36, 42, W)


@icon("eye")
def _(p):
    p.arc(32, 44, 22, 220, 320, W - 0.6)
    p.arc(32, 20, 22, 40, 140, W - 0.6)
    p.circle(32, 32, 6, outline=(255, 255, 255, 255), w=W - 0.8)


@icon("lock")
def _(p):
    p.rrect(19, 30, 45, 48, 4, outline=(255, 255, 255, 255), w=W - 0.4)
    p.arc(32, 30, 9, 180, 360, W - 0.4)
    p.circle(32, 39, 3, fill=(255, 255, 255, 255))


@icon("refresh")
def _(p):
    p.arc(32, 32, 13, 60, 340, W - 0.4)
    p.poly([(36, 16), (48, 21), (37, 27)])


@icon("dot")
def _(p):
    p.circle(32, 32, 10, fill=(255, 255, 255, 255))


@icon("logo")
def _(p):
    p.rrect(10, 12, 54, 44, 12, fill=(255, 255, 255, 255))
    p.poly([(20, 42), (20, 55), (34, 43)])
    for x in (23, 32, 41):
        p.circle(x, 28, 3.4, fill=(0, 0, 0, 0))


@icon("volume")
def _(p):
    p.poly([(16, 26), (24, 26), (34, 17), (34, 47), (24, 38), (16, 38)])
    p.arc(34, 32, 10, -55, 55, W - 1.2)
    p.arc(34, 32, 16, -50, 50, W - 1.2)


@icon("volume_off")
def _(p):
    p.poly([(14, 26), (22, 26), (32, 17), (32, 47), (22, 38), (14, 38)])
    p.line(39, 25, 51, 39, W - 0.6)
    p.line(51, 25, 39, 39, W - 0.6)


@icon("edit")
def _(p):
    p.poly([(17, 47), (20, 38), (41, 17), (47, 23), (26, 44)])
    p.line(38, 20, 44, 26, W - 1.4, fill=(0, 0, 0, 0))


@icon("x_circle")
def _(p):
    p.circle(32, 32, 14, outline=(255, 255, 255, 255), w=W - 0.4)
    p.line(26, 26, 38, 38, W - 0.8)
    p.line(38, 26, 26, 38, W - 0.8)


@icon("check_circle")
def _(p):
    p.circle(32, 32, 14, outline=(255, 255, 255, 255), w=W - 0.4)
    p.polyline([(25, 32), (30, 38), (40, 25)], W - 0.8)


@icon("hourglass")
def _(p):
    p.line(21, 17, 43, 17, W - 0.6)
    p.line(21, 47, 43, 47, W - 0.6)
    p.polyline([(23, 17), (23, 24), (32, 32), (23, 40), (23, 47)], W - 1.0)
    p.polyline([(41, 17), (41, 24), (32, 32), (41, 40), (41, 47)], W - 1.0)


@icon("sort")
def _(p):
    p.line(18, 21, 46, 21, W - 0.6)
    p.line(18, 32, 38, 32, W - 0.6)
    p.line(18, 43, 30, 43, W - 0.6)


@icon("keyboard")
def _(p):
    p.rrect(13, 22, 51, 44, 4, outline=(255, 255, 255, 255), w=W - 1.2)
    for x in (20, 27, 34, 41):
        p.circle(x, 29, 1.9, fill=(255, 255, 255, 255))
    p.circle(45, 29, 1.9, fill=(255, 255, 255, 255))
    p.line(24, 37, 40, 37, 3.2)


def main():
    atlas = Image.new("RGBA", (CELL * COLS, CELL * ROWS), (255, 255, 255, 0))
    names = []
    for idx, (name, fn) in enumerate(ICONS):
        if idx >= COLS * ROWS:
            raise SystemExit("atlas overflow: %d icons" % len(ICONS))
        cell = Image.new("RGBA", (CELL * SS, CELL * SS), (255, 255, 255, 0))
        d = ImageDraw.Draw(cell)
        fn(Pen(d, SS))
        cell = cell.resize((CELL, CELL), Image.LANCZOS)
        # keep RGB white everywhere so bilinear filtering cannot darken edges
        r, g, b, a = cell.split()
        cell = Image.merge("RGBA", (
            Image.new("L", cell.size, 255),
            Image.new("L", cell.size, 255),
            Image.new("L", cell.size, 255),
            a,
        ))
        col, row = idx % COLS, idx // COLS
        atlas.paste(cell, (col * CELL, row * CELL))
        names.append(name)

    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "WhatTheWhisper", "Art")
    out_dir = os.path.normpath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    write_tga(os.path.join(out_dir, "Icons.tga"), atlas)
    atlas.save(os.path.join(out_dir, "_preview_icons.png"))

    # Emit the Lua coordinate table so the atlas and the addon can never drift.
    lines = ["-- Generated by Tools/gen_icons.py -- do not edit by hand.",
             "local _, ns = ...", "", "ns.ICON_ATLAS = {", ]
    step = 1.0 / COLS
    for i, name in enumerate(names):
        col, row = i % COLS, i // COLS
        lines.append("\t%s = { %.6f, %.6f, %.6f, %.6f }," % (
            name, col * step, (col + 1) * step, row * (1.0 / ROWS), (row + 1) * (1.0 / ROWS)))
    lines.append("}")
    lines.append("")
    with open(os.path.join(out_dir, "..", "UI", "IconAtlas.lua"), "w") as fh:
        fh.write("\n".join(lines))
    print("wrote %d icons" % len(names))


main()
