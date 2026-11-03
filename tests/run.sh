#!/usr/bin/env bash
# Runs every test in tests/ plus a syntax check of the Lua sources. Run from anywhere:  bash tests/run.sh
# JS tests that need the web dependencies (npm ci --prefix web) are skipped when those are not installed.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1
lua_bin="${LUA:-lua5.4}"
luac_bin="${LUAC:-luac5.4}"
status=0

run() {
    echo "== $*"
    if ! "$@"; then echo "FAIL: $*"; status=1; fi
}

for file in tests/*.test.lua; do run "$lua_bin" "$file"; done
# The shell tests need a disposable MariaDB (QBPHONE_TEST_SOCKET / QBPHONE_TEST_DATABASE); skip them otherwise.
for file in tests/*.test.sh; do
    if [ -z "${QBPHONE_TEST_SOCKET:-}" ]; then echo "== SKIP $file (no disposable database configured)"; continue; fi
    run bash "$file"
done
for file in tests/*.test.js; do
    if [ "$file" = "tests/game-recording.test.js" ] && [ ! -d web/node_modules/typescript ]; then
        echo "== SKIP $file (run npm ci --prefix web first)"
        continue
    fi
    run node "$file"
done

echo "== luac -p"
while IFS= read -r file; do
    if ! "$luac_bin" -p "$file"; then echo "LUAC FAIL: $file"; status=1; fi
done < <(find client server shared config tests -name '*.lua' | sort)

exit "$status"
