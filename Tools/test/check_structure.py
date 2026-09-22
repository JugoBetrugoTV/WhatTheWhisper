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

# A TOC's suffix is how the client picks the file; its Interface line is how the
# client decides whether to trust it. Those two have to agree, and nothing said
# so until a Forever manifest was copied from the Classic Era one: the client
# would have loaded WhatTheWhisper_Camelot.toc and then marked the addon out of
# date, which is a failure that looks nothing like a wrong number in a file.
#
# The ranges are the client lines themselves: Retail is 1xxxxx, Forever is 1.60+
# (16xxx-19xxx), MoP Classic 5.x, TBC 2.x, Classic Era 1.13-1.15.
TOC_SUFFIX_INTERFACE = {
    "Mainline": (100000, 999999),
    "Camelot": (16000, 19999),
    "Mists": (50000, 59999),
    "TBC": (20000, 29999),
    "Vanilla": (11300, 11599),
}
seen_interface = {}
for toc in tocs:
    text = open(os.path.join(ADDON, toc), encoding="utf-8").read()
    stem = os.path.splitext(toc)[0]
    suffix = stem.split("_", 1)[1] if "_" in stem else None
    if suffix is None:
        # The unsuffixed fallback manifest serves whatever the client is, so
        # there is no range to hold it to.
        continue
    if suffix not in TOC_SUFFIX_INTERFACE:
        err("%s has a suffix no client claims: %s" % (toc, suffix))
        continue
    stated = re.search(r'^## Interface:\s*(\d+)', text, re.M)
    if not stated:
        err("%s has no readable Interface number" % toc)
        continue
    value = int(stated.group(1))
    low, high = TOC_SUFFIX_INTERFACE[suffix]
    if not low <= value <= high:
        err("%s is the %s manifest but states interface %d, which is not a %s "
            "build (%d-%d)" % (toc, suffix, value, suffix, low, high))
    if value in seen_interface:
        err("%s and %s both state interface %d; one of them is a copy nobody "
            "finished" % (seen_interface[value], toc, value))
    seen_interface[value] = toc
    flavor = re.search(r'^## X-Flavor:\s*(\S+)', text, re.M)
    if flavor and flavor.group(1) != suffix:
        err("%s says X-Flavor %s but is named for %s"
            % (toc, flavor.group(1), suffix))
if len(seen_interface) < 4:
    err("only %d suffixed manifests checked; the client line coverage has "
        "shrunk" % len(seen_interface))
notes.append("%d client manifests, each stating an interface its client accepts"
             % len(seen_interface))

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
# Measuring text at one size and drawing it at another.
#
# Three separate controls have shipped this bug: the context menu measured its
# entries at SMALL and drew them at BODY and came out a sixth too narrow; the
# slider measured its readout at SMALL and drew it at SUBHEAD and clipped
# "5 seconds"; the segmented control did the same and cut "Sidebar" to "Sid...".
#
# Every one was silent -- the layout is computed from the measurement, so it is
# self-consistently wrong -- and every one only showed up at a font size nobody
# was testing by eye.
#
# The rule: a file that measures at a size must also draw at it. That does not
# prove the measurement is used for the right thing, but it catches the whole
# family, because in each case the drawn token was absent from the measured set.

MEASURE = re.compile(r'Theme\.Measure\(\s*"([A-Z_]+)"\s*\)')
DRAWN = re.compile(r'W\.Text\([^,]+,\s*"([A-Z_]+)"|Theme\.Font\(\s*"([A-Z_]+)"\s*\)'
                   r'|SetFontObject\(Theme\.Font\(\s*"([A-Z_]+)"')
for rel in declared:
    body = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    measured = set(MEASURE.findall(body))
    if not measured:
        continue
    drawn = set()
    for groups in DRAWN.findall(body):
        drawn.update(g for g in groups if g)
    # A file that names its size in a constant and passes the constant around is
    # doing the right thing and shows up as neither measured nor drawn.
    for token in sorted(measured - drawn):
        if drawn:
            err("%s measures text at %s but never draws at it (draws at %s). "
                "Measuring at one size and drawing at another is how a column "
                "ends up narrower than the words in it."
                % (rel, token, ", ".join(sorted(drawn))))
notes.append("text measured at the size it is drawn at")

# ---------------------------------------------------------------------------
# One API that must not come back.
#
# C_ChatInfo.AreOutgoingAddonChatMessagesRestricted answers "may addons send on
# the hidden channel they use to talk to each other", and it is a realm setting:
# on an ordinary realm it says restricted, permanently. It reads like the answer
# to "may this whisper be sent", and this addon believed that and refused every
# message anybody typed.
#
# This addon sends no addon messages at all, so there is no correct caller for
# it here. Naming it in a comment is fine -- that is how the next person finds
# out why -- but calling it is the bug, so calling it is what fails.

FORBIDDEN_CALL = "AreOutgoingAddonChatMessagesRestricted"
for rel in declared:
    body = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    for line_no, line in enumerate(body.split("\n"), 1):
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        if FORBIDDEN_CALL in stripped:
            err("%s:%d calls %s. That is a realm setting about addon-to-addon "
                "messages, not about whether a whisper may be sent; use "
                "Compat.OutgoingChatRestricted, which asks "
                "InChatMessagingLockdown" % (rel, line_no, FORBIDDEN_CALL))
