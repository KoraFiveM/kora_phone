# Installation and configuration

## Dependency contract

| Dependency | Required | Purpose | Failure behaviour |
|---|---:|---|---|
| `qb-core` | Yes | Player identity, jobs, money and callbacks | Stop with a clear error |
| `oxmysql` | Yes | Persistent phone data and transactions | Stop with a clear error |
| `pma-voice` | For calls | Private call voice channels | Disable calls with a clear warning |
| `qb-inventory` | Default | Phone-item ownership | Configurable adapter; deny opening if required item is missing |
| Media provider | For camera | Durable image uploads | Camera explains unavailable service; other apps remain usable |

Pin and document the minimum supported versions before release. Do not silently guess incompatible exports.

## Configuration checklist

- Phone item name and whether possession is required while the phone is open
- Number format, uniqueness rules, and character deletion/reassignment policy
- Enabled apps and job integrations
- Voice resource and call-channel adapter
- Upload host allowlist, maximum media size, and server-only credential source
- Text length, attachment, pagination and per-action rate limits
- Marketplace listing lifetime and price bounds
- Banking transfer limits and idempotency window
- Locale, keybind, animation, prop, sounds and notification preferences
- Retention/moderation rules for messages, posts, comments, media and listings

## Clean-install verification

1. Start with an empty database and start the resource. The tables are created automatically on first start: every file in `migrations/` (listed in `fxmanifest.lua`) runs once, in order, and is remembered in a `phone_migrations` table, so a restart runs nothing. If a statement fails, the reason is printed, the resource stops, and the next start resumes at that statement. A database you already imported by hand is adopted: statements that report "already exists" are recorded as done. To manage the SQL yourself, set `Config.Server.AutoMigrate = false` and import the files in filename order, each exactly once.
2. Create two characters and confirm unique persistent numbers.
3. Give both characters the configured phone item.
4. Complete one call, message, image share, transfer, social post and marketplace contact flow.
5. Reconnect both characters and verify persistence and unread state.
6. Restart `stevie-phone` during an active call and confirm voice routing is cleaned up.

## Upgrade verification

- Back up the database before applying migrations.
- A new version's migrations apply automatically on start (and are recorded); with `AutoMigrate = false`, apply each new one exactly once yourself.
- Confirm existing phone numbers, messages, media references and settings remain valid.
- Verify downgrade expectations explicitly; destructive automatic downgrade is unsupported.

## Operational guidance

- Treat upload credentials, webhook URLs and moderation secrets as server-only values.
- Use structured logs for rejected sensitive actions without logging message bodies or secrets.
- Set database indexes for phone numbers, conversation timestamps, feed cursors, handles and marketplace status/search fields.
- Use targeted player events. Never broadcast private messages, balances or call state globally.

