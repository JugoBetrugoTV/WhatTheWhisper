#!/bin/sh
# Full verification: syntax, static analysis, atlas consistency, and the addon
# actually running under the mock client on every supported flavour.
#
# Every Lua suite reports "<n> passed, <m> failed" on its last line. Those are
# added up here rather than anywhere else, so the total is something the suite
# calculated and not something anybody typed.
set -e
cd "$(dirname "$0")/../.."

TOTAL_PASS=0
TOTAL_FAIL=0

# Runs one Lua suite, prints its own count, and folds it into the totals.
suite() {
	label="$1"
	shift
	line=$(lua5.1 "$@" 2>&1 | tail -1)
	p=$(printf '%s' "$line" | sed -n 's/^[^0-9]*\([0-9][0-9]*\) passed.*/\1/p')
	f=$(printf '%s' "$line" | sed -n 's/.*, *\([0-9][0-9]*\) failed.*/\1/p')
	[ -n "$p" ] || { printf '  %-26s %s\n' "$label" "$line"; exit 1; }
	printf '  %-26s %6s passed %4s failed\n' "$label" "$p" "$f"
	TOTAL_PASS=$((TOTAL_PASS + p))
	TOTAL_FAIL=$((TOTAL_FAIL + f))
}

echo "== syntax =="
luac5.1 -p $(find WhatTheWhisper -name '*.lua')
echo "ok"

echo "== luacheck =="
luacheck WhatTheWhisper --no-color | tail -1

echo "== atlases =="
python3 Tools/test/check_icons.py

echo "== textures =="
python3 Tools/test/check_textures.py | tail -1

echo "== icon legibility =="
python3 Tools/test/check_icon_legibility.py 2>/dev/null | tail -1

echo "== locales =="
python3 Tools/test/check_locales.py | tail -1

echo "== structure =="
python3 Tools/test/check_structure.py | tail -1

echo "== icon manifest =="
python3 Tools/gen_icon_manifest.py --check

echo "== embedded libraries =="
python3 Tools/test/check_libs.py | tail -1

echo "== packaged release =="
python3 Tools/test/check_package.py | tail -1

echo "== suites =="
suite "library coexistence"   Tools/test/libs.lua
suite "real-client loadability" Tools/test/loadability.lua
suite "text processing"       Tools/test/text.lua
suite "whisper pipeline"      Tools/test/whisper.lua
suite "history"               Tools/test/history.lua
suite "leaks and churn"       Tools/test/perf.lua
suite "combat lockdown"       Tools/test/combat.lua
suite "settings"              Tools/test/settings.lua
suite "commands and debug"    Tools/test/commands.lua
suite "search"                Tools/test/search.lua
suite "modern API only"       Tools/test/modern.lua
suite "icons: drop-in"        Tools/test/icons.lua
suite "icons: blind client"   Tools/test/icons.lua blind
suite "restricted content"    Tools/test/arena.lua
suite "presence and profile"  Tools/test/presence.lua
suite "minimap button"        Tools/test/minimap.lua
suite "ui geometry"           Tools/test/ui.lua

echo "== languages =="
for client in enUS koKR zhCN zhTW; do
	suite "locale: $client" Tools/test/locale.lua "$client"
done

echo "== per-flavour behaviour =="
for flavor in retail modern mop tbc classic fallback; do
	suite "flavour: $flavor" Tools/test/flavour.lua "$flavor"
done

echo "== mock client boots =="
for flavor in retail modern mop tbc classic fallback; do
	printf '  %-26s ' "$flavor"
	lua5.1 Tools/test/run.lua "$flavor" 2>&1 | tail -1
done
for locale in deDE ruRU koKR; do
	printf '  %-26s ' "locale $locale"
	lua5.1 Tools/test/run.lua retail "$locale" 2>&1 | tail -1
done

echo
printf '  %-26s %6s passed %4s failed\n' "TOTAL" "$TOTAL_PASS" "$TOTAL_FAIL"
[ "$TOTAL_FAIL" -eq 0 ] || exit 1
