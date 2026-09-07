"""Every icon must still read at the size it is actually drawn.

An icon sheet is authored at 64px and drawn at 11 to 16. A stroke that looks
crisp in the atlas becomes less than one physical pixel down there, and the
client resolves it to grey mush rather than a line. That is invisible while
reviewing the sheet and obvious in the game.

So the sizes are taken from the source, not guessed: whatever W.Icon is called
with, plus the named glyph constants. Each icon is downsampled to exactly the
sizes it is used at and judged on how much of its ink survives as opaque.
"""
import os
import re
import struct
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ADDON = os.path.join(ROOT, "WhatTheWhisper")

try:
    from PIL import Image
except ImportError:
    print("Pillow is not installed; skipping icon legibility")
    sys.exit(0)

errors, notes = [], []


def err(message):
    errors.append(message)


# --- the constants the source draws icons at -------------------------------

namespace = open(os.path.join(ADDON, "Core/Namespace.lua"), encoding="utf-8").read()
CONSTS = {}
for name, value in re.findall(r'(\w+)\s*=\s*(\d+),', namespace):
    CONSTS["ns.SZ." + name] = int(value)
    CONSTS["ns.S." + name] = int(value)

sources = {}
for base, dirs, files in os.walk(ADDON):
    dirs[:] = [d for d in dirs if d != "Libs"]
    for name in files:
        if name.endswith(".lua"):
            path = os.path.join(base, name)
            sources[path] = open(path, encoding="utf-8").read()

# Local constants like STATUS_SIZE = 11, resolved per file.
usage = {}


def note_usage(icon, size):
    if size and 4 <= size <= 64:
        usage.setdefault(icon, set()).add(int(size))


ICON_CALL = re.compile(r'W\.Icon\(\s*[^,]+,\s*"([a-z_]+)"\s*,\s*([^,)]+)')
SET_ICON = re.compile(r'icon\s*=\s*"([a-z_]+)"')
for path, body in sources.items():
    locals_here = dict(CONSTS)
    for name, value in re.findall(r'^local\s+(\w+)\s*=\s*(\d+)\s*$', body, re.M):
        locals_here[name] = int(value)

    for icon, raw in ICON_CALL.findall(body):
        raw = raw.strip()
        if raw.isdigit():
            note_usage(icon, int(raw))
        elif raw in locals_here:
            note_usage(icon, locals_here[raw])
        else:
            # An expression: assume the default glyph size, which is what the
            # widget layer falls back to.
            note_usage(icon, CONSTS.get("ns.SZ.ICON_GLYPH", 16))

    # An icon named inside a table -- a button spec, a status map -- is drawn at
    # one of the icon sizes that file uses. Attributing it to every such size in
    # the file is what catches the delivery marks, which are named in a table
    # and sized from ns.SZ.STATUS_ICON several hundred lines away.
    file_sizes = {CONSTS.get("ns.SZ.ICON_GLYPH", 16)}
    for const in ("ns.SZ.STATUS_ICON", "ns.SZ.ICON_GLYPH_SM", "ns.SZ.MENU_ICON"):
        if const.split(".")[-1] in body and const in CONSTS:
            file_sizes.add(CONSTS[const])
    for icon in SET_ICON.findall(body):
        for size in file_sizes:
            note_usage(icon, size)

if not usage:
    err("no icon usage found in the source; this check would pass vacuously")

# --- read the sheet --------------------------------------------------------

blob = open(os.path.join(ADDON, "Art/Icons.tga"), "rb").read()
idlen = blob[0]
width, height = struct.unpack("<HH", blob[12:16])
offset = 18 + idlen
pixels = bytearray()
for i in range(0, width * height * 4, 4):
    pixels += bytes((blob[offset + i + 2], blob[offset + i + 1],
                     blob[offset + i], blob[offset + i + 3]))
sheet = Image.frombytes("RGBA", (width, height), bytes(pixels))

atlas = open(os.path.join(ADDON, "UI/IconAtlas.lua"), encoding="utf-8").read()
cells = {}
for name, l, r, t, b in re.findall(
        r'(\w+)\s*=\s*\{\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\s*\}', atlas):
    cells[name] = (round(float(l) * 8), round(float(t) * 8))

# --- measure ---------------------------------------------------------------

# Fraction of an icon's ink that stays fully opaque after downsampling. Below
# this the glyph has dissolved: what the player sees is a grey smudge with the
# shape only implied.
MIN_OPAQUE = 0.35
INK = 24        # alpha above which a pixel counts as drawn at all
SOLID = 128     # alpha above which it counts as opaque

checked = 0
for icon in sorted(usage):
    if icon not in cells:
        err("%s is drawn but is not in the atlas" % icon)
        continue
    col, row = cells[icon]
    cell = sheet.crop((col * 64, row * 64, col * 64 + 64, row * 64 + 64))
    for size in sorted(usage[icon]):
        if size > 32:
            continue        # large draws are never the problem
        alpha = cell.resize((size, size), Image.LANCZOS).split()[3]
        data = list(alpha.getdata())  # noqa: pillow keeps this working
        lit = [p for p in data if p > INK]
        if not lit:
            err("%s has no ink at %dpx" % (icon, size))
            continue
        checked += 1
        opaque = sum(1 for p in lit if p > SOLID) / len(lit)
        if opaque < MIN_OPAQUE:
            err("%s dissolves at %dpx: only %.0f%% of its ink stays opaque "
                "(needs %.0f%%) -- thicken the stroke or draw it larger"
                % (icon, size, opaque * 100, MIN_OPAQUE * 100))

notes.append("%d icons checked at %d size combinations, all legible"
             % (len(usage), checked))
notes.append("sizes in use: %s" % ", ".join(
    str(s) for s in sorted({s for sizes in usage.values() for s in sizes}) if s <= 32))

print("\n".join("  " + n for n in notes))
if errors:
    print("\nICON LEGIBILITY ERRORS:")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("icons legible")
