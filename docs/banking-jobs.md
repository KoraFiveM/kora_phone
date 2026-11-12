---
title: Banking and jobs
sidebar_position: 15
---

# Banking and jobs

## Banking model

Balance is read on the server from `kora_core` (`getMoney` for `Config.Server.Banking.Account`). The client never submits a balance or sender identity. Phone history comes from `phone_economy_audit`, which records phone-initiated transfers and their final state.

The `kora_core` `removeMoney` and `addMoney` operations cannot join the SQL audit transaction. For that reason transfers are safely disabled by default. Balance and history remain available. An operator may explicitly enable the compensating path:

```lua
Config.Server.Banking.AllowCompensatingTransfers = true
```

The compensating path requires both players online, debits the sender, credits the recipient, and refunds the sender if the credit fails. A failed refund is marked `manual_review` and logged. It cannot protect against a process crash between framework money calls; servers requiring true atomic transfers should replace the integration with a banking resource that provides one atomic server-side transfer operation.

The shipped defaults in `config/server.lua` (plus `HistoryPageSize`, default 30, read by the banking integration):

```lua
Config.Server.Banking = {
    Enabled = true,
    Account = 'bank',
    MaximumTransfer = 1000000,
    HistoryPageSize = 30,
    AllowCompensatingTransfers = false
}
```

Every transfer requires a client-generated request ID of 8–64 characters. The database uniqueness constraint makes retries idempotent. Reusing a completed request returns the original completion; pending, rejected, rolled-back and review states cannot move money again.

## Job model

Job name, grade, boss state and duty state are always read from the current player data on the server (`kora_core`). Clients may request a boolean duty state or an action ID but cannot submit their job or grade.

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

The configured server event receives one context table containing the verified `source`, `citizenId`, `job`, `grade`, and action ID. Prefer a `handler` function when the integration is defined in server configuration. The receiving resource must still validate its own domain-specific state.

## Callback contract

| Callback suffix | Purpose |
|---|---|
| `getBankBalance` | Current authoritative account balance |
| `getBankHistory` | Cursor-paginated phone transfer audit |
| `transferBankMoney` | Idempotent bounded transfer request |
| `getJob` | Current job snapshot and permitted actions |
| `setJobDuty` | Boolean duty-state request |
| `runJobAction` | Execute one configured, grade-checked action |

`server/modules/economy_callbacks.lua` registers these callbacks. The `phone_economy_audit` table (`server/schema.lua`) is created automatically at start.

## Operational checks

- Alert administrators to any `manual_review` record immediately.
- Review old `pending` records after unexpected resource/server termination; never replay them automatically.
- Test insufficient funds, duplicate clicks, offline recipients, failed credits and failed compensation with a staging banking adapter.
- Test duty/action requests while job and grade change concurrently.

