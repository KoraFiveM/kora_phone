# Legacy QBCore phone integration

Pinned companion surface: `qbcore-framework/qb-phone` commit
`333e8132359b1c50c31c2bc6db8e8a64db6c93f6`. Enable one phone provider;
`qbphone-stevie` now provides `qb-phone` as well as its existing optional aliases.

- `qb-phone:server:sendNewMail` sends validated, rate-limited mail to the caller's
  citizen ID. Named senders and safely rendered legacy HTML text appear in Mail.
- Server export `sendNewMailToOffline(citizenid, data)` (native and `qb-phone`
  identities) and local server event `qb-phone:server:sendNewEventMail` persist
  mail even before that citizen has opened/provisioned their phone. The event
  intentionally rejects network clients choosing another citizen's mailbox.
- `button = { enabled = true, buttonEvent = 'client:event', buttonData = ... }`
  appears as Accept in Mail. Its action is read from the owned server record,
  atomically cleared once, and dispatched locally. The browser cannot nominate
  an event. `ClearButtonData` and `RemoveMail` use the existing authenticated
  mailbox permissions and rate limit.
- `NewMailNotify`, `BillingEmail` and `qb-phone:RefreshPhone` route into the native
  notifications/mail/bootstrap paths. `RemoveBankMoney` is only a notification.
- `AddTransaction` retains title/message notes in `phone_legacy_transactions`
  under the caller's citizen ID and displays recent Crypto activity in Wallet.
  It never credits/debits money or treats client notes as an accounting ledger.

Migration `012_legacy_qb_phone.sql` makes only the two mail device references
nullable, retaining their foreign keys and existing rows, and adds citizen/name/
button fields plus the notes table. Device-to-device inbox/sent pagination and
ownership continue to use their original paths. The migration runner applies
steps once; validate on an isolated database before restarting this resource.

Validation: `lua tests/legacy-compat.test.lua`, all existing phone tests, and the
web production build. Game-client notification display, button event effects and
remote resource state/export resolution require an isolated FiveM client check.
This does not claim parity for the old phone's internal NUI or every application
callback; broader phone contracts remain in the repository compatibility matrix.
