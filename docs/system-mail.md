---
title: System mail
sidebar_position: 17
---

# System mail

System mail lets trusted server resources leave a message or an activity note for a character. It is shown in the Mail app (Inbox and Activity). Players cannot create it.

## Server exports

```lua
local ok, mailId = exports.kora_phone:SendSystemMail(citizenId, {
    sender = 'Job Office',
    subject = 'Delivery offer',
    message = 'Collect the delivery.<br>Accept when you are ready.',
    button = { event = 'my-job:client:acceptDelivery', data = { deliveryId = deliveryId } },
})

exports.kora_phone:AddSystemActivity(citizenId, 'Credit', 'Received 5 BTC')
```

| Export | Behaviour |
| --- | --- |
| `SendSystemMail(citizenId, mail)` | Stores the mail for the character, online or offline, and returns `true, id` (or `false`). Online players get a `kora_phone:client:mail:new` event. `sender` max 100, `subject` max 120, `message` max 16000 characters; HTML is stripped to plain text |
| `AddSystemActivity(citizenId, title, message)` | Stores an informational note (`title` max 100, `message` max 1000). It never changes a balance |

## Accept button

`button.event` is nominated only by the calling server resource, never by a client. It must look like `resource:client:name`, be at most 200 characters, and must not start with `kora_phone:`, `kora_core:`, `kora_lib:`, `kora_sql:`, `kora_inventory:` or `kora_voice:`. `button.data` is capped at 16000 characters of JSON.

When the player presses Accept, the Mail app's `accept` callback (the same one-use claim, `mail:system:accept` inside `server/mail/system.lua`) claims the button once in the database and the server itself fires `TriggerClientEvent(event, source, data)`. The browser sends only the mail id. Duplicate, deleted, locked and other-character requests are refused, and a consumed button is not retried. The receiving resource must still validate any resulting request on its own server.

## Callbacks

The Mail folder app (`apps/mail`) serves `inbox`, `activity`, `read`, `delete` and `accept`, each calling the matching handler in `KoraPhone.SystemMail.routes` (`mail:system:list`, `activity`, `read`, `delete`, `accept`). They are SDK app callbacks, so they are no longer entries in `shared/routes.json`. All need an unlocked handset held by the current character. Mail belongs to the character, not the handset, so a traded handset reveals nothing and a replacement handset shows the same mailbox.

## Tables

`phone_system_mail` and `phone_system_activity` are declared in `server/schema.lua` and created by `Kora.sql.ensureTables`; there is no migration.

## Custom-app alias exports

This is a pointer, not part of system mail. `client/customapps.lua` answers the export names of other phone resources (lb-phone, sd-phone, 17mov_Phone, yseries, high-phone) so a custom app written for one can register unmodified. The functions and the `compat.js` bridge are listed in [Exports](./api/exports-events.md). There is no qb-phone compatibility.
