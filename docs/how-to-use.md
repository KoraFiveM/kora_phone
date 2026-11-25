---
title: "How to use"
sidebar_position: 3
---


# How to use

Every server-facing request is one entry in `shared/routes.json` (NUI name, server callback, rate-limit key and optional app gate). `server/callbacks.lua` registers one `Kora.callback` per server name (`kora_phone:server:<name>`) and runs every call through `Routes.invoke`: it consumes the player's shared sliding-window rate bucket (`server/rate_limits.lua`, `Config.Server.RateLimits`), refuses routes whose app gate in `Config.Apps` is off, runs the bound handler inside the handset lock (`KoraPhone.Handsets.locked`, skipped for the `apps:*` routes and async handlers) so a handset swap mid-request cannot be exploited, fails with `Handset session changed` if the character or selected handset moved, and returns `{ ok, data }` or `{ ok = false, error = { code, message, details } }` (`PhoneResult` and `PhoneError` in `shared/constants.lua`). Modules only bind handlers with `KoraPhone.Routes.handle(name, handler)`. After a successful mutating call the server schedules a cloud backup.

## Opening the phone

- Client: `/phone` (configurable, `Config.Client.Command`) or the `M` key (`Config.Client.Keybind`, registered with `Kora.keybind` as `kora_phone_toggle`, so players can rebind it) toggles `KoraPhone.Open`/`Close` (`client/main.lua`). Opening is refused while already open, before the character has loaded, while `KoraPhone.Unavailable()` (dead/downed, if `Config.Client.DisableWhileDead`) or while another resource has set the `koraUiBlocked` state bag (`Config.Client.UiBlockBag`).
- Every open calls the server callback `kora_phone:server:getBootstrap` (through `KoraPhone.ServerCallback`), which returns the handset/device snapshot the NUI renders from. The client never assembles that state itself.
- `exports('OpenPhone')`, `exports('ClosePhone')`, `exports('IsPhoneOpen')` and `exports('PushNotification')` let another client resource drive the same phone.

## Wallet — the ID card

