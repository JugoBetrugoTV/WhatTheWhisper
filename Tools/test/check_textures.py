"""Texture quality: reads the shipped .tga pixels and checks them.

The failure modes here are the ones nobody notices until a screenshot: a dark
fringe around every antialiased edge because transparent pixels carry black RGB,
a neighbouring atlas cell bleeding in because the sheet has no gutter, an icon
drawn off centre in its cell, and a sheet whose dimensions are not powers of two
so the client rescales it.

Everything is measured from the file, not from the generator that wrote it.
"""
import os
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ART = os.path.join(ROOT, "WhatTheWhisper/Art")
ADDON = os.path.join(ROOT, "WhatTheWhisper")

errors = []
notes = []


def err(message):
    errors.append(message)


class Texture(object):
    """A 32-bit uncompressed TGA, read back the way the client would."""

    def __init__(self, path):
        with open(path, "rb") as fh:
            blob = fh.read()
        (idlen, cmap, kind, _, _, _, _, _,
         self.w, self.h, bpp, descriptor) = struct.unpack("<BBBHHBHHHHBB", blob[:18])
        self.path = path
        self.name = os.path.basename(path)
        self.bpp = bpp
        self.kind = kind
        self.topDown = bool(descriptor & 0x20)
        self.alphaBits = descriptor & 0x0F
        offset = 18 + idlen
        if cmap:
            err("%s carries a colour map; the client expects true colour" % self.name)
        body = blob[offset:offset + self.w * self.h * 4]
        if len(body) != self.w * self.h * 4:
            err("%s is truncated: %d bytes of pixels, expected %d"
                % (self.name, len(body), self.w * self.h * 4))
        self.px = body

    def rgba(self, x, y):
        i = (y * self.w + x) * 4
        b, g, r, a = self.px[i], self.px[i + 1], self.px[i + 2], self.px[i + 3]
        return r, g, b, a

    def alpha(self, x, y):
        return self.px[(y * self.w + x) * 4 + 3]


def isPowerOfTwo(n):
    return n > 0 and (n & (n - 1)) == 0


def check_format(tex):
    if tex.kind != 2:
        err("%s is not uncompressed true-colour (image type %d)" % (tex.name, tex.kind))
    if tex.bpp != 32:
        err("%s is %d bits per pixel; the addon tints at runtime and needs 32"
            % (tex.name, tex.bpp))
    if tex.alphaBits != 8:
        err("%s declares %d alpha bits, not 8" % (tex.name, tex.alphaBits))
    if not tex.topDown:
        err("%s is bottom-up; the atlas coordinates assume a top-down origin" % tex.name)
    # WoW rescales a non-power-of-two texture on load, which softens every edge
    # the pixel snapping was there to keep sharp.
    if not isPowerOfTwo(tex.w) or not isPowerOfTwo(tex.h):
        err("%s is %dx%d; both dimensions must be powers of two" % (tex.name, tex.w, tex.h))


# A pixel this faint adds no coverage but its RGB is still sampled by the
# filter, so it has to carry the neighbouring colour like a transparent one.
FAINT = 8

# How far a repaired pixel may sit from the mean of what it borders. Where a
# dark outline meets a white fill the correct answer really is the grey in
# between, so the test is "close to the mean", not "as bright as the brightest
# thing next to it".
BLEED_TOLERANCE = 40


