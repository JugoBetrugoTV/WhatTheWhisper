"""Structural checks the runtime mock cannot make.

Covers the things that only break on a real client: a file listed in the XML
that is not on disk (or differs in case, which only matters on case-sensitive
filesystems), a texture path with no file behind it, a global frame name used
twice, and writes to globals the addon never declared.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ADDON = os.path.join(ROOT, "WhatTheWhisper")

errors = []
notes = []


def err(message):
    errors.append(message)


# ---------------------------------------------------------------- load list --
xml_path = os.path.join(ADDON, "WhatTheWhisper.xml")
xml = open(xml_path, encoding="utf-8").read()
declared = [f.replace("\\", "/") for f in re.findall(r'<Script file="([^"]+)"/>', xml)]

# Exact-case existence, not just os.path.exists: a mismatch works on Windows and
# fails on Linux and macOS clients.
def exists_exact(relative):
    parts = relative.split("/")
    current = ADDON
    for part in parts:
        try:
            entries = os.listdir(current)
        except OSError:
            return False
        if part not in entries:
            return False
        current = os.path.join(current, part)
    return True


for relative in declared:
    if not exists_exact(relative):
        err("XML lists a file that is not on disk (exact case): %s" % relative)

# Every shipped Lua file must be listed exactly once. Libs/ is excluded on
# purpose: those files are loaded by their own manifest and are third-party, so
# Tools/test/check_libs.py owns them -- including checking that they are
# unmodified, which the rules below would have no business enforcing.
on_disk = []
for base, dirs, files in os.walk(ADDON):
    dirs[:] = [d for d in dirs if d != "Libs"]
    for name in files:
        if name.endswith(".lua"):
            rel = os.path.relpath(os.path.join(base, name), ADDON).replace("\\", "/")
            on_disk.append(rel)

for rel in sorted(on_disk):
    if rel not in declared:
        err("Lua file on disk but not loaded by the XML: %s" % rel)

seen = set()
for rel in declared:
    if rel in seen:
        err("file listed twice in the XML: %s" % rel)
    seen.add(rel)

notes.append("%d files declared, %d Lua files on disk" % (len(declared), len(on_disk)))

# ------------------------------------------------------------------- TOCs ----
tocs = [f for f in os.listdir(ADDON) if f.endswith(".toc")]
if not tocs:
    err("no .toc file")
for toc in tocs:
    text = open(os.path.join(ADDON, toc), encoding="utf-8").read()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if not exists_exact(line.replace("\\", "/")):
            err("%s references a missing file: %s" % (toc, line))
    if "## Interface:" not in text:
        err("%s has no Interface line" % toc)
    for key in ("## Title:", "## SavedVariables:"):
        if key not in text:
            err("%s is missing %s" % (toc, key))
notes.append("%d TOC files" % len(tocs))

# --------------------------------------------------------------- textures ----
# Texture paths are built from ns.ART, which is Interface\AddOns\<folder>\Art\.
art_dir = os.path.join(ADDON, "Art")
art_files = {os.path.splitext(f)[0] for f in os.listdir(art_dir)}
lua_all = ""
for rel in declared:
    lua_all += open(os.path.join(ADDON, rel), encoding="utf-8").read()

for name in re.findall(r'ART\s*\.\.\s*"([A-Za-z0-9_]+)"', lua_all):
    if name not in art_files:
        err("texture referenced but not in Art/: %s" % name)

# Blizzard texture paths must not carry a file extension.
for path in re.findall(r'"(Interface\\\\[^"]+)"', lua_all):
    if path.lower().endswith((".tga", ".blp", ".png")):
        err("Blizzard texture path should have no extension: %s" % path)
notes.append("Art/: %s" % ", ".join(sorted(art_files)))

# --------------------------------------------------- global frame names ------
names = re.findall(r'CreateFrame\(\s*"[A-Za-z]+"\s*,\s*"([A-Za-z_][A-Za-z0-9_]*)"', lua_all)
duplicates = {n for n in names if names.count(n) > 1}
for name in sorted(duplicates):
    err("global frame name used more than once: %s" % name)
notes.append("%d globally named frames" % len(set(names)))

# ------------------------------------------------------- accidental globals --
# Anything that touches the namespace must take it from the vararg header rather
# than reaching for the _G.WhatTheWhisper alias.
NS_HEADER = re.compile(r'^local\s+[A-Za-z0-9_,\s]*\bns\b[A-Za-z0-9_,\s]*=\s*\.\.\.', re.M)
for rel in declared:
    source = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    uses_ns = re.search(r'\bns\.', source) is not None
    if uses_ns and not NS_HEADER.search(source):
        err("%s uses ns. but does not take it from the vararg header" % rel)

# Locale files legitimately only need LibStub; everything else that defines
# behaviour should be reachable through the namespace.
for rel in declared:
    source = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    for match in re.finditer(r'\b_G\.WhatTheWhisper\b', source):
        if "Namespace.lua" not in rel:
            err("%s reaches for the _G alias instead of the vararg namespace" % rel)
            break

# ---------------------------------------------------------------------------
# The spacing system: SetPoint offsets must be named constants or derived from
# them, never a number typed straight into the call. This is a source rule, not
# a geometry one -- at runtime a derived 3 and a magic 3 are the same number, so
# the only place it can be enforced is here.
SPACING = set()
_ns = open(os.path.join(ADDON, "Core/Namespace.lua"), encoding="utf-8").read()
for block in ("S", "R", "SZ", "T"):
    section = re.search(r'\bns\.%s\s*=\s*\{(.*?)\n\}' % block, _ns, re.S)
    if section:
        for value in re.findall(r'=\s*(-?\d+(?:\.\d+)?)\s*,', section.group(1)):
            SPACING.add(abs(float(value)))

# 0 is "flush", 1 and 2 are hairline nudges that read as such wherever they
# appear, and a half or double step is still the scale talking.
ALLOWED = {0.0, 1.0, 2.0}
for value in list(SPACING):
    ALLOWED.add(value)
    ALLOWED.add(value / 2)
    ALLOWED.add(value * 2)

SETPOINT = re.compile(r'SetPoint\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)')
offenders = []
for rel in declared:
    source = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    for line_no, line in enumerate(source.split("\n"), 1):
        for call in SETPOINT.finditer(line):
            args = call.group(1).split(",")
            for arg in args[-2:] if len(args) >= 4 else []:
                arg = arg.strip()
                literal = re.fullmatch(r'-?\d+(?:\.\d+)?', arg)
                if not literal:
                    continue        # a constant, an expression, a variable
                if abs(float(arg)) not in ALLOWED:
                    offenders.append("%s:%d offset %s is not on the spacing scale"
                                     % (rel, line_no, arg))
for offender in offenders:
    err(offender)
notes.append("%d SetPoint offsets checked against the spacing scale"
             % len(SPACING))

# ---------------------------------------------------------------------------
# Every XML file must actually be well-formed XML.
#
# This check exists because its absence shipped a broken build. Libs.xml carried
# a double hyphen inside a comment, which is illegal in XML; the client refused
# the whole file, so not one library loaded and every file in the addon died on
# its first LibStub call. Nothing caught it, because the Lua harness reads these
# manifests with a pattern match, and a pattern match does not care whether the
# document is well-formed. The client's parser does.
import xml.parsers.expat

xml_files = []
for base, dirs, files in os.walk(ADDON):
    for name in sorted(files):
        if name.endswith(".xml"):
            xml_files.append(os.path.join(base, name))

for path in xml_files:
    rel = os.path.relpath(path, ADDON)
    try:
        parser = xml.parsers.expat.ParserCreate()
        parser.Parse(open(path, "rb").read(), True)
    except xml.parsers.expat.ExpatError as problem:
        err("%s is not well-formed XML: %s" % (rel, problem))
        continue
    # Expat reports the position but not the cause, and the cause is nearly
    # always this one, so name it: "--" may not appear inside an XML comment.
    body = open(path, encoding="utf-8").read()
    for match in re.finditer(r'<!--(.*?)-->', body, re.S):
        if "--" in match.group(1):
            line = body[:match.start()].count("\n") + 1
            err("%s: comment starting at line %d contains a double hyphen, "
                "which is illegal inside an XML comment" % (rel, line))

notes.append("%d XML files parsed as the client parses them" % len(xml_files))

# Bindings.xml is picked up from the addon folder by the client itself. Listing
# it in the TOC makes the generic UI XML loader parse it as well, which fills
# the log with "Unrecognized XML: Binding" for every entry -- the bindings still
# register, but the warnings are real and they are ours.
for name in tocs:
    body = open(os.path.join(ADDON, name), encoding="utf-8").read()
    for line in body.split("\n"):
        if line.strip().lower() == "bindings.xml":
            err("%s lists Bindings.xml; the client loads it on its own, and "
                "listing it makes the UI parser walk it too" % name)
if os.path.exists(os.path.join(ADDON, "Bindings.xml")):
    notes.append("Bindings.xml present and left for the client to discover")

print("\n".join("  " + n for n in notes))
if errors:
    print("\nSTRUCTURE ERRORS:")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("structure ok")
