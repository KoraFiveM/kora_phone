# Legacy qb-phone support on three handsets

Adapted from `qbcore2/qbphone-Stevie-` commit `bf1ef3921845a413cd018b07c1dd909099060743`. Its legacy public interface was pinned to `qbcore-framework/qb-phone` commit `333e8132359b1c50c31c2bc6db8e8a64db6c93f6`.

## Supported integration surface

- `qb-phone:server:sendNewMail`: validated, rate-limited mail to the calling character only. Client-supplied buttons are discarded.
- Server export `sendNewMailToOffline(citizenid, data)`, on both `kora_phone` and `qb-phone` identities: trusted server mail, including optional Accept actions. It retains the upstream void return value. A recipient does not need a handset or SIM for delivery to persist.
- Local server event `qb-phone:server:sendNewEventMail(citizenid, data)`: trusted arbitrary-recipient delivery; network clients are rejected.
- `qb-phone:server:ClearButtonData` and `qb-phone:server:RemoveMail`: current-character ownership and unlocked-handset checks, plus rate limits.
- `qb-phone:client:NewMailNotify`, `qb-phone:RefreshPhone`, `qb-phone:client:BillingEmail`: native notifications, refresh and billing mail.
- `qb-phone:client:RemoveBankMoney`: informational notification only.
- Client/server `qb-phone:*:AddTransaction`: validated transaction notes, retained under the caller's character and displayed in Mail → Activity. These routes never debit or credit money.

For example, from a trusted server resource after phone startup:

```lua
exports['qb-phone']:sendNewMailToOffline(citizenId, {
    sender = 'Job Office',
    subject = 'Delivery offer',
    message = 'Collect the delivery.<br>Accept when you are ready.',
    button = {
        enabled = true,
        buttonEvent = 'my-job:client:acceptDelivery',
        buttonData = { deliveryId = deliveryId }
    }
})
```

The job resource must still validate any resulting gameplay request on its own server. The phone dispatches a local client event; it does not grant job permissions.

## Identity, privacy and UI

Mail is available on Standard, Flip and Fold. Inbox supports named senders, safe plain-text conversion of legacy HTML, read/delete, pagination and one-use Accept buttons. Activity shows integration notes. Mail is a system inbox; it does not enable the deferred Wallet, banking or social apps, or add general email composition.

System mail and notes belong to the current character, not the handset's original registering character, SIM, or cloud account. A stolen/traded handset cannot reveal its former holder's system mail. The same character can read their mailbox from a different unlocked handset. Phone PIN/Face ID protections still gate access. Factory reset clears the physical handset while the character's system mailbox remains available on their replacement phone; it is separate from phone cloud backup.

Only trusted server deliveries can create Accept buttons. The browser submits an owned mail ID, never an event name. The server atomically clears the stored button once; the native client dispatches only the returned stored action. Duplicate, deleted, locked and foreign-character actions are refused. A consumed action is not automatically retried after disconnect or possession loss.

Notifications carry character/handset identity when available. The native client rejects mail notifications addressed to another loaded character. Closed-phone notifications follow the existing handset-isolation rules.

## Schema and existing data

`phone_legacy_mail` and `phone_legacy_transactions` (formerly `013_legacy_qb_phone.sql`) are declared in `server/schema.lua` and created by `Kora.sql.ensureTables` at start; existing databases are left untouched.

This adapts the upstream extension without making the old device-mail foreign keys nullable. Native device-to-device mail tables and routes remain intact and outside this launch interface.

After the normal data preflight succeeds, startup checks for the upstream `phone_mail.recipient_citizenid`, `legacy_sender` and `legacy_button` columns. If all are present, character-owned legacy rows are copied into the new mailbox, preserving sender, subject/body, button, creation/read times and deletion state. A unique `legacy_source_id` mapping prevents duplication or resurrection on later starts. Original rows are not rewritten. Existing `phone_legacy_transactions` rows are read in place. If the upstream mail extension is absent, adoption is skipped.

Back up the database and inventories together before upgrade. Do not run two phone providers together. Rollback restores the consistent backup and the previous resource together; no destructive down-migration is supplied. With automatic migrations disabled, install migration 013 yourself before starting this version; missing legacy tables stop startup clearly.

Live FiveM alias resolution, downstream job effects and database adoption/rollback still require server verification.
