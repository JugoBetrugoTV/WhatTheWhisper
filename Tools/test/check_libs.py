"""Embedded library packaging: the addon folder has to be the whole install.

Checks the structure a player actually receives:

  * every file the TOCs and manifests name exists, with the exact case
  * the load order is LibStub, then CallbackHandler, then the Ace modules
  * every library requested at runtime through LibStub("...") is embedded,
    unless it is an optional integration probed with the silent flag
  * nothing embedded is unused, and nothing embedded has been patched
  * no TOC declares an external Ace3 dependency and nothing outside the addon
    folder is referenced
  * the packager configuration ships Libs and cannot ship a nolib build

Case is checked by listing the directory rather than by opening the file,
because the filesystem here is case sensitive and Windows is not: a manifest
saying "libstub" would work for the developer and fail for half the players.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ADDON = os.path.join(ROOT, "WhatTheWhisper")
LIBS = os.path.join(ADDON, "Libs")

errors = []
notes = []


def err(message):
    errors.append(message)


def exists_exact(path):
    """True only if every path segment matches on disk exactly, case included."""
    path = os.path.normpath(path)
    if not path.startswith(ROOT):
        return False
    current = ROOT
    for part in os.path.relpath(path, ROOT).split(os.sep):
        try:
            entries = os.listdir(current)
        except OSError:
            return False
        if part not in entries:
            return False
        current = os.path.join(current, part)
    return True


# ---------------------------------------------------------------------------
# Manifests
# ---------------------------------------------------------------------------

ENTRY = re.compile(r'<(Script|Include)\s+file="([^"]+)"')


def walk(xml_path, order, seen=None):
    """Depth-first walk of a UI manifest, the way the client loads it."""
    seen = seen if seen is not None else set()
    if xml_path in seen:
        err("%s is included more than once" % os.path.relpath(xml_path, ROOT))
        return order
    seen.add(xml_path)
    if not exists_exact(xml_path):
        err("manifest missing or miscased: %s" % os.path.relpath(xml_path, ROOT))
        return order
    body = open(xml_path, encoding="utf-8").read()
    directory = os.path.dirname(xml_path)
    for tag, raw in ENTRY.findall(body):
        target = os.path.join(directory, *raw.replace("\\", "/").split("/"))
        if not exists_exact(target):
            err("%s names %s, which does not exist with that exact case"
                % (os.path.relpath(xml_path, ROOT), raw))
            continue
        if tag == "Script":
            order.append(target)
        else:
            walk(target, order, seen)
    return order


lib_order = walk(os.path.join(LIBS, "Libs.xml"), [])
lib_names = [os.path.relpath(p, LIBS).split(os.sep)[0] for p in lib_order]
notes.append("Libs.xml loads %d files: %s" % (len(lib_order), ", ".join(lib_names)))

# ---------------------------------------------------------------------------
# Load order
# ---------------------------------------------------------------------------

if not lib_names:
    err("Libs.xml loads nothing")
else:
    if lib_names[0] != "LibStub":
        err("LibStub must load first, but %s does" % lib_names[0])
    if "CallbackHandler-1.0" in lib_names:
        cb = lib_names.index("CallbackHandler-1.0")
        # Only the libraries that actually use it need to follow it.
        for dependent in ("AceEvent-3.0", "AceDB-3.0", "AceBucket-3.0", "AceTimer-3.0"):
            if dependent in lib_names and lib_names.index(dependent) < cb:
                err("%s loads before CallbackHandler-1.0, which it depends on" % dependent)
    for name in lib_names:
        if name != "LibStub" and lib_names.index(name) < lib_names.index("LibStub"):
            err("%s loads before LibStub" % name)

# Every library declares itself to LibStub with a MAJOR and a MINOR; a file that
# does not is not participating in the shared-version mechanism at all.
for path in lib_order:
    body = open(path, encoding="utf-8").read()
    name = os.path.basename(path)
    if name == "LibStub.lua":
        if "LIBSTUB_MAJOR, LIBSTUB_MINOR" not in body:
            err("LibStub.lua does not declare its own major/minor")
        if "if not LibStub or LibStub.minor < LIBSTUB_MINOR then" not in body:
            err("LibStub.lua does not guard against an older copy replacing a newer one")
        continue
    if not re.search(r'\bMAJOR\s*,\s*MINOR\s*=|\b\w*MAJOR\s*,\s*\w*MINOR\s*=', body):
        err("%s does not declare MAJOR/MINOR for LibStub registration" % name)
    if not re.search(r'LibStub:NewLibrary\(', body):
        err("%s does not register through LibStub:NewLibrary" % name)

# ---------------------------------------------------------------------------
# What the addon asks for at runtime must be what is embedded
# ---------------------------------------------------------------------------

addon_order = walk(os.path.join(ADDON, "WhatTheWhisper.xml"), [])
notes.append("WhatTheWhisper.xml loads %d files" % len(addon_order))

# LibStub("X") is a hard requirement; LibStub("X", true) is a soft probe that
# returns nil when absent, which is how an optional integration is written.
HARD = re.compile(r'LibStub\(\s*"([^"]+)"\s*\)')
SOFT = re.compile(r'LibStub\(\s*"([^"]+)"\s*,\s*true\s*\)')
MIXIN = re.compile(r'NewAddon\(\s*[^)]*?\)')

required, optional = set(), set()
for path in addon_order:
    body = open(path, encoding="utf-8").read()
    required.update(HARD.findall(body))
    optional.update(SOFT.findall(body))
    # Mixins named in NewAddon must be registered by load time too.
    for call in MIXIN.findall(body):
        for lib in re.findall(r'"(Ace\w+-[\d.]+)"', call):
            required.add(lib)
required -= optional

# A library required only by another embedded library still has to be there:
# nothing in the addon calls LibStub("CallbackHandler-1.0"), but AceEvent and
# AceDB both do, so the closure over the embedded sources is what matters.
transitive = set()
for path in lib_order:
    body = open(path, encoding="utf-8").read()
    for lib in HARD.findall(body) + re.findall(r'GetLibrary\(\s*"([^"]+)"', body):
        transitive.add(lib)
transitive -= {"LibStub"}
required |= (transitive & set(lib_names))

embedded = set(lib_names)
for lib in sorted(required):
    if lib not in embedded:
        err("%s is required at runtime but is not embedded" % lib)
for lib in sorted(embedded):
    if lib == "LibStub":
        continue        # every other library needs it, nothing names it
    if lib not in required:
        err("%s is embedded but nothing uses it" % lib)

notes.append("required: %s" % ", ".join(sorted(required)))
notes.append("optional (probed with the silent flag, not embedded): %s"
             % (", ".join(sorted(optional)) or "none"))

# ---------------------------------------------------------------------------
# TOCs
# ---------------------------------------------------------------------------

tocs = sorted(f for f in os.listdir(ADDON) if f.endswith(".toc"))
if not tocs:
    err("no TOC files")
for name in tocs:
    body = open(os.path.join(ADDON, name), encoding="utf-8").read()
    if re.search(r'^##\s*Dependencies\s*:', body, re.M | re.I):
        err("%s declares a hard Dependencies line; the addon must be standalone" % name)
    if re.search(r'^##\s*RequiredDeps\s*:', body, re.M | re.I):
        err("%s declares RequiredDeps; the addon must be standalone" % name)

    loaded = [line.strip() for line in body.split("\n")
              if line.strip() and not line.strip().startswith("#")]
    if "Libs\\Libs.xml" not in loaded:
        err("%s does not load Libs\\Libs.xml" % name)
    else:
        libs_at = loaded.index("Libs\\Libs.xml")
        if "WhatTheWhisper.xml" not in loaded:
            err("%s does not load WhatTheWhisper.xml" % name)
        elif loaded.index("WhatTheWhisper.xml") < libs_at:
            err("%s loads the addon before its libraries" % name)
    for entry in loaded:
        target = os.path.join(ADDON, *entry.replace("\\", "/").split("/"))
        if not exists_exact(target):
            err("%s names %s, which does not exist with that exact case" % (name, entry))
notes.append("%d TOC files, all standalone and loading Libs first" % len(tocs))

# ---------------------------------------------------------------------------
# Nothing may reach outside the addon folder
# ---------------------------------------------------------------------------

EXTERNAL = re.compile(r'Interface[\\/]+AddOns[\\/]+(?!WhatTheWhisper\b)(\w+)')
# Only paths that would actually load something count. An example path shown to
# the player as placeholder text -- "Interface\AddOns\YourAddon\sound.ogg" in
# the custom sound field -- names no real file and loads nothing.
ILLUSTRATIVE = re.compile(r'(caption|placeholder|example|tooltip)\s*=|^\s*--')
for path in addon_order + lib_order:
    for line in open(path, encoding="utf-8").read().split("\n"):
        if ILLUSTRATIVE.search(line):
            continue
        for other in set(EXTERNAL.findall(line)):
            err("%s refers to another addon folder: %s"
                % (os.path.relpath(path, ROOT), other))

# The repository must not still assume a sibling Ace3 checkout anywhere that
# ships or that the tests read.
for base, dirs, files in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in (".git", "__pycache__", "preview")]
    if os.path.relpath(base, ROOT).split(os.sep)[0] == "Ace3":
        continue
    for name in files:
        if not name.endswith((".lua", ".py", ".sh", ".toc", ".xml", ".md", ".pkgmeta")):
            continue
        path = os.path.join(base, name)
        if os.path.relpath(path, ROOT) == os.path.join("Tools", "test", "check_libs.py"):
            continue
        body = open(path, encoding="utf-8", errors="replace").read()
        for match in re.finditer(r'["\'](\.\./)?Ace3/', body):
            err("%s still loads from the external Ace3 folder" % os.path.relpath(path, ROOT))
            break

# ---------------------------------------------------------------------------
# The embedded copies must be untouched upstream
# ---------------------------------------------------------------------------

# Another addon may end up using whichever copy of a library loads first, so a
# local edit here would silently become their code too. Hashes make that an
# enforced rule rather than a comment: any edit, however well meant, fails here.
import hashlib
import json

manifest_path = os.path.join(LIBS, "Libs.manifest.json")
if not os.path.exists(manifest_path):
    err("Libs.manifest.json is missing; run Tools/gen_lib_manifest.py")
else:
    manifest = json.load(open(manifest_path, encoding="utf-8"))
    recorded = manifest.get("files", {})
    on_disk = {}
    for base, _dirs, names in os.walk(LIBS):
        for name in names:
            if not name.endswith((".lua", ".xml")):
                continue
            rel = os.path.relpath(os.path.join(base, name), LIBS).replace(os.sep, "/")
            if rel == "Libs.xml":
                continue
            with open(os.path.join(base, name), "rb") as fh:
                on_disk[rel] = hashlib.sha256(fh.read()).hexdigest()

    for rel, digest in sorted(recorded.items()):
        if rel not in on_disk:
            err("%s is in the manifest but missing from Libs/" % rel)
        elif on_disk[rel] != digest:
            err("%s has been modified; embedded libraries must stay upstream "
                "(if this is a deliberate library update, rerun "
                "Tools/gen_lib_manifest.py)" % rel)
    for rel in sorted(on_disk):
        if rel not in recorded:
            err("%s is in Libs/ but not in the manifest" % rel)

    # A set assembled from different Ace3 releases is where subtle incompatibilities
    # come from, so the recorded revisions are reported for review on every run.
    versions = manifest.get("versions", {})
    notes.append("revisions: " + ", ".join(
        "%s r%d" % (k, v) for k, v in sorted(versions.items())))
    for name in lib_names:
        if name not in versions:
            err("%s registers no revision the manifest could record" % name)

# ---------------------------------------------------------------------------
# Packaging
# ---------------------------------------------------------------------------

pkgmeta = os.path.join(ROOT, ".pkgmeta")
if not os.path.exists(pkgmeta):
    err("no .pkgmeta: the packager would zip the repository root")
else:
    body = open(pkgmeta, encoding="utf-8").read()
    if not re.search(r'^package-as:\s*WhatTheWhisper\s*$', body, re.M):
        err(".pkgmeta does not package as WhatTheWhisper")
    if re.search(r'^externals:', body, re.M):
        err(".pkgmeta declares externals; the libraries are committed, and a "
            "failed fetch would ship an archive with no Libs folder")
    if not re.search(r'^enable-nolib-creation:\s*no\s*$', body, re.M):
        err(".pkgmeta does not disable nolib creation; a nolib build of a "
            "standalone addon has no libraries and cannot load")
    # An ignore rule that swallowed the libraries is the exact failure this
    # whole exercise exists to prevent.
    for line in body.split("\n"):
        entry = line.strip().lstrip("-").strip()
        if entry and not entry.endswith(":") and not line.strip().startswith("#"):
            if "Libs" in entry and ":" not in entry:
                err(".pkgmeta ignores %s, which would strip the libraries" % entry)
    notes.append(".pkgmeta packages WhatTheWhisper with no externals and no nolib build")

# The libraries have to be real files in the repository, not a submodule stub.
for name in lib_names:
    directory = os.path.join(LIBS, name)
    if not os.path.isdir(directory):
        err("%s is not a directory in Libs/" % name)
    elif not any(f.endswith(".lua") for f in os.listdir(directory)):
        err("%s contains no Lua; is it an unfetched submodule?" % name)

gitmodules = os.path.join(ROOT, ".gitmodules")
if os.path.exists(gitmodules):
    if "Libs" in open(gitmodules, encoding="utf-8").read():
        err("the libraries are a git submodule; a CurseForge checkout would be empty")

print("\n".join("  " + n for n in notes))
if errors:
    print("\nLIBRARY ERRORS:")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("libraries ok")
