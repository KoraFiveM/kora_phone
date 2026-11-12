---
title: "How to use"
sidebar_position: 3
---


# How to use

Every server-facing request goes through one dispatcher (`KoraPhone.registerCallback`, `server/callbacks.lua`) wrapping `Kora.callback.register('kora_phone:server:<name>', ...)`. It applies a per-action token-bucket rate limit, blocks whole app categories that `Config.Apps` has turned off, re-validates the caller's character and (for most actions) runs the handler inside the handset lock (`KoraPhone.Handsets.locked`) so a handset swap mid-request cannot be exploited, and forces a result shape of `{ ok, data }` or `{ ok = false, error = { code, message, details } }` (`PhoneResult`/`PhoneError` in `shared/constants.lua`).

## Opening the phone

- Client: `/phone` (configurable, `Config.Client.Command`) or the `M` keybind toggles `KoraPhone.Open`/`Close` (`client/main.lua`). Opening is refused while already open, before the character has loaded, while `KoraPhone.Unavailable()` (dead/downed, if `Config.Client.DisableWhileDead`) or while another resource has set the `koraUiBlocked` state bag (`Config.Client.UiBlockBag`).
- Every open sends `KoraPhone.ServerCallback('kora_phone:server:getBootstrap', ...)`, which returns the handset/device snapshot the NUI renders from. The client never assembles that state itself.
- `exports('OpenPhone')`, `exports('ClosePhone')`, `exports('IsPhoneOpen')` and `exports('PushNotification')` let another client resource drive the same phone.

## Wallet — the ID card

The Wallet app (`server/services/wallet.lua`) is read-only identity, never money: `Wallet.get` returns the caller's own card (name, citizen id, birthdate, gender, nationality, job, and a licence list built from `Config.Server.Wallet.Licences` against the character's `metadata.licences`), and `Wallet.show` finds the closest other player within `Config.Server.Wallet.ShowDistance` (default 3.0 m, measured from the server's own ped positions, never trusted from the client) and pushes that card to them as a phone notification (`kora_phone:client:wallet:shown`).

## Banking — phone-to-phone cash transfer

The Banking app wraps `exports.kora_core` money, not a separate ledger. `getBankBalance` reads the caller's `bank` account (`Config.Server.Banking.Account`) through `KoraPhone.Integrations.Banking.getBalance`. `getBankHistory` pages the shared `phone_economy_audit` table. `transferBankMoney` is the one path that actually moves money between two different players' phones — see "Money handling: settle and rollback" below for exactly how it is kept idempotent and reversible.

- Transfers are disabled unless `Config.Server.Banking.AllowCompensatingTransfers = true` (default `false`): `Banking.canTransfer()` gates the whole app, because QBCore's in-memory money API cannot join the same SQL transaction as the audit row, so the resource refuses to pretend otherwise unless the operator explicitly opts into a compensating-transfer design.
- A transfer needs a `clientRequestId` (8–64 chars) from the caller — this is the idempotency key (see below), not a display value.
- Recipient resolution is by phone number only (`PhoneValidation.phoneNumber`, prefix + subscriber digits from `Config.PhoneNumber`) via `KoraPhone.Repositories.Phones.findByNumber`; the recipient must be a different phone than the sender's own, and must be online (the transfer is rejected with `RECIPIENT_OFFLINE` otherwise — there is no offline-credit path here, unlike kora_banking's own transfers).

## Marketplace (classifieds)

A lightweight listings board over `phone_market_listings`, gated by `Config.Apps.classifieds`. Listings never move money themselves — contacting a seller (`Market.contactSeller`) reuses `KoraPhone.Services.Messaging.send` so the conversation (and its own idempotency/membership checks) is identical to an ordinary message; any actual payment between buyer and seller happens through the Banking transfer or in person, not inside this app.

