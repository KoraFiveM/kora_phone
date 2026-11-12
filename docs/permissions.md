---
title: Permissions
sidebar_position: 11
---

# Permissions

Moderator status is decided on the server in `server/services/moderation.lua`. A player is a moderator when either holds:

- the ACE `kora.phone.moderate` (`IsPlayerAceAllowed`), or
- the `kora_core` permission `admin` or `god` (`exports.kora_core:hasPermission`).

```cfg
add_ace group.admin kora.phone.moderate allow
```

Moderator status is used for:

- `/phonereset` ([Commands](./commands.md)).
- The `moderator` and `admin` flags in the bootstrap payload, which the UI uses to show the Moderation app and extra delete buttons in Pulse. The Moderation app also requires `Config.Apps.moderation = true`; it is `false` by default, and while it is `false` the server refuses `moderation:*` callbacks.
- The moderation queue and resolve callbacks ([Community security](./community-security.md)).

Opening a staff screen grants no authority; every callback re-checks permission on the server.

Other access rules (not ACE based):

- Job actions need the configured job, minimum grade and duty state ([Banking and jobs](./banking-jobs.md)).
- Business service counters can require `job` and `grade` from `Config.PhoneServices.shops`; private Wi-Fi can require `ownerJob`.
- Gateway calls to `kora_inventory` `PhoneItemTransaction` are accepted only from the resource named `kora_phone` (or the legacy `kora_phone-stevie`).
