#!/usr/bin/env python3
"""Writes docs/ICON-REPLACEMENT.md from the addon's own icon table.

The manifest is a work order: somebody pastes it into a generator, gets back a
folder of TGAs, drops them into WhatTheWhisper/Media/Icons and reloads. For that
to work, every number in it has to be the number the addon actually draws at --
so none of them are typed here. The filenames come from UI/Icons.lua, the render
sizes from the design tokens in Core/Namespace.lua, and how many places each icon
appears from reading the source.

Run it after changing the icon set; Tools/test/check_structure.py fails if the
committed file no longer matches.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ADDON = os.path.join(ROOT, "WhatTheWhisper")
OUT = os.path.join(ROOT, "docs", "ICON-REPLACEMENT.md")

# ---------------------------------------------------------------------------
# Read the addon
# ---------------------------------------------------------------------------

icons_lua = open(os.path.join(ADDON, "UI/Icons.lua"), encoding="utf-8").read()
namespace_lua = open(os.path.join(ADDON, "Core/Namespace.lua"), encoding="utf-8").read()

TOKENS = {}
for block in ("SZ", "T", "S"):
    section = re.search(r'\bns\.%s\s*=\s*\{(.*?)\n\}' % block, namespace_lua, re.S)
    for key, value in re.findall(r'(\w+)\s*=\s*(-?\d+(?:\.\d+)?)\s*,', section.group(1)):
        TOKENS.setdefault(key, float(value))

body = re.search(r'Icons\.REPLACEABLE = \{(.*?)\n\}', icons_lua, re.S).group(1)

entries = []
for match in re.finditer(r'\n\t(\w+) = \{(.*?)\n?\t?\},', body, re.S):
    name, fields = match.group(1), match.group(2)
    entry = {"name": name}
    for key, value in re.findall(r'(\w+) = "((?:[^"\\]|\\.)*)"', fields):
        entry[key] = value
    entries.append(entry)

# How many distinct places in the addon draw each icon. One asset used in five
# places is worth more care than one used once, and the author should know which
# is which before deciding how long to spend on it.
ICON_FORMS = (
    (re.compile(r'\bW\.Icon\('), 1),
    (re.compile(r'\bSetIcon\('), -1),
    (re.compile(r'\btitleButton\('), 0),
    (re.compile(r'\bAddHeaderButton\('), 0),
    (re.compile(r'\bicon\s*=\s*'), 0),
)
NAME = re.compile(r'"([a-z_0-9]+)"')


def split_args(text):
    args, depth, current = [], 0, []
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
        if ch == "," and depth == 0:
            args.append("".join(current))
            current = []
        else:
            current.append(ch)
    args.append("".join(current))
    return args


uses = {}
for base, dirs, files in os.walk(ADDON):
    if "Libs" in base:
        continue
    for filename in sorted(files):
        if not filename.endswith(".lua") or filename in ("Icons.lua", "IconAtlas.lua"):
            continue
        source = open(os.path.join(base, filename), encoding="utf-8").read()
        for line in source.split("\n"):
            for pattern, index in ICON_FORMS:
                match = pattern.search(line)
                if not match:
                    continue
                args = split_args(line[match.end():])
                if index == -1:
                    arg = args[-1] if len(args) > 1 else args[0]
                elif index < len(args):
                    arg = args[index]
                else:
                    continue
                for found in NAME.findall(arg):
                    uses[found] = uses.get(found, 0) + 1
                break

# ---------------------------------------------------------------------------
# Decide the art brief for each icon
# ---------------------------------------------------------------------------

# Master resolution. Everything is drawn small, so the source is generated large
# and scaled down: it is the only way to get a clean edge at 14 pixels.
def master(entry, render):
    return 128 if entry["name"] == "logo" else 64


# Safe padding inside the master square, in master pixels.
#
# Deliberately small. The glyph is drawn at about seven tenths of its button, and
# padding baked into the file comes straight off that: 10px of a 64px square is
# a sixth of the width gone before the artwork starts, and the mark ends up
# looking like the small grey suggestion this set exists to stop being.
#
# It is not one number, because the icons are not all drawn at one size. A
# delivery tick rendered at 16px has so little room on screen that it needs
# nearly the whole square; a glyph at 24 can afford a little more.
def padding(entry, render, size):
    if size >= 128:
        return 10
    if entry["size"] == "STATUS_ICON":
        return 4
    if render >= 22:
        return 6
    return 5


rows = []
for entry in sorted(entries, key=lambda e: e["name"]):
    render = int(TOKENS[entry["size"]])
    size = master(entry, render)
    rows.append({
        "file": entry["name"] + ".tga",
        "use": entry.get("use", ""),
        "render": render,
        "source": "%d x %d" % (size, size),
        "pad": padding(entry, render, size),
        "look": entry.get("note", ""),
        "places": uses.get(entry["name"], 0),
    })

# ---------------------------------------------------------------------------
# Write it
# ---------------------------------------------------------------------------

def table(rows):
    header = ("| File | What it is for | Rendered at | Source | Tintable | "
              "Safe padding | What it should look like | Hover/active art | "
              "Used in |")
    rule = "|---|---|---|---|---|---|---|---|---|"
    lines = [header, rule]
    for row in rows:
        lines.append("| `%s` | %s | %dpx | %s | yes | %dpx | %s | not needed | %s |"
                     % (row["file"], row["use"], row["render"], row["source"],
                        row["pad"], row["look"],
                        "1 place" if row["places"] == 1 else "%d places" % row["places"]))
    return "\n".join(lines)


doc = """# Replacing the icons