notes.append("the addon-comms restriction is not consulted for player chat")

# ---------------------------------------------------------------------------
# Every icon the UI asks for must resolve to art that exists.
#
# Icons are named for what they mean, and the name is looked up at runtime. A
# typo, or a semantic name nobody wired to a cell of the sheet, produces a
# texture with nothing on it -- a button that is there, takes clicks, and cannot
# be seen. In the source it looks exactly like a working one, so it has to be
# caught here.

_atlas = open(os.path.join(ADDON, "UI/IconAtlas.lua"), encoding="utf-8").read()
ATLAS_KEYS = set(re.findall(r'^\t([a-z_0-9]+)\s*=\s*\{', _atlas, re.M))

_icons = open(os.path.join(ADDON, "UI/Icons.lua"), encoding="utf-8").read()
_alias_block = re.search(r'local ATLAS_ALIAS = \{(.*?)\n\}', _icons, re.S)
ALIAS = dict(re.findall(r'(\w+)\s*=\s*"([a-z_0-9]+)"', _alias_block.group(1)))
_repl_block = re.search(r'Icons\.REPLACEABLE = \{(.*?)\n\}', _icons, re.S)
REPLACEABLE = set(re.findall(r'^\t(\w+)\s*=\s*\{', _repl_block.group(1), re.M))

# Where an icon name is chosen. The name itself is picked out of the whole
# expression rather than the position after the comma, because half of these are
# conditional -- `icon = conv.pinned and "pin" or "unpin"` names two icons, and a
# pattern that only understood the first would miss whichever one was broken.
# Each form says which argument carries the name. -1 means "the last one", which
# is how SetIcon is called both with and without a texture in front of the name.
ICON_FORMS = (
    (re.compile(r'\bW\.Icon\('), 1),
    (re.compile(r'\bSetIcon\('), -1),
    (re.compile(r'\btitleButton\('), 0),
    (re.compile(r'\bAddHeaderButton\('), 0),
    (re.compile(r'\bicon\s*=\s*'), 0),
)
NAME = re.compile(r'"([a-z_0-9]+)"')

def split_args(text):
    """Arguments of a call, split on commas that are not inside brackets."""
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

def icon_names(body):
    """Yields (name, line) for every icon named anywhere in the file.

    The name is taken from one argument, and every string literal inside that
    argument counts: half these calls are conditional, and
    `icon = conv.pinned and "pin" or "unpin"` names two icons in one place.
    Widening it to the whole line instead would sweep up the colour role that
    follows, which is a string and is not an icon.
    """
    for line_no, line in enumerate(body.split("\n"), 1):
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
            for name in NAME.findall(arg):
                yield name, line_no
            break

unresolved = []
drawn = set()
for rel in declared:
    if rel in ("UI/IconAtlas.lua", "UI/Icons.lua", "UI/EmojiAtlas.lua"):
        continue
    body = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    for name, line in icon_names(body):
        drawn.add(name)
        if ALIAS.get(name, name) in ATLAS_KEYS:
            continue
        unresolved.append("%s:%d asks for icon %r, which is neither a cell of "
                          "Art/Icons nor an alias for one" % (rel, line, name))
for one in unresolved:
    err(one)

# The reverse: a name offered for replacement that nothing draws is a file we
# would be asking somebody to produce for no reason.
for name in sorted(REPLACEABLE - drawn):
    err("UI/Icons.lua offers %r for replacement but nothing in the addon draws "
        "it; docs/ICON-REPLACEMENT.md would be asking for art nobody sees"
        % name)

notes.append("%d icon references resolved against %d sheet cells"
             % (len(drawn), len(ATLAS_KEYS)))

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

# ------------------------------------------------- who may read a player --
# Some client calls answer with a *secret value* in restricted content: in an
# arena an opponent's name is deliberately not knowable, and reading one -- even
# comparing it to the empty string -- is a hard error that taints the caller.
# There is one probe for that, Compat.UnitFullName, and the only way to keep it
# from being bypassed by the next person who needs a unit's name is to make
# bypassing it fail here.
GUARDED_CALLS = ("UnitName", "UnitFullName", "GetUnitName")
# Client namespaces and globals that only Compat may reach for. Some of these
# are being moved by Blizzard (chat behind C_ChatInfo, Battle.net behind
# C_BattleNet); some exist on one flavour and not another. Either way the rest of
# the addon asks Compat, so there is one place to change when the client does.
GUARDED_GLOBALS = (
    "C_ChatInfo", "C_BattleNet", "C_FriendList", "SendChatMessage",
    "BNSendWhisper", "FlashClientIcon", "GetCVar", "SetCVar",
    "GetPlayerInfoByGUID", "AddonCompartmentFrame",
)
# Compat is where the probe lives, so it is the one place allowed to call them.
GUARD_HOME = "Core/Compat/"
guarded_pattern = re.compile(r'(?<![\w.])(' + "|".join(GUARDED_CALLS) + r')\s*\(')
global_pattern = re.compile(r'_G\.(' + "|".join(GUARDED_GLOBALS) + r')\b')
bypasses = 0
for rel in declared:
    if rel.startswith(GUARD_HOME):
        continue
    body = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    for match in guarded_pattern.finditer(body):
        line = body[:match.start()].count("\n") + 1
        err("%s:%d calls %s directly; use Compat.UnitFullName, which asks the "
            "client whether the name may be read before reading it"
            % (rel, line, match.group(1)))
    for match in global_pattern.finditer(body):
        line = body[:match.start()].count("\n") + 1
        err("%s:%d reaches for %s directly; the client moves these around and "
            "not every flavour has them, so they belong behind Compat"
            % (rel, line, match.group(1)))
    bypasses += 1
