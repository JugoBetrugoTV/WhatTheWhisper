"""Generates WhatTheWhisper/Art/Emoji.tga -- an 8x8 atlas of 64px colour emoji.

WoW ships no emoji glyphs in any of its fonts and none of the four target
clients has an emoji atlas we could borrow, so the addon carries its own. These
are drawn as flat vector art so they read cleanly at the 14-16px they are
rendered at inside message text.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402
from draw import Pen  # noqa: E402
from tga import write_tga, bleed  # noqa: E402

CELL, COLS, ROWS, SS = 64, 8, 8, 6

FACE   = (255, 204, 77, 255)
INK    = (102, 69, 0, 255)
WHITE  = (255, 255, 255, 255)
TONGUE = (229, 89, 106, 255)
BLUSH  = (244, 144, 138, 200)
TEAR   = (93, 173, 236, 255)
RED    = (221, 46, 68, 255)
GOLD   = (255, 172, 51, 255)
GREY   = (204, 213, 221, 255)
GREEN  = (120, 177, 89, 255)
BLUE   = (85, 172, 238, 255)
PURPLE = (170, 142, 214, 255)
BROWN  = (141, 96, 60, 255)
DARK   = (49, 55, 61, 255)

EMOJI = []


def emoji(name):
    def deco(fn):
        EMOJI.append((name, fn))
        return fn
    return deco


def face(p, colour=FACE):
    p.circle(32, 32, 29, fill=colour)


def eyes_dots(p, y=26, r=3.6, dx=9.5):
    p.circle(32 - dx, y, r, fill=INK)
    p.circle(32 + dx, y, r, fill=INK)


def eyes_closed(p, y=26, dx=9.5, up=True):
    for s in (-1, 1):
        if up:
            p.arc(32 + s * dx, y + 2.5, 6, 200, 340, 3.2, fill=INK)
        else:
            p.arc(32 + s * dx, y - 2.5, 6, 20, 160, 3.2, fill=INK)


def smile(p, r=13, a0=25, a1=155, w=3.4):
    p.arc(32, 31, r, a0, a1, w, fill=INK)


def open_mouth(p, cy=40, rx=12, ry=9, teeth=False):
    p.ellipse(32, cy, rx, ry, fill=INK)
    if teeth:
        p.d.pieslice(
            [(32 - rx) * p.s, (cy - ry) * p.s, (32 + rx) * p.s, (cy + ry) * p.s],
            180, 360, fill=WHITE)


# ------------------------------------------------------------- smileys ----

@emoji("smile")
def _(p):
    face(p); eyes_dots(p); smile(p)


@emoji("grin")
def _(p):
    face(p); eyes_dots(p, y=24)
    open_mouth(p, cy=38, rx=15, ry=11, teeth=True)


@emoji("laugh")
def _(p):
    face(p); eyes_closed(p, y=25)
    open_mouth(p, cy=39, rx=14, ry=11, teeth=True)


@emoji("joy")
def _(p):
    face(p); eyes_closed(p, y=25)
    open_mouth(p, cy=39, rx=14, ry=11, teeth=True)
    p.poly([(11, 27), (16, 25), (16, 38)], fill=TEAR)
    p.poly([(53, 27), (48, 25), (48, 38)], fill=TEAR)


@emoji("wink")
def _(p):
    face(p)
    p.circle(22.5, 26, 3.6, fill=INK)
    p.arc(41.5, 28.5, 6, 200, 340, 3.2, fill=INK)
    smile(p)


@emoji("tongue")
def _(p):
    face(p); eyes_dots(p, y=25)
    p.d.pieslice([16 * p.s, 27 * p.s, 48 * p.s, 47 * p.s], 0, 180, fill=INK)
    p.rrect(25, 38, 39, 51, 6, fill=TONGUE)
    p.rect(25, 38, 39, 41, fill=TONGUE)


@emoji("cool")
def _(p):
    face(p)
    p.rrect(11, 20, 30, 32, 4, fill=DARK)
    p.rrect(34, 20, 53, 32, 4, fill=DARK)
    p.rect(29, 24, 35, 27, fill=DARK)
    smile(p, r=12)


@emoji("love")
def _(p):
    face(p)
    for cx in (22.5, 41.5):
        p.circle(cx - 3.6, 24, 4.2, fill=RED)
        p.circle(cx + 3.6, 24, 4.2, fill=RED)
        p.poly([(cx - 7.6, 26), (cx + 7.6, 26), (cx, 34)], fill=RED)
    smile(p, r=12)


@emoji("blush")
def _(p):
    face(p); eyes_closed(p, y=26)
    smile(p, r=12)
    p.circle(15, 36, 5.5, fill=BLUSH)
    p.circle(49, 36, 5.5, fill=BLUSH)


@emoji("neutral")
def _(p):
    face(p); eyes_dots(p)
    p.line(22, 41, 42, 41, 3.4, fill=INK)


@emoji("sad")
def _(p):
    face(p); eyes_dots(p, y=25)
    p.arc(32, 50, 13, 205, 335, 3.4, fill=INK)


@emoji("cry")
def _(p):
    face(p); eyes_dots(p, y=25)
    p.arc(32, 50, 13, 205, 335, 3.4, fill=INK)
    p.rrect(19, 27, 25, 52, 3, fill=TEAR)


@emoji("angry")
def _(p):
    face(p, (247, 141, 79, 255))
    eyes_dots(p, y=28, r=3.2)
    p.line(13, 17, 27, 23, 3.6, fill=INK)
    p.line(51, 17, 37, 23, 3.6, fill=INK)
    p.arc(32, 52, 13, 205, 335, 3.4, fill=INK)


@emoji("surprised")
def _(p):
    face(p)
    p.circle(22.5, 25, 4.2, fill=INK)
    p.circle(41.5, 25, 4.2, fill=INK)
    p.ellipse(32, 42, 7, 9, fill=INK)


@emoji("confused")
def _(p):
    face(p); eyes_dots(p)
    p.polyline([(21, 43), (26, 39), (32, 43), (38, 39), (43, 43)], 3.2, fill=INK)


@emoji("sleep")
def _(p):
    face(p); eyes_closed(p, y=26)
    p.ellipse(32, 42, 5, 6, fill=INK)
    p.polyline([(44, 14), (52, 14), (44, 22), (52, 22)], 2.6, fill=(85, 172, 238, 255))


# ------------------------------------------------------------- symbols ----

@emoji("heart")
def _(p):
    p.circle(21, 24, 12, fill=RED)
    p.circle(43, 24, 12, fill=RED)
    p.poly([(9.5, 27), (54.5, 27), (32, 55)], fill=RED)


@emoji("heart_broken")
def _(p):
    p.circle(21, 24, 12, fill=RED)
    p.circle(43, 24, 12, fill=RED)
    p.poly([(9.5, 27), (54.5, 27), (32, 55)], fill=RED)
    p.polyline([(32, 12), (26, 27), (36, 34), (30, 43), (33, 55)], 4.0, fill=(0, 0, 0, 0))


@emoji("star")
def _(p):
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = 29 if i % 2 == 0 else 12.5
        pts.append((32 + math.cos(a) * r, 32 + math.sin(a) * r))
    p.poly(pts, fill=GOLD)


@emoji("sparkles")
def _(p):
    def spark(cx, cy, r, col):
        p.poly([(cx, cy - r), (cx + r * 0.28, cy - r * 0.28), (cx + r, cy),
                (cx + r * 0.28, cy + r * 0.28), (cx, cy + r),
                (cx - r * 0.28, cy + r * 0.28), (cx - r, cy),
                (cx - r * 0.28, cy - r * 0.28)], fill=col)
    spark(25, 27, 21, GOLD)
    spark(48, 16, 11, (255, 220, 120, 255))
    spark(45, 45, 14, (255, 220, 120, 255))


@emoji("fire")
def _(p):
    p.ellipse(32, 41, 20, 18, fill=(244, 144, 12, 255))
    p.poly([(12, 42), (32, 2), (52, 42)], fill=(244, 144, 12, 255))
    p.ellipse(32, 46, 11.5, 11, fill=(255, 204, 77, 255))
    p.poly([(20.5, 47), (32, 21), (43.5, 47)], fill=(255, 204, 77, 255))


@emoji("skull")
def _(p):
    p.circle(32, 27, 23, fill=(230, 233, 237, 255))
    p.rrect(22, 42, 42, 56, 5, fill=(230, 233, 237, 255))
    p.ellipse(23, 28, 7.5, 9, fill=DARK)
    p.ellipse(41, 28, 7.5, 9, fill=DARK)
    p.poly([(32, 36), (36, 44), (28, 44)], fill=DARK)
    p.line(27, 50, 27, 56, 2.4, fill=DARK)
    p.line(32, 50, 32, 56, 2.4, fill=DARK)
    p.line(37, 50, 37, 56, 2.4, fill=DARK)


@emoji("crown")
def _(p):
    p.poly([(6, 46), (10, 16), (22, 30), (32, 12), (42, 30), (54, 16), (58, 46)],
           fill=GOLD)
    p.rrect(8, 45, 56, 54, 3, fill=(230, 145, 30, 255))
    p.circle(32, 26, 3.6, fill=RED)


@emoji("sword")
def _(p):
    p.poly([(44, 6), (58, 6), (26, 44), (18, 36)], fill=GREY)
    p.line(14, 42, 26, 54, 6.0, fill=(120, 80, 48, 255))
    p.line(9, 47, 21, 59, 6.0, fill=(160, 110, 66, 255))
    p.line(12, 38, 30, 56, 3.0, fill=GOLD)


@emoji("shield")
def _(p):
    p.poly([(32, 5), (56, 14), (52, 40), (32, 59), (12, 40), (8, 14)],
           fill=(85, 130, 190, 255))
    p.poly([(32, 12), (49, 18), (46, 38), (32, 51), (18, 38), (15, 18)],
           fill=(206, 219, 233, 255))
    p.rect(29, 20, 35, 44, fill=RED)
    p.rect(20, 26, 44, 32, fill=RED)


@emoji("potion")
def _(p):
    p.rrect(26, 6, 38, 18, 2, fill=(200, 210, 220, 255))
    p.poly([(24, 16), (40, 16), (52, 44), (44, 58), (20, 58), (12, 44)],
           fill=(214, 226, 236, 200))
    p.poly([(19, 34), (45, 34), (50, 45), (43, 57), (21, 57), (14, 45)],
           fill=PURPLE)
    p.circle(24, 44, 3.0, fill=(226, 208, 245, 255))


@emoji("gem")
def _(p):
    p.poly([(20, 10), (44, 10), (58, 26), (32, 58), (6, 26)],
           fill=(93, 205, 214, 255))
    p.poly([(20, 10), (32, 26), (6, 26)], fill=(150, 232, 238, 255))
    p.poly([(44, 10), (58, 26), (32, 26)], fill=(60, 170, 182, 255))
    p.poly([(6, 26), (32, 26), (32, 58)], fill=(120, 218, 226, 255))


@emoji("coin")
def _(p):
    p.circle(32, 32, 27, fill=(214, 150, 32, 255))
    p.circle(32, 32, 22, fill=GOLD)
    p.circle(32, 32, 13, fill=(255, 226, 150, 255))


@emoji("ok")
def _(p):
    p.circle(32, 32, 28, fill=GREEN)
    p.polyline([(19, 33), (28, 43), (46, 21)], 6.0, fill=WHITE)


@emoji("no")
def _(p):
    p.circle(32, 32, 28, fill=RED)
    p.line(22, 22, 42, 42, 6.0, fill=WHITE)
    p.line(42, 22, 22, 42, 6.0, fill=WHITE)


@emoji("warn")
def _(p):
    p.poly([(32, 5), (61, 56), (3, 56)], fill=(255, 204, 77, 255))
    p.polyline([(32, 5), (61, 56), (3, 56), (32, 5)], 7.0, fill=(255, 204, 77, 255))
    p.line(32, 24, 32, 40, 5.0, fill=DARK)
    p.circle(32, 47, 3.2, fill=DARK)


@emoji("question")
def _(p):
    p.circle(32, 32, 28, fill=BLUE)
    p.arc(32, 25, 9, 190, 380, 5.4, fill=WHITE)
    p.line(32, 32, 32, 39, 5.4, fill=WHITE)
    p.circle(32, 47, 3.4, fill=WHITE)


def main():
    atlas = Image.new("RGBA", (CELL * COLS, CELL * ROWS), (0, 0, 0, 0))
    names = []
    for idx, (name, fn) in enumerate(EMOJI):
        cell = Image.new("RGBA", (CELL * SS, CELL * SS), (0, 0, 0, 0))
        d = ImageDraw.Draw(cell)
        fn(Pen(d, SS))
        cell = cell.resize((CELL, CELL), Image.LANCZOS)
        cell = bleed(cell, passes=3)
        atlas.paste(cell, ((idx % COLS) * CELL, (idx // COLS) * CELL))
        names.append(name)

    out = os.path.normpath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "WhatTheWhisper", "Art"))
    write_tga(os.path.join(out, "Emoji.tga"), atlas)
    atlas.save(os.path.join(out, "_preview_emoji.png"))

    lines = ["-- Generated by Tools/gen_emoji.py -- do not edit by hand.",
             "local _, ns = ...", "", "ns.EMOJI_ATLAS = {"]
    for i, name in enumerate(names):
        c, r = i % COLS, i // COLS
        lines.append("\t%s = { %.6f, %.6f, %.6f, %.6f }," % (
            name, c / COLS, (c + 1) / COLS, r / ROWS, (r + 1) / ROWS))
    lines.append("}")
    lines.append("")
    with open(os.path.join(out, "..", "UI", "EmojiAtlas.lua"), "w") as fh:
        fh.write("\n".join(lines))
    print("wrote %d emoji" % len(names))


main()
