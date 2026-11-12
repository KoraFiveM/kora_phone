# kora_phone agent guide

`kora_phone` is a server-authoritative FiveM phone for the Kora `[v2]` stack: physical handsets (Standard, Flip, Fold) as inventory items, removable SIMs, PIN and cloud backup, calls over pma-voice, messages, mail, camera and gallery, Pulse/Flash social, Market and a qb-phone compatibility layer. Layout: `fxmanifest.lua`, `config/` (shared, client, server, handsets), `shared/` (constants, validation, contracts), `client/` (NUI bridge, calls, camera, map, share, custom apps), `server/` (`schema.lua`, `repositories/`, `services/`, `integrations/`, `modules/`, `handsets.lua`, `compat/qb-phone.lua`), `integration/kora_inventory/` (companion inventory gateway), `web/` (React NUI source and built `web/dist`), `tests/` (Lua and Node checks plus kora_qa feature files), `local-media/` and `docs/`.

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events, items, permissions and database usage.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
