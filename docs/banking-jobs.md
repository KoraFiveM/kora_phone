---
title: Banking and jobs
sidebar_position: 15
---

# Banking and jobs

## Banking model

Balance is read on the server from `kora_core` (`getMoney` for `Config.Server.Banking.Account`). The client never submits a balance or sender identity.

Transfers run on `exports.kora_banking:ExecuteTransaction`, kora_banking's durable transaction API. One call moves the money (sender debit, recipient credit), stores kora_banking's idempotent receipt and writes the phone's own history row (`phone_bank_history`) in the same database transaction. Either everything commits or nothing does, so the phone has no pending, rolled-back or manual-review states and never issues compensating money changes.

- **Whitelist:** kora_banking only accepts callers listed in its `Config.transactionCallers`. `kora_phone = true` must be present there (it is in kora_banking's default); otherwise every transfer is refused (`rejected`) and the phone reports that transfers are not available.
- **Availability:** transfers need `Config.Server.Banking.Enabled` and kora_banking started (`Integrations.Banking.canTransfer`). The same flag decides whether the Wallet offers a Send form. `Config.Apps.banking = false` also refuses `transferBankMoney` on the server.
- **Offline recipients:** the recipient is addressed by citizen id, and kora_banking updates their stored bank balance when they are offline, so the recipient does not need to be online.
- **Not taxed:** durable transactions never go through kora_core's money tax.
- **History:** `getBankHistory` pages `phone_bank_history` (id, operation key, sender and recipient device, amount, time) for the caller's device. Every row is a completed transfer, so `status` is always `completed`. Rows from the old `phone_economy_audit` table are not migrated; history starts empty after the switch and the old table can be dropped by an operator.

Shipped defaults in `config/server.lua`:

```lua
Config.Server.Banking = {
    Enabled = true,
    Account = 'bank',
    MaximumTransfer = 1000000,
    HistoryPageSize = 30
}
```

Every transfer takes the recipient's phone number (`to`), an integer `amount` from 1 to `MaximumTransfer`, and a client-generated request ID of 8 to 64 characters. The idempotency key is `transfer:` plus the sender citizen id and that request ID (at most 128 characters). Repeating an identical request returns the original completion with `replayed = true` and moves nothing. Reusing the ID with a different recipient or amount is a `CONFLICT`.

kora_banking codes map to phone errors:

| kora_banking code | Phone result |
|---|---|
| `insufficient_funds` | `CONFLICT`, "Insufficient funds" |
| `conflict` | `CONFLICT`, request ID used for different details |
| `pending`, `indeterminate`, `unavailable` | `CONFLICT` with `details.retryable = true`; retry with the same request ID, never compensate |
| `rejected` and any other code | `INTERNAL_ERROR` (logged), usually a missing caller whitelist entry |

## Job model

Job name, grade, boss state and duty state are always read on the server with `exports.kora_core:getJob(src)`. Clients may request a boolean duty state or an action ID but cannot submit their job or grade.

Grades use kora_core's native one-based `grade.level`, with no conversion. `minimumGrade` in job actions and `grade` on a business shop counter (`Config.PhoneServices.shops`) are compared against that same level, so `0` and `1` both mean any grade. The grade label shown in the Jobs app is the kora_core grade name.

Duty changes call `exports.kora_multijob:setDuty(src, onDuty)`, which applies the same rules as the in-game duty toggle: jobs in multijob's `Config.disabledDuty` are refused, and otherwise it calls `exports.kora_core:setJobDuty`. The phone no longer duplicates that check. A lock refusal returns a `CONFLICT` error ("This job cannot change duty from the phone"). If kora_multijob is not started, duty changes return a `CONFLICT` error ("Duty management is currently unavailable") and nothing changes. The Jobs app still reads `exports.kora_multijob:getRoster(src)` to add a display-only `dutyLocked` flag to the `job` object returned by `jobs:get` and `setJobDuty`; it is false when kora_multijob is stopped. Business shop gating uses `Integrations.Jobs.onDutyAt` (matching job, on duty, grade at or above the counter's `grade`).

`Config.Server.Jobs` defaults come from the config schema; the integration does not fill them in. `Enabled = false` or `AllowDutyToggle = false` refuses duty changes from the phone.

Actions are an explicit server configuration allowlist:

```lua
Config.Server.Jobs.Actions = {
    police = {
        requestBackup = {
            enabled = true,
            label = 'Request backup',
            minimumGrade = 0,
            requireDuty = true,
            serverEvent = 'my-police:server:requestBackup'
        }
    }
}
```

The configured server event receives one context table containing the verified `source`, `citizenId`, `job`, `grade` (one-based), and action ID. Prefer a `handler` function when the integration is defined in server configuration. The receiving resource must still validate its own domain-specific state.

## Garage

The Garage app lists vehicles with `exports.kora_garages:getOwnedVehicles(citizenid)` (yields, returns an empty list when the character owns none) and the phone runs no SQL for it. kora_garages supplies the display name, garage id and label, and state. The `garage:list` response is unchanged: up to 200 vehicles sorted by plate (the export's cap), each `{ vehicle, plate, garage, state, fuel }` with `state` 0 out, 1 garaged, 2 impounded. `vehicle` is the vehicle's display name, or its model when the name cannot be resolved. The garage name is `None` for a vehicle without one and `House` for an id kora_garages does not list. When `Config.Server.Garage.UseGarageLabels` is off the raw garage id is shown instead. The app is unavailable when `Config.Server.Garage.Enabled` is off or kora_garages is not started.

## Property

There is no Kora housing resource, so the Property app has nothing to call. It reads a housing script's tables through `server/repositories/external.lua` (`Kora.sql`). The table and column names are `Config.Server.Property` (`OwnedTable`, `OwnerColumn`, `HouseColumn`, `LocationsTable`, `NameColumn`, `LabelColumn`, `CoordsColumn`) and default to the qb-houses layout. The expected schema is:

| Table (default) | Needed columns (default) |
|---|---|
| Owned houses (`player_houses`) | character id (`citizenid`), house name (`house`) |
| House locations (`houselocations`) | name (`name`), label (`label`), coordinates (`coords`, JSON; an `enter` object with `x` and `y` is used when present, otherwise `x` and `y` at the top level) |

The app only appears when every configured table and column exists (checked once against the database, cached until restart) and every name is a plain identifier. It stays off otherwise.

## Callback contract

Wallet (`apps/banking`) and Work (`apps/services`) are folder apps. Their callbacks run behind the SDK gate (character loaded, phone held, PIN unlocked, app installed) and call the validated services with the caller's own source; the UI never names an account, sender, job or grade.

| App | Callback | Purpose |
|---|---|---|
| Wallet | `overview` | Authoritative balance, account, recent phone transfers and whether transfers are enabled |
| Wallet | `transfer` | Idempotent bounded transfer request (`to`, `amount`, `clientRequestId`) |
| Wallet | `idCard`, `showId` | The character ID card, and showing it to the person next to you |
| Work | `get` | Current job snapshot and permitted actions |
| Work | `setDuty` | Boolean duty-state request |
| Work | `runAction` | Execute one configured, grade-checked action |

The services live in `server/services/banking.lua`, `wallet.lua` and `jobs.lua`. The `phone_bank_history` table (`server/schema.lua`) is created automatically at start.

## Operational checks

- If a transfer reports `retryable`, the client must retry with the same request ID; never move the money by hand first.
- Test insufficient funds, duplicate clicks, offline recipients, a kora_banking restart mid-transfer, and a missing `Config.transactionCallers` entry on staging.
- Test duty/action requests while job and grade change concurrently.

