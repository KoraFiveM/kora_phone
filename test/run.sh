#!/usr/bin/env bash
# Runs the whole kora_phone test suite and prints a summary table. Non-zero exit when anything fails.
#   LUA=lua5.4 bash test/run.sh     (LUA defaults to lua5.4)
# Order: Lua tests, Node contract tests, print guard, SDK tests, web typecheck.
# The SDK and web steps need node_modules (npm ci); they are SKIPPED with a message when it is absent.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lua_bin="${LUA:-lua5.4}"
cd "$root" || exit 1

names=()
results=()
status=0

# record <name> <command...>: runs the command, keeps its output only on failure.
record() {
    local name="$1"; shift
    local log
    log="$(mktemp)"
    if "$@" >"$log" 2>&1; then
        results+=("PASS")
    else
        results+=("FAIL")
        status=1
        echo "---- $name failed ----"
        tail -n 25 "$log"
        echo
    fi
    names+=("$name")
    rm -f "$log"
}

skip() {
    names+=("$1")
    results+=("SKIP")
    echo "SKIP $1: $2"
}

for file in tests/*.test.lua; do
    record "$file" "$lua_bin" "$file"
done

# tests/customapps-host.test.js wires the real SDK build (sdk/dist, gitignored) to the host router.
if [ -d sdk/node_modules ]; then
    (cd sdk && npm run build >/dev/null 2>&1) || echo "WARN: sdk build failed; tests that need sdk/dist will fail"
fi

for file in tests/*.test.js; do
    record "$file" node "$file"
done

record "test/no_raw_print.lua" "$lua_bin" test/no_raw_print.lua

if [ -d sdk/node_modules ]; then
    record "sdk: npm test" bash -c 'cd sdk && npm test'
else
    skip "sdk: npm test" "sdk/node_modules is missing (run: cd sdk && npm ci)"
fi

if [ -d web/node_modules ]; then
    record "web: tsc --noEmit" bash -c 'cd web && npx tsc --noEmit'
else
    skip "web: tsc --noEmit" "web/node_modules is missing (run: cd web && npm ci)"
fi

echo
printf '%-6s %s\n' "RESULT" "TEST"
pass=0; fail=0; skipped=0
for i in "${!names[@]}"; do
    printf '%-6s %s\n' "${results[$i]}" "${names[$i]}"
    case "${results[$i]}" in
        PASS) pass=$((pass + 1)) ;;
        FAIL) fail=$((fail + 1)) ;;
        *) skipped=$((skipped + 1)) ;;
    esac
done
echo
echo "passed: $pass  failed: $fail  skipped: $skipped"
exit "$status"