Generated by `Tools/gen_icon_manifest.py` from `WhatTheWhisper/UI/Icons.lua`.
Do not edit by hand -- run the script instead, or the numbers below stop being
the numbers the addon draws at.

## How to use this

1. Paste the table into an image generator and ask for the files it names.
2. Drop them into `WhatTheWhisper/Media/Icons/`.
3. `/reload`.

That is the whole process. No Lua to edit, no sprite sheet to rebuild, no
coordinates to work out. Any file you do not supply keeps using the built-in
artwork, so you can replace the set one icon at a time and the window always
works.

`/wtw diag` prints how many of them are being served from your own files, which
is the quickest way to find out whether a file landed in the right folder.

## Rules that apply to every file

* **32-bit TGA, uncompressed, with an alpha channel.** Not PNG -- the game does
  not read PNG from an addon folder.
* **Transparent background.** No plate, no circle behind the glyph unless the
  glyph *is* a circle. The button's own background is drawn by the addon.
* **Draw it white or near-white.** Every icon is tinted at runtime to match the
  active theme, so one white file works in all six skins and looks right in
  each. A blue icon stays blue in the green skin.
* **One weight throughout the set.** The stroke that reads correctly at 14px is
  about 6-8% of the icon's width; keep it the same in every file or the set
  looks assembled rather than designed.
* **Rounded caps and joins**, geometric construction, no gradients, no inner
  shadows, no text, no perspective.
* **Leave the safe padding empty -- but only that much.** The table gives a
  figure per icon, in source pixels, and it is small on purpose: the addon draws
  these at about seven tenths of their button, so every pixel of padding baked
  into the file is a pixel off the mark the player actually sees. Artwork that
  runs right to the edge looks larger than everything beside it; artwork with a
  wide margin looks timid. The figures below are the middle of that.
* **It has to survive 14px.** Squint at it. If the shape only makes sense
  because of a detail three pixels across, it is the wrong drawing -- simplify
  it rather than making the detail bigger.

## One file per icon, not four

Hover, pressed and disabled are produced by the addon: it changes the tint and
the background under the glyph. Do not generate separate art for them. The only
reason to supply a second file would be a shape that genuinely changes -- and
nothing in this set does.

## The icons

__TABLE__

## Notes on specific ones

* **`send`** is the most looked-at glyph in the addon and the one worth spending
  the longest on. It sits inside a filled circle, so it is drawn in the theme's
  "on accent" colour -- effectively white on blue -- and needs to read cleanly
  against a solid field rather than against the panel.
* **`sent`, `delivered`, `failed`** are the delivery marks tucked into the
  corner of an outgoing message. They are the smallest things drawn and they sit
  on a coloured bubble, so they need the most generous stroke weight in the set.
  `delivered` is two overlapping checks and is the one most likely to turn to
  mush: keep the overlap wide.
* **`pin` and `unpin`** are the same object, filled and outlined. They appear
  next to each other in a menu, so they should look like one drawing in two
  states rather than two drawings.
* **`logo`** is the addon's own mark, drawn at 18px in the title bar and on the
  minimap button. It is the one file generated at 128 x 128, because the minimap
  button may draw it larger on a scaled interface.
* **`bullet`** is the fallback used wherever a menu entry or a settings category
  has nothing more specific. It should be unremarkable -- a small filled dot is
  correct, and anything more interesting than that will be distracting in a
  column of other icons.
""".replace("__TABLE__", table(rows))

if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    existing = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else None
    if "--check" in sys.argv:
        if existing != doc:
            print("docs/ICON-REPLACEMENT.md is out of date; run Tools/gen_icon_manifest.py")
            sys.exit(1)
        print("icon manifest is up to date (%d icons)" % len(rows))
    else:
        open(OUT, "w", encoding="utf-8").write(doc)
        print("wrote %s (%d icons)" % (os.path.relpath(OUT, ROOT), len(rows)))
