"""Regenerates WhatTheWhisper/Libs/Libs.manifest.json.

The manifest records a SHA-256 for every embedded library file and the revision
each library registers with LibStub. Tools/test/check_libs.py compares the
shipped files against it, which is what makes "we never patch a library" an
enforced rule rather than a promise: an accidental edit, a stray debug print, or
a well-meaning local fix all change a hash and fail the suite.

Run this ONLY when deliberately updating a library to a new upstream revision,
and say so in the commit message.
"""
import hashlib
import io
import json
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LIBS = os.path.join(ROOT, "WhatTheWhisper", "Libs")

files, versions = {}, {}
for base, _dirs, names in os.walk(LIBS):
    for name in sorted(names):
        if not name.endswith((".lua", ".xml")):
            continue
        rel = os.path.relpath(os.path.join(base, name), LIBS).replace(os.sep, "/")
        if rel == "Libs.xml":
            continue        # our own manifest, not an upstream file
        with open(os.path.join(base, name), "rb") as fh:
            files[rel] = hashlib.sha256(fh.read()).hexdigest()
        if rel.endswith(".lua"):
            body = io.open(os.path.join(LIBS, rel), encoding="utf-8").read()
            match = re.search(r'(\w*MAJOR)\s*,\s*(\w*MINOR)\s*=\s*"([^"]+)"\s*,\s*(\d+)', body)
            if match:
                versions[match.group(3)] = int(match.group(4))

out = {
    "note": ("SHA-256 of every embedded library file as shipped by upstream Ace3, "
             "plus the revision each one registers with LibStub. Regenerate with "
             "Tools/gen_lib_manifest.py only when deliberately updating a library."),
    "versions": dict(sorted(versions.items())),
    "files": dict(sorted(files.items())),
}
target = os.path.join(LIBS, "Libs.manifest.json")
io.open(target, "w", encoding="utf-8").write(json.dumps(out, indent=2) + "\n")
print("wrote %s: %d files, %d libraries" % (target, len(files), len(versions)))
