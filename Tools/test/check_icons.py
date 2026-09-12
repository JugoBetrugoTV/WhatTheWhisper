"""Every icon the code asks for must exist in the generated atlas.

Draw.SetIcon fails silently on an unknown name -- the button simply renders
empty -- so this is checked mechanically rather than by eye.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

atlas = set(subprocess.check_output([
    "lua5.1", "-e",
    'local ns={} loadfile("%s/WhatTheWhisper/UI/IconAtlas.lua")("x",ns) '
    'local k={} for n in pairs(ns.ICON_ATLAS) do k[#k+1]=n end table.sort(k) '
    'print(table.concat(k,","))' % ROOT]).decode().strip().split(","))

PATTERNS = [
    re.compile(r'SetIcon\s*\(\s*[\w.]+\s*,\s*"([a-z_0-9]+)"'),
    re.compile(r'\bicon\s*=\s*"([a-z_0-9]+)"'),
    re.compile(r'W\.Icon\([^,]+,\s*"([a-z_0-9]+)"'),
    re.compile(r'AddHeaderButton\(\s*"([a-z_0-9]+)"'),
    re.compile(r':SetIcon\(\s*"([a-z_0-9]+)"'),
    re.compile(r'Button\.Icon\([^)]*?icon\s*=\s*"([a-z_0-9]+)"'),
]

used = {}
for base, _, files in os.walk(os.path.join(ROOT, "WhatTheWhisper")):
    for name in files:
        if not name.endswith(".lua"):
            continue
        path = os.path.join(base, name)
        rel = os.path.relpath(path, ROOT)
        for number, line in enumerate(open(path, encoding="utf-8"), 1):
            for pattern in PATTERNS:
                for match in pattern.finditer(line):
                    used.setdefault(match.group(1), []).append("%s:%d" % (rel, number))

# Emoji category items are validated against the emoji atlas instead.
emoji_only = {"rt1", "rt2", "rt3", "rt4", "rt5", "rt6", "rt7", "rt8"}
# Draw.SetIcon only looks in the icon atlas, so an emoji name is not a pass.
missing = {k: v for k, v in used.items() if k not in atlas and k not in emoji_only}

print("icon atlas: %d entries, %d referenced" % (len(atlas), len(used)))
if missing:
    print("MISSING ICONS:")
    for key in sorted(missing):
        for location in missing[key]:
            print("  %-16s %s" % (key, location))
    sys.exit(1)
print("all referenced icons exist")
