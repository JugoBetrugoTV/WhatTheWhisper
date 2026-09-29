"""Locale files must not drift: no key in a translation that the source lacks.

The tables are plain Lua, so they are read with a regex rather than executed.
That is deliberate -- a locale file that needs a Lua interpreter to tell you
what is in it is a locale file nobody will keep up to date.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LOCALE_DIR = os.path.join(ROOT, "WhatTheWhisper/Core/Locale")

# ["some key"] = <value>   -- the value is either `true` or a quoted string. In
# the source language `true` means "the key is the text"; in a translation it
# means "the English is right here too", which is the honest answer for a
# product name or a file format and is counted as done.
ENTRY = re.compile(r'^\s*\[("(?:[^"\\]|\\.)*")\]\s*=\s*(true\b|")', re.M)
# Registered here, so the file is one of ours and not a helper that happens to
# live in the folder.
REGISTER = re.compile(r'ns\.RegisterLocale\(\s*"([A-Za-z]+)"')
# Key and value together, including the values that wrap onto the next line.
PAIR = re.compile(r'\[("(?:[^"\\]|\\.)*")\]\s*=\s*(?:\n\s*)?(true\b|"(?:[^"\\]|\\.)*")')
# Marks that carry meaning rather than grammar: a label that trails off, or one
# that asks a question, reads wrong without them, and they are what a hurried
# translation drops. CJK writes its own, so each mark lists its variants.
PUNCTUATION = [("...", ("...", "…", "……")), ("?", ("?", "？"))]


def entries(path):
    """[(key, is_translated)] in file order."""
    text = open(path, encoding="utf-8").read()
    return [(key, kind == '"') for key, kind in ENTRY.findall(text)]


def declared_code(path):
    match = REGISTER.search(open(path, encoding="utf-8").read())
    return match.group(1) if match else None


def duplicates(pairs):
    """A repeated key is silent: the later line wins and the earlier one is
    dead. That is how a typo in a translation hides -- the file still has the
    right number of entries and one of them never renders."""
    seen, repeated = set(), []
    for key, _ in pairs:
        if key in seen:
            repeated.append(key)
        seen.add(key)
    return repeated


def locale_files():
    for name in sorted(os.listdir(LOCALE_DIR)):
        if not name.endswith(".lua") or name == "Locale.lua":
            continue
        yield name, os.path.join(LOCALE_DIR, name)


failed = False

source_pairs = entries(os.path.join(LOCALE_DIR, "enUS.lua"))
source = set(key for key, _ in source_pairs)

# Every locale the picker offers must actually exist, and every file must
# register under the name it is filed as. A picker entry with no table behind
# it is an option that silently does nothing.
listed = re.findall(r'code\s*=\s*"([A-Za-z]+)"',
                    open(os.path.join(LOCALE_DIR, "Locale.lua"), encoding="utf-8").read())
present = {}
for name, path in locale_files():
    code = declared_code(path)
    if code is None:
        failed = True
        print("%s: does not call ns.RegisterLocale" % name)
        continue
    if code != name[:-4]:
        failed = True
        print("%s: registers as %s" % (name, code))
    present[code] = name

for code in listed:
    if code not in present:
        failed = True
        print("Locale.lua offers %s in the picker but there is no %s.lua" % (code, code))
for code in sorted(present):
    if code not in listed:
        failed = True
        print("%s.lua exists but Locale.lua does not offer it in the picker" % code)

for name, path in locale_files():
    repeated = duplicates(entries(path))
    if repeated:
        failed = True
        print("%s: the same key is defined twice, so the first one is dead:" % name)
        for key in sorted(set(repeated)):
            print("    " + key)

for name, path in locale_files():
    if name == "enUS.lua":
        continue
    pairs = entries(path)
    other = set(key for key, _ in pairs)
    verbatim = set(key for key, done in pairs if not done)
    extra = other - source
    missing = source - other
    note = "  (%d left in English on purpose)" % len(verbatim) if verbatim else ""
    print("%s: %d/%d covered%s" % (name, len(other & source), len(source), note))
    if extra:
        failed = True
        print("  keys not present in enUS:")
        for key in sorted(extra):
            print("    " + key)
    # A locale that is only half written still works -- the lookup falls back to
    # English -- but it must be half written on purpose, not because a key was
    # dropped in an edit. Shipping locales are held to the full set.
    if missing:
        failed = True
        print("  keys missing (%d):" % len(missing))
        for key in sorted(missing)[:20]:
            print("    " + key)
        if len(missing) > 20:
            print("    ... and %d more" % (len(missing) - 20))

# Punctuation and spacing, which drift silently: nothing breaks, the label just
# reads as though nobody proofread it.
for name, path in locale_files():
    if name == "enUS.lua":
        continue
    text = open(path, encoding="utf-8").read()
    for key, value in PAIR.findall(text):
        if value == "true" or key not in source:
            continue
        body = value[1:-1]
        for mark, variants in PUNCTUATION:
            if key[1:-1].endswith(mark) != body.endswith(variants):
                failed = True
                print("%s: %s -> %s\n    ends in %r on one side only"
                      % (name, key, value, mark))
        if "  " in body:
            failed = True
            print("%s: %s -> %s\n    has a double space" % (name, key, value))

print("enUS: %d strings" % len(source))
sys.exit(1 if failed else 0)