def check_bleed(tex):
    """Faint pixels must carry the colour of what they border.

    Bilinear filtering reads RGB regardless of alpha, so a faint pixel left at
    black draws a dark halo around the shape beside it. The dilation fills each
    one with the mean of its drawn neighbours; this checks the file matches.
    """
    off, checked = 0, 0
    worst = None
    for y in range(1, tex.h - 1):
        for x in range(1, tex.w - 1):
            if tex.alpha(x, y) > FAINT:
                continue
            rs = gs = bs = n = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    nr, ng, nb, na = tex.rgba(x + dx, y + dy)
                    if na > FAINT:
                        rs += nr; gs += ng; bs += nb; n += 1
            if not n:
                continue        # deep in the transparent region; nothing to match
            checked += 1
            r, g, b, _ = tex.rgba(x, y)
            mean = (rs // n, gs // n, bs // n)
            drift = max(abs(r - mean[0]), abs(g - mean[1]), abs(b - mean[2]))
            if drift > BLEED_TOLERANCE:
                off += 1
                worst = worst or (x, y, (r, g, b), mean, drift)
    if off:
        err("%s has %d faint pixels whose colour does not match what they border "
            "(worst at %d,%d: %s vs mean %s, off by %d) -- they will fringe"
            % ((tex.name, off) + worst))
    notes.append("%s: %d faint pixels checked against their neighbourhood"
                 % (tex.name, checked))


def check_gutters(tex, cols, rows, label):
    """No cell may put ink in its outermost row or column.

    Without that margin the client's filtering samples across the cell boundary
    and the icon next door bleeds in at small sizes.
    """
    cw, ch = tex.w // cols, tex.h // rows
    if cw * cols != tex.w or ch * rows != tex.h:
        err("%s does not divide evenly into %dx%d cells" % (label, cols, rows))
        return
    touching = []
    for row in range(rows):
        for col in range(cols):
            x0, y0 = col * cw, row * ch
            edge = 0
            for i in range(cw):
                edge = max(edge, tex.alpha(x0 + i, y0), tex.alpha(x0 + i, y0 + ch - 1))
            for i in range(ch):
                edge = max(edge, tex.alpha(x0, y0 + i), tex.alpha(x0 + cw - 1, y0 + i))
            if edge > 8:
                touching.append("(%d,%d) alpha %d" % (col, row, edge))
    if touching:
        err("%s: %d cells draw into their own border, so neighbours bleed in "
            "when filtered: %s" % (label, len(touching), ", ".join(touching[:4])))
    notes.append("%s: %d cells, %dx%d each, all with a clear border"
                 % (label, cols * rows, cw, ch))


def check_centering(tex, cols, rows, label, tolerance):
    """An icon whose ink is off centre in its cell looks misaligned in a row of
    buttons even though every button is the same size."""
    cw, ch = tex.w // cols, tex.h // rows
    offenders = []
    for row in range(rows):
        for col in range(cols):
            x0, y0 = col * cw, row * ch
            minx, maxx, miny, maxy = cw, -1, ch, -1
            for y in range(ch):
                for x in range(cw):
                    if tex.alpha(x0 + x, y0 + y) > 24:
                        minx, maxx = min(minx, x), max(maxx, x)
                        miny, maxy = min(miny, y), max(maxy, y)
            if maxx < 0:
                continue        # an empty cell is a spare slot, not a fault
            cx = (minx + maxx + 1) / 2.0
            cy = (miny + maxy + 1) / 2.0
            dx, dy = abs(cx - cw / 2.0), abs(cy - ch / 2.0)
            if dx > tolerance or dy > tolerance:
                offenders.append("(%d,%d) off by %.1f,%.1f" % (col, row, dx, dy))
    if offenders:
        err("%s: %d cells are not centred within %.1fpx: %s"
            % (label, len(offenders), tolerance, ", ".join(offenders[:4])))
    notes.append("%s: every drawn cell centred within %.1fpx" % (label, tolerance))


def atlas_size(lua_name, table_name):
    """Reads the cell grid straight out of the generated coordinate table so a
    regenerated atlas cannot silently disagree with this check."""
    path = os.path.join(ADDON, lua_name)
    source = open(path, encoding="utf-8").read()
    import re
    rows = re.findall(r'=\s*\{\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\s*\}', source)
    if not rows:
        return None, None
    widths = set(round(float(r) - float(l), 6) for l, r, _, _ in rows)
    heights = set(round(float(b) - float(t), 6) for _, _, t, b in rows)
    if len(widths) != 1 or len(heights) != 1:
        err("%s: cells are not a uniform grid (%d widths, %d heights)"
            % (lua_name, len(widths), len(heights)))
        return None, None
    return int(round(1.0 / widths.pop())), int(round(1.0 / heights.pop()))


textures = {}
for name in sorted(os.listdir(ART)):
    if not name.endswith(".tga"):
        continue
    tex = Texture(os.path.join(ART, name))
    textures[name] = tex
    check_format(tex)
    notes.append("%s: %dx%d, %d-bit, top-down" % (name, tex.w, tex.h, tex.bpp))

for name in ("Icons.tga", "Emoji.tga", "Logo.tga"):
    if name in textures:
        check_bleed(textures[name])

iconCols, iconRows = atlas_size("UI/IconAtlas.lua", "ICON_ATLAS")
if iconCols and "Icons.tga" in textures:
    check_gutters(textures["Icons.tga"], iconCols, iconRows, "Icons.tga")
    check_centering(textures["Icons.tga"], iconCols, iconRows, "Icons.tga", 2.0)

emojiCols, emojiRows = atlas_size("UI/EmojiAtlas.lua", "EMOJI_ATLAS")
if emojiCols and "Emoji.tga" in textures:
    check_gutters(textures["Emoji.tga"], emojiCols, emojiRows, "Emoji.tga")
    check_centering(textures["Emoji.tga"], emojiCols, emojiRows, "Emoji.tga", 3.0)

# The rounded-corner disc is sampled by all four corner quads, so it has to be
# symmetric or the corners of every panel will not match each other.
if "Round.tga" in textures:
    tex = textures["Round.tga"]
    asymmetric = 0
    for y in range(0, tex.h, max(1, tex.h // 64)):
        for x in range(0, tex.w, max(1, tex.w // 64)):
            a = tex.alpha(x, y)
            if abs(a - tex.alpha(tex.w - 1 - x, y)) > 2:
                asymmetric += 1
            if abs(a - tex.alpha(x, tex.h - 1 - y)) > 2:
                asymmetric += 1
    if asymmetric:
        err("Round.tga is not symmetric in %d sampled pixels; the four corners "
            "of a panel would not match" % asymmetric)
    else:
        notes.append("Round.tga: symmetric on both axes, so all four corners match")
    # A disc that reaches full opacity in the middle and zero outside the radius
    # is the whole point; a flat one would draw a square.
    centre = tex.alpha(tex.w // 2, tex.h // 2)
    corner = tex.alpha(1, 1)
    if centre < 250:
        err("Round.tga is only %d opaque at its centre; panels would be translucent"
            % centre)
    if corner > 8:
        err("Round.tga has alpha %d in its corner; the rounding would not show"
            % corner)

if "Shadow.tga" in textures:
    tex = textures["Shadow.tga"]
    centre = tex.alpha(tex.w // 2, tex.h // 2)
    edge = tex.alpha(1, tex.h // 2)
    if centre <= edge:
        err("Shadow.tga does not fall off from the centre (%d) to the edge (%d)"
            % (centre, edge))
    else:
        notes.append("Shadow.tga: falls off %d -> %d from centre to edge" % (centre, edge))

print("\n".join("  " + n for n in notes))
if errors:
    print("\nTEXTURE ERRORS:")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("textures ok")