- `createListing`/`updateListing` validate `title` (1–80), `description` (0–2000), `category` (one of `vehicle`, `property`, `electronics`, `services`, `other`) and `price` (0–1,000,000,000 integer) through `validatedListing` in `server/services/marketplace.lua`.
- `createListing` takes a `clientRequestId` (8–64 chars) too: `Market.create` tries the `INSERT` and, on a unique-constraint failure (duplicate request), looks the existing row up by `(owner_device_id, client_request_id)` instead and returns it with `replayed = true` — a replay-safe create, not a money settlement (see below for why this is a different kind of idempotency than the bank transfer's).
- `getListings`/`getListing` exclude listings from or to a blocked device (`Repositories.Blocks.isEitherBlocked`) and cap the page size at 50 regardless of what was requested.
- A moderator (`KoraPhone.Services.Moderation.isModerator`) can hide any listing via the same `setStatus(..., 'removed')` path used for an owner marking their own listing sold/removed.

## Money handling: settle and rollback (verified mechanism)

This resource keeps one genuinely idempotent, settle/rollback money-moving path: the phone-to-phone bank transfer. It is built on `server/repositories/transactions.lua` and the `phone_economy_audit` table, driven from `BankingService.transfer` in `server/services/banking.lua`. The marketplace and in-world shop flows use lighter, narrower patterns — read the distinction below before assuming every money-touching call here behaves the same way.

- **Claim (idempotency key)**: `Transactions.claim(senderDeviceId, recipientDeviceId, senderCitizenId, recipientDeviceId, amount, clientRequestId)` runs `INSERT IGNORE INTO phone_economy_audit (..., status, client_request_id) VALUES (..., 'pending', ?)`. If the row already exists for this `(sender_citizenid, client_request_id)` (a presumed unique constraint on that pair — not shown in a schema file read here, marked unclear below), the `INSERT IGNORE` affects 0 rows; `claim` then looks the existing row up with `findIdempotent` and returns `claimed = false` plus that row. The service layer checks the stored `amount`/`recipientDeviceId` still match the new request: a mismatch is a hard `CONFLICT` (reused id, different transfer); a match on a transaction already `completed` returns that same result with `replayed = true` — a genuine retry of an identical request is answered without moving money twice.
- **Settle**: once claimed, the service re-validates the recipient is online and the sender's live balance covers the amount, then calls `Banking.debit(sender, amount, reason)` (`exports.kora_core:removeMoney`) followed by `Banking.credit(recipient, amount, reason)` (`exports.kora_core:addMoney`). Every state transition is written with `Transactions.finish(id, status, failureCode)`, which only updates the row `WHERE id = ? AND status = 'pending'` — a transaction can only be finished once from the pending state.
- **Rollback**: if the debit itself fails, the row is finished as `rejected`/`DEBIT_FAILED` and nothing further happens (no money left the sender). If the debit succeeded but the credit fails, the code calls `Banking.credit(sender, amount, reason .. ' rollback')` to give the sender their money back — this is a **compensating transfer**, not a database rollback, since the debit already committed to kora_core's own money store. If that compensating credit itself succeeds, the row is finished `rolled_back`/`CREDIT_FAILED`; if the compensating credit ALSO fails, it is finished `manual_review`/`ROLLBACK_FAILED` and the server prints `[kora_phone] transfer <id> failed credit; status=<status>` — this is the one case that is not automatically resolved and needs operator attention.
- What this means precisely: the **idempotency** is real and verified (same `clientRequestId` + sender never double-charges, by the unique claim row and the pending-only `finish` guard). The **rollback** is real and verified for the one failure mode it covers (crediting the recipient after debiting the sender), via a same-amount compensating credit — it is not a two-phase-commit or a database transaction spanning both `phone_economy_audit` and kora_core's money tables, since those are different stores. A double rollback failure is logged and left as `manual_review`, not silently retried.
- **Unique index (verified)**: `phone_economy_audit` carries the unique index `uq_phone_economy_idempotency` on `(sender_citizenid, client_request_id)` (`server/schema.lua:185`), which the `INSERT IGNORE` claim depends on.
- **Marketplace and shop flows, by contrast**: `Market.create`'s pcall-insert/fallback-lookup pattern is idempotent for *listing creation* (no double row on a retried request) but moves no money and has nothing to roll back. The in-world commerce flows in `server/phone_commerce.lua` (buy a handset, pay a `recoveryFee`/`replacementFee`, resell a handset) call `exports.kora_core:removeMoney`/`addMoney` or `exports.kora_inventory:PhoneItemTransaction`/`BuyItem` directly, with ad hoc, per-operation refund logic where the code anticipates a specific failure (for example `recoverCloud` refunds the recovery fee if the SQL transaction that follows it fails) rather than the shared claim/finish ledger the bank transfer uses. There is no `clientRequestId`-style replay protection on those shop calls; a client that fires the same `buy`/`recoverCloud`/`replaceSim`/`resell` request twice is only protected by whatever `exports.kora_inventory` and `exports.kora_core` themselves guard against (not inspected here).

## In-world phone commerce (shops)

Handled entirely by `H.commerce` in `server/phone_commerce.lua`, reached through the shared `handsetAction` callback with `op` set to `buy`, `recoverCloud`, `replaceSim` or `resell`.

- Every operation first calls `shopAccess(src, payload)`: the named `payload.shop` must exist in `Config.PhoneServices.shops`, the caller must be within that shop's `distance` **and** routing bucket, and if the shop declares a `job` the caller must work that job on duty at the required grade.
- A purchase on behalf of someone else (a business employee serving a customer, `payload.target` ≠ the acting player) first requires the target's consent: a `serviceRequest` is created with a 30-second expiry and `kora_phone:client:serviceRequest` is pushed to the target; only after they answer through the `consent` op (and both players' character ids still match what was recorded) does `H.commerce` actually run with `approved = true`.
- `buy` looks up a matching stock slot via `exports.kora_inventory:shopGet` and purchases it with `exports.kora_inventory:BuyItem` — the shop's money/weight rules are kora_inventory's own, this resource only locates the slot and target.
- `recoverCloud` charges `s.recoveryFee` through `exports.kora_core:removeMoney` before anything else; if the subsequent `MySQL.transaction.await` (revoking the old recovery hash and disconnecting handsets) fails, the fee is refunded with `addMoney` and the service answers "Recovery failed; your fee was refunded".
- `replaceSim` inserts the new SIM as `blocked` before calling `exports.kora_inventory:PhoneItemTransaction` (which charges `s.replacementFee` and swaps the physical items) — metadata commits before activation, so a crash mid-flow fails closed (an inert blocked SIM) rather than leaving a usable duplicate number.
- `resell` requires the handset be factory-reset and SIM-free (`CanResellHandset`) and pays out `floor(price * resalePercent / 100)` through `exports.kora_inventory:PhoneItemTransaction`.

## Custom apps (third-party integration)

`client/customapps.lua` is a display-only app registry plus a compatibility shim: `exports('RegisterApp'/'RemoveApp'/'SendAppMessage')` is the native contract, and the same behaviour is aliased onto the export event names of five other FiveM phone ecosystems (lb-phone, sd-phone, 17mov_Phone, yseries, high-phone) so an addon app written for one of them registers here unmodified. Job gating on a registered app (`app.job`) only decides what the Store/home screen SHOWS — whatever the app actually lets a player do once opened is still whatever its own resource enforces server-side.

## Cosmetic note: notification card title overflow

A code-review pass flagged that the notification shade's title style was missing the same overflow guard as its body text in one theme layer. Confirmed in source: `web/src/polish.css` sets `.notification-card strong { font-size: 13px; }` (no wrapping rule) immediately above `.notification-card small { font-size: 12px; line-height: 1.5; overflow-wrap: anywhere; }`, while the base `web/src/style.css` already carries `overflow-wrap: anywhere` on its own `.notification-card strong` rule. So the title rule in the `polish.css` theme overlay is the one missing the guard the body text (and the base stylesheet's title rule) already has — a long notification title can overflow its card in that theme. Low-impact and cosmetic; not pursued further here.
