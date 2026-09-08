"""Locale files must not drift: no key in a translation that the source lacks."""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LOCALE_DIR = os.path.join(ROOT, "WhatTheWhisper/Core/Locale")

KEY = re.compile(r'^L\[("(?:[^"\\]|\\.)*")\]', re.M)


def keys(path):
    return set(KEY.findall(open(path, encoding="utf-8").read()))


def duplicates(path):
    """A repeated key is silent: the later line wins and the earlier one is
    dead. That is how a typo in a translation hides -- the file still has the
    right number of entries and one of them never renders."""
    seen, repeated = set(), []
    for key in KEY.findall(open(path, encoding="utf-8").read()):
        if key in seen:
            repeated.append(key)
        seen.add(key)
    return repeated


source = keys(os.path.join(LOCALE_DIR, "enUS.lua"))
failed = False
for name in sorted(os.listdir(LOCALE_DIR)):
    if not name.endswith(".lua"):
        continue
    repeated = duplicates(os.path.join(LOCALE_DIR, name))
    if repeated:
        failed = True
        print("%s: the same key is defined twice, so the first one is dead:" % name)
        for key in sorted(set(repeated)):
            print("    " + key)
for name in sorted(os.listdir(LOCALE_DIR)):
    if not name.endswith(".lua") or name == "enUS.lua":
        continue
    other = keys(os.path.join(LOCALE_DIR, name))
    extra = other - source
    print("%s: %d/%d translated" % (name, len(other & source), len(source)))
    if extra:
        failed = True
        print("  keys not present in enUS:")
        for key in sorted(extra):
            print("    " + key)

print("enUS: %d strings" % len(source))
sys.exit(1 if failed else 0)
