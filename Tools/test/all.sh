#!/bin/sh
# Full verification: syntax, static analysis, atlas consistency, and the addon
# actually running under the mock client on all four target flavours.
set -e
cd "$(dirname "$0")/../.."

echo "== syntax =="
luac5.1 -p $(find WhatTheWhisper -name '*.lua')
echo "ok"

echo "== luacheck =="
luacheck WhatTheWhisper --no-color | tail -1

echo "== atlases =="
python3 Tools/test/check_icons.py

echo "== locales =="
python3 Tools/test/check_locales.py

echo "== structure =="
python3 Tools/test/check_structure.py

echo "== whisper pipeline =="
lua5.1 Tools/test/whisper.lua | tail -1

echo "== history and saved variables =="
lua5.1 Tools/test/history.lua | tail -1

echo "== mock client =="
for flavor in retail mop tbc classic; do
	printf '%-9s ' "$flavor"
	lua5.1 Tools/test/run.lua "$flavor" 2>&1 | tail -1
done
for locale in deDE; do
	printf '%-9s ' "$locale"
	lua5.1 Tools/test/run.lua retail "$locale" 2>&1 | tail -1
done