The Wallet app (`server/services/wallet.lua`) is read-only identity, never money: `Wallet.get` returns the caller's own card (name, citizen id, birthdate, gender, nationality, job, and a licence list built from `Config.Server.Wallet.Licences` against the character's `metadata.licences`), and `Wallet.show` finds the closest other player within `Config.Server.Wallet.ShowDistance` (default 3.0 m, measured from the server's own ped positions, never trusted from the client) and pushes that card to them as a phone notification (`kora_phone:client:wallet:shown`).

## Banking — phone-to-phone cash transfer

The Banking app reads balances from `exports.kora_core` and moves money through `exports.kora_banking:ExecuteTransaction`; it keeps no ledger of its own beyond a slim per-device history. The Wallet folder app (`apps/banking`) calls the banking service: `overview` reads the caller's `bank` account (`Config.Server.Banking.Account`) through `KoraPhone.Integrations.Banking.getBalance` and pages `phone_bank_history`. `transfer` is atomic and idempotent: see [Banking and jobs](./banking-jobs.md) for the key format, error mapping and caller whitelist. The app is switched off with `Config.Apps.banking = false`.

- A transfer needs a `clientRequestId` (8 to 64 chars) from the caller. It is the idempotency key, not a display value.
- Recipient resolution is by phone number only (`PhoneValidation.phoneNumber`) via `KoraPhone.Repositories.Phones.findByNumber`. The recipient must be a different character than the sender. The recipient may be offline: kora_banking credits their stored balance.
- Transfers require kora_banking to be started and `kora_phone = true` in its `Config.transactionCallers` (already in kora_banking's default).

## Marketplace (classifieds)

A lightweight listings board over `phone_market_listings`, gated by `Config.Apps.classifieds`. Listings never move money themselves — contacting a seller (`Market.contactSeller`) reuses `KoraPhone.Services.Messaging.send` so the conversation (and its own idempotency/membership checks) is identical to an ordinary message; any actual payment between buyer and seller happens through the Banking transfer or in person, not inside this app.

- `createListing`/`updateListing` validate `title` (1–80), `description` (0–2000), `category` (one of `vehicle`, `property`, `electronics`, `services`, `other`) and `price` (0–1,000,000,000 integer) through `validatedListing` in `server/services/marketplace.lua`.
- `createListing` takes a `clientRequestId` (8–64 chars) too: `Market.create` (`server/repositories/marketplace.lua`) tries the `INSERT` and, when it does not insert (duplicate request), looks the existing row up by `(owner_device_id, client_request_id)` instead and returns it with `replayed = true` — a replay-safe create, not a money settlement (see below for why this is a different kind of idempotency than the bank transfer's).
- `getListings`/`getListing` exclude listings from or to a blocked device (`Repositories.Blocks.isEitherBlocked`) and cap the page size at 50 regardless of what was requested.
- A moderator (`KoraPhone.Services.Moderation.isModerator`) can hide any listing via the same `setStatus(..., 'removed')` path used for an owner marking their own listing sold/removed.

## Money handling

The phone-to-phone bank transfer is the one money path with a durable, atomic design: `BankingService.transfer` in `server/services/banking.lua` calls `exports.kora_banking:ExecuteTransaction` with the sender debit, the recipient credit and the `phone_bank_history` insert as a `statements` entry, so money and history commit together and a retry with the same key returns the original receipt. There is no claim, finish or compensation step. Read the distinction below before assuming every money-touching call here behaves the same way.

- **Marketplace and shop flows, by contrast**: `Market.create`'s insert-then-lookup pattern is idempotent for *listing creation* (no double row on a retried request) but moves no money and has nothing to roll back. The in-world commerce flows in `server/phone_commerce.lua` (buy a handset, pay a `recoveryFee`/`replacementFee`, resell a handset) call `exports.kora_core:removeMoney`/`addMoney` or `exports.kora_inventory:PhoneItemTransaction`/`BuyItem` directly, with ad hoc, per-operation refund logic where the code anticipates a specific failure (for example `recoverCloud` refunds the recovery fee if the SQL transaction that follows it fails) rather than a durable transaction like the bank transfer. There is no `clientRequestId`-style replay protection on those shop calls; a client that fires the same `buy`/`recoverCloud`/`replaceSim`/`resell` request twice is only protected by the rate limit and by what `kora_inventory` and `kora_core` guard against in their own code.

## In-world phone commerce (shops)

Handled entirely by `H.commerce` in `server/phone_commerce.lua`, reached through the shared `handsetAction` callback with `op` set to `buy`, `recoverCloud`, `replaceSim` or `resell`.

- Every operation first calls `H.shopFor` (`server/handsets/location.lua`): the named `payload.shop` must exist in `Config.PhoneServices.shops`, the caller must be within that shop's `distance` **and** routing bucket, and if the shop declares a `job` the caller must be on duty in it at or above the shop's one-based `grade` (`Integrations.Jobs.onDutyAt`). The customer must also be at the counter, and acting for someone else is only allowed at a business counter (one with a `job`).
- A purchase on behalf of someone else (a business employee serving a customer, `payload.target` ≠ the acting player) first requires the target's consent: a `serviceRequest` is created with a 30-second expiry and `kora_phone:client:serviceRequest` is pushed to the target; only after they answer through the `consent` op (and both players' character ids still match what was recorded) does `H.commerce` actually run with `approved = true`.
- `buy` looks up a matching stock slot via `exports.kora_inventory:GetShopItems` and purchases it with `exports.kora_inventory:BuyItem` — the shop's money/weight rules are kora_inventory's own, this resource only locates the slot and target.
- `recoverCloud` charges `s.recoveryFee` through `exports.kora_core:removeMoney` before anything else; if the subsequent `Cloud.rotateRecovery` transaction (revoking the old recovery hash and disconnecting handsets) fails, the fee is refunded with `addMoney` and the service answers "Recovery failed; your fee was refunded".
- `replaceSim` inserts the new SIM as `blocked` before calling `exports.kora_inventory:PhoneItemTransaction` (which charges `s.replacementFee` and swaps the physical items) — metadata commits before activation, so a crash mid-flow fails closed (an inert blocked SIM) rather than leaving a usable duplicate number.
- `resell` requires the handset be factory-reset and SIM-free (`CanResellHandset`) and pays out `floor(price * resalePercent / 100)` through `exports.kora_inventory:PhoneItemTransaction`.

## Custom apps (third-party integration)

There are two routes for a third-party app:

- **SDK apps (recommended).** A separate resource declares a manifest (`kora_phone_app 'app.json'` in its `fxmanifest.lua`, or `exports.kora_phone:RegisterApp`). The phone shows its UI in a sandboxed iframe, enforces the manifest permissions on the server, and gives it namespaced storage and per-app server callbacks. See [App SDK](./apps.md) and [App SDK API](./api/apps.md).
- **Client-registered and alias apps.** `client/customapps.lua` is a display-only app registry plus a compatibility shim: `exports('RegisterApp'/'RemoveApp'/'SendAppMessage')` is the native contract, and the same behaviour is aliased onto the export event names of five other FiveM phone ecosystems (lb-phone, sd-phone, 17mov_Phone, yseries, high-phone) so an addon app written for one of them registers here unmodified. These apps feed the same registry but hold no server permissions, storage or callbacks. Job gating on a registered app (`app.job`) only decides what the Store and home screen show; whatever the app lets a player do once opened is whatever its own resource enforces server-side.
