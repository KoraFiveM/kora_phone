# Tests

Run everything from the resource root with one command:

```bash
LUA=lua5.4 bash test/run.sh
```

`test/run.sh` runs all Lua tests (`tests/*.test.lua`), all Node tests (`tests/*.test.js`), the raw-print guard (`test/no_raw_print.lua`), the SDK package tests (`cd sdk && npm test`) and the web type check (`cd web && npx tsc --noEmit`). It prints a PASS, FAIL or SKIP line per step and a summary, and exits non-zero when any step fails. The SDK and web steps are skipped with a message when `sdk/node_modules` or `web/node_modules` is missing (run `npm ci` in `sdk/` and `web/`). `LUA` defaults to `lua5.4`. Because the runner picks files by glob, a new `tests/*.test.lua` or `tests/*.test.js` file is included automatically.

To run a single check:

```bash
lua5.4 tests/schema.test.lua
lua5.4 tests/call-startup.test.lua '../../[pre]/kora_lib' # optional startup check against real kora_lib exports
node tests/routes-contract.test.js
lua5.4 test/no_raw_print.lua
cd sdk && npm test
cd web && npx tsc --noEmit
```

## How the tests work

- **Lua tests** run without FiveM. They load the real server or client files into a mock environment (`tests/helpers/`, `tests/sdk-helper.lua`). `tests/config_shim.lua` stands in for `Kora.config`: it returns the authored defaults as a plain table and does not validate them. To check the config schema itself, load `config/*.lua` through kora_lib's real `modules/config/consumer.lua` ([Configuration](../docs/configuration.md#checking-a-change)).
- **Node tests** use only Node built-ins. Some read the Lua or TypeScript source and assert contracts (for example `routes-contract.test.js` for `shared/routes.json`, `schema-manifest.test.js` for the schema and the rule that all SQL lives in `server/repositories/`); others transpile the web TypeScript to a temporary directory and exercise it (`customapps-host.test.js`, `api-adapters.test.js`).
- **Tests that assert old behaviour must be updated, not removed,** when the behaviour changes on purpose.

## What is covered

| Area | Files |
| --- | --- |
| Config, schema, validation, routes | `schema.test.lua`, `schema-manifest.test.js`, `validation.test.lua`, `routes-contract.test.js`, `gateway.test.lua`, `web-contract.test.js` |
| App SDK (server) | `sdk-manifest.test.lua`, `sdk-registry.test.lua`, `sdk-routes.test.lua`, `sdk-storage.test.lua`, `sdk-client.test.lua` (helper: `sdk-helper.lua`) |
| App SDK (web host and package) | `customapps-host.test.js`, `customapps.test.lua`, `sdk/test/sdk.test.mjs` (through `cd sdk && npm test`) |
| Handsets, SIMs, banking, mail | `sim-install.test.lua`, `banking-transfer.test.lua`, `economy-contract.test.js`, `system-mail.test.lua`, `pin-contract.test.js`, `native-integrations.test.lua` |
| Calls, camera, maps, sharing | `call-startup.test.lua`, `calls.test.js`, `camera-capture.test.lua`, `camera-preview.test.lua`, `map.test.lua`, `map-blips.test.lua`, `share.test.lua`, `animations.test.lua`, `downed-watch.test.lua`, `client-nui.test.lua` |
| Web UI contracts | `web-contract.test.js`, `features-contract.test.js`, `messaging-contract.test.js`, `media-contract.test.js`, `community-contract.test.js`, `home-reorder.test.js`, `ui-selection.test.js`, `game-recording.test.js`, `game-recording-audio.test.js`, `api-adapters.test.js` |
| Security and code hygiene | `static-security.test.js`, `final-security.test.js`, `test/no_raw_print.lua` (allowlist in `test/print_allowlist.txt`) |

`tests/checklist-social-and-comms.feature` is a Gherkin checklist for the kora_qa panel (the manifest points at `tests/*.feature` with `qa_feature`); it is not run by `test/run.sh`.

Voice, game cameras, inventory, hosted media and two-client flows need a real FiveM server; use [Acceptance tests](../docs/acceptance-tests.md) as the manual plan for those.
