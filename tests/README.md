# Test scaffolding

`bash tests/run.sh` runs everything below plus a `luac -p` syntax check of the Lua sources (web-dependent checks are skipped until `npm ci --prefix web`; CI runs it before every release). Run independent checks from the resource root:

```bash
node tests/static-security.test.js
node tests/web-contract.test.js
node tests/features-contract.test.js
lua tests/validation.test.lua
lua tests/storage.test.lua
lua tests/migrations.test.lua
lua tests/customapps.test.lua
node tests/migrations-manifest.test.js
```

The JS tests use only Node built-ins. They skip cleanly until web source or an `fxmanifest.lua` exists, then become enforcing checks automatically.

The Lua suite loads `config/shared.lua` and `shared/validation.lua` directly, proving that the production validation layer remains usable without FiveM globals. FiveM/QBCore integration tests still require a real server and two clients; use `docs/acceptance-tests.md` as that manual/automation plan.