notes.append("%d files checked for client calls that belong behind Compat" % bypasses)

# --- settings are read through ns.Setting, not indexed two levels deep ------
#
# AceDB strips every value that equals its default out of the profile at
# PLAYER_LOGOUT, so `db.profile` outlives the sections under it and the addon
# keeps running for a while in that state. A read of the shape
# `db.profile.animations.level` throws there, and a guard that stops at
# `db.profile` does not help -- it survives the missing database and falls over
# on the missing section. Twenty of them did.
#
# ns.Setting walks the whole path and falls back to the shipped default, so the
# rule is simply: do not index two levels below the profile by hand. Writes are
# exempt, because a write has to reach the real table; they take the store and
# check it is there, which the reader cannot do.
PROFILE_READ = re.compile(
    r'(?<![\w.])(?:ns\.)?db\.profile'          # db.profile / ns.db.profile
    r'((?:\.[A-Za-z_]\w*)+)'                   # .section.key...
    r'\s*(?!=[^=])'                             # not the target of an assignment
)
setting_offenders = 0
for rel in declared:
    body = open(os.path.join(ADDON, rel), encoding="utf-8").read()
    # The helper itself, and the two files that legitimately hold a store.
    if rel == "Core/Namespace.lua":
        continue
    for line_no, line in enumerate(body.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        for match in PROFILE_READ.finditer(line):
            path = match.group(1)
            depth = path.count(".")
            if depth < 2:
                continue        # db.profile.section is a whole section: fine
            after = line[match.end():].lstrip()
            if after.startswith("=") and not after.startswith("=="):
                continue        # a write, which needs the real table
            # A read guarded all the way down is fine too.
            parent = "db.profile" + path.rsplit(".", 1)[0]
            if parent + " and" in line or parent + " then" in line:
                continue
            err("%s:%d reads db.profile%s by hand; use ns.Setting(\"%s\") so a "
                "stripped profile falls back to the default instead of throwing"
                % (rel, line_no, path, path.lstrip(".")))
            setting_offenders += 1
notes.append("%d files checked for settings read past a section that can be gone"
             % len(declared))

# --- DESIGN.md's metrics table must be the code's metrics ------------------
#
# The table in section 1.2 is the design contract, and a contract that drifts is
# worse than none: every number in it was wrong by the time anybody looked,
# because nothing made them wrong out loud. Now they do.
design_path = os.path.join(ADDON, "DESIGN.md")
design = open(design_path, encoding="utf-8").read()
namespace_src = open(os.path.join(ADDON, "Core/Namespace.lua"), encoding="utf-8").read()


def _namespace_table(name):
    start = namespace_src.index("ns.%s = {" % name)
    depth, i = 0, start
    while True:
        if namespace_src[i] == "{":
            depth += 1
        elif namespace_src[i] == "}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = namespace_src[start:i]
    out = {}
    for key, value in re.findall(r'^\s*(\w+)\s*=\s*([0-9.]+)\s*,', body, re.M):
        out[key] = value
    return out


NS_TABLES = {"SZ": _namespace_table("SZ"), "S": _namespace_table("S"),
             "R": _namespace_table("R"), "T": _namespace_table("T")}


def _lookup(name):
    for table in ("SZ", "S", "R", "T"):
        if name in NS_TABLES[table]:
            return NS_TABLES[table][name]
    return None


DESIGN_ROW = re.compile(r'^\|\s*`([A-Z][A-Z0-9_]*)`\s*\|\s*([0-9.]+)\s*\|', re.M)
checked_rows = 0
for name, stated in DESIGN_ROW.findall(design):
    actual = _lookup(name)
    if actual is None:
        err("DESIGN.md quotes %s, which is not a constant in Namespace.lua" % name)
        continue
    if float(actual) != float(stated):
        err("DESIGN.md says %s is %s; Namespace.lua says %s"
            % (name, stated, actual))
    checked_rows += 1
if checked_rows < 30:
    err("only %d metrics checked against DESIGN.md; the table has stopped being "
        "read" % checked_rows)
notes.append("%d design metrics checked against the code" % checked_rows)

print("\n".join("  " + n for n in notes))
if errors:
    print("\nSTRUCTURE ERRORS:")
    for e in errors:
        print("  " + e)
    sys.exit(1)
print("structure ok")
