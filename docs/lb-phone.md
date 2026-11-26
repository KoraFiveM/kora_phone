---
title: "lb-phone apps"
sidebar_position: 5.7
---

# lb-phone apps

`kora_phone` answers lb-phone's public surface, so apps and scripts written for lb-phone run without edits. The resource declares `provide 'lb-phone'` in its manifest, so `GetResourceState('lb-phone')` reads as started. Do not run the real lb-phone next to it: two providers of one name race for the same registrations.

The same applies, with less coverage, to `sd-phone`, `17mov_Phone`, `yseries` and `high-phone` (client registration exports only, see [Exports and events](./api/exports-events.md)).

## What works

| lb-phone feature | In kora_phone |
| --- | --- |
| `AddCustomApp`, `RemoveCustomApp`, `SendCustomAppMessage`, client `SendNotification` | Answered. The app shows in the App Store and on the home screen like any other app |
| Custom app page with `ui = "resource/ui/index.html"` | Loaded by the phone and given lb-phone's page globals before its own scripts run (below) |
| `fetchNui(event, data, scriptName)` | Posts to the NUI callback of the app resource, or of `scriptName` |
| Server exports (`exports['lb-phone']:Name`) | All 60 documented server exports are answered; the table below gives the status of each |
| `data-theme` on the page root | Set to `dark` or `light` from the phone theme; kora_theme colours are also available as CSS variables |

## Page globals

lb-phone injects these into an app page. Here the phone does the same by loading the app's HTML itself and inserting `web/public/lb-shim.js` ahead of the app's scripts, with a `base` tag so relative files keep loading from the app resource.

| Global | Status |
| --- | --- |
| `resourceName`, `appName`, `appIdentifier`, `settings` | Supported |
| `fetchNui`, `onNuiEvent`, `onSettingsChange` | Supported. `SendCustomAppMessage` data also arrives as a plain `message` event on the window |
| `formatPhoneNumber`, `setApp`, `createCall` | Supported. `setApp` opens built-in apps by their lb-phone names (Phone, Messages, Contacts, Camera, Photos, Settings, Maps, Mail, Clock, Wallet, App Store) or another installed app by id. `createCall` takes a number, not a company |
| `components.setPopUp`, `setContextMenu`, `setContactSelector`, `setGallery`, `setColorPicker`, `setEmojiPickerVisible`, `setFullscreenImage`, `setHomeIndicatorVisible` | Supported, drawn with the Kora UI kit so they follow the phone theme. The gallery lists the photos of this phone only. The emoji picker is a small fixed set |
| `components.setShareComponent`, `setGifPickerVisible`, `uploadMedia`, `saveToGallery`, `createGameRender`, `GameMap` | Not available. They reject (or throw, for `GameMap`) with a clear message instead of hanging |

## Server exports

Mapped exports do the real thing through the phone's own services. Unsupported exports have no Kora equivalent: they return lb-phone's documented failure value so the calling script never errors, and log one `phone.compat.unsupported` warning per calling resource so you can see what to replace.

| Export | Status | Notes |
| --- | --- | --- |
| `AddCheck` | Mapped | Stores the handler; see the note on checks below. |
| `AddContact` | Mapped | Adds or updates a contact on the phone with that number. |
| `AddTransaction` | Mapped | Adds an informational note to Mail, Activity (it never changes a balance). |
| `AwaitClientCallback` | Mapped | `Kora.callback.trigger` to the player. |
| `BaseCallback` | Mapped | Same, with the phone number added as the second argument. |
| `ContainsBlacklistedWord` | Mapped | Always false (no word filter). |
| `EmergencyNotification` | Mapped | An urgent notification. |
| `EndCall` | Mapped | Hangs up the player call. |
| `FactoryReset` | Mapped | Same as `/resetphone`: setup runs again and the PIN is cleared. |
| `FormatNumber` | Mapped | Returns the number unchanged (numbers have one format here). |
| `GetCall` | Mapped | Basic call data. |
| `GetCellTowers` | Mapped | Always an empty list (no cell towers). |
| `GetConfig` | Mapped | A small subset: framework and number format. |
| `GetEquippedPhoneNumber` | Mapped | Phone number of the held handset (source, or a character id). |
| `GetPin` | Mapped | Always nil: PINs are stored as salted hashes. |
| `GetSettings` | Mapped | The handset settings of an online player. |
| `GetSourceFromNumber` | Mapped | Online player answering that number, or false. |
| `HasAirplaneMode` | Mapped | From the handset settings; nil when offline. |
| `HasPhoneItem` | Mapped | Holds a handset; with a number, that handset has that number. |
| `IsInCall` | Mapped | From the call service. |
| `IsPhoneDead` | Mapped | Always false. |
| `NotifyEveryone` | Mapped | Every online phone, whichever mode is passed. |
| `RegisterCallback` | Mapped | Registers a `Kora.callback` named `lbphone:EVENT`. |
| `RemoveCheck` | Mapped | Removes it. |
| `ResetSecurity` | Mapped | Clears the PIN and Face ID. |
| `SaveAllBatteries` | Mapped | No-op. |
| `SaveBattery` | Mapped | No-op: handsets have no battery. |
| `SendCoords` | Mapped | Sends a location message. |
| `SendMail` | Mapped | System mail to a phone number or character id (not an email address). |
| `SendMessage` | Mapped | Sends a text as that number; attachments become photo tokens. |
| `SendNotification` | Mapped | Shown on the phone of the online target. A number target returns an id; offline targets get nothing because notifications are not stored. |
| `SentMoney` | Mapped | Sends a text saying money was sent. Does not move money. |
| `TriggerClientCallback` | Mapped | The same, with a callback. |
| `AddCrypto` | Unsupported | No Crypto app. Returns the documented failure value and logs one warning per calling resource. |
| `AddCustomCoin` | Unsupported | No Crypto app. Returns the documented failure value and logs one warning per calling resource. |
| `AddUserToDarkChatChannel` | Unsupported | No DarkChat app. Returns the documented failure value and logs one warning per calling resource. |
| `AirShare` | Unsupported | Use Share phone number. Returns the documented failure value and logs one warning per calling resource. |
| `ChangePassword` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `CreateCall` | Unsupported | Calls start from the Phone app only. Returns the documented failure value and logs one warning per calling resource. |
| `CreateDarkChatChannel` | Unsupported | No DarkChat app. Returns the documented failure value and logs one warning per calling resource. |
| `CreateMailAccount` | Unsupported | Mail uses phone numbers, not addresses. Returns the documented failure value and logs one warning per calling resource. |
| `DeleteBirdyAccount` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `DeleteDarkChatChannel` | Unsupported | No DarkChat app. Returns the documented failure value and logs one warning per calling resource. |
| `DeleteInstaPicAccount` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `DeleteMail` | Unsupported | Mail uses phone numbers, not addresses. Returns the documented failure value and logs one warning per calling resource. |
| `DeleteTrendyAccount` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `ForwardCall` | Unsupported | No custom numbers or forwarding. Returns the documented failure value and logs one warning per calling resource. |
| `GetBirdyPost` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `GetCoin` | Unsupported | No Crypto app. Returns the documented failure value and logs one warning per calling resource. |
| `GetEmailAddress` | Unsupported | Mail uses phone numbers, not addresses. Returns the documented failure value and logs one warning per calling resource. |
| `GetOwnedCoin` | Unsupported | No Crypto app. Returns the documented failure value and logs one warning per calling resource. |
| `GetSocialMediaUsername` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `IsVerified` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `PostBirdy` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `PostInstaPic` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |
| `RemoveCrypto` | Unsupported | No Crypto app. Returns the documented failure value and logs one warning per calling resource. |
| `RemoveUserFromDarkChatChannel` | Unsupported | No DarkChat app. Returns the documented failure value and logs one warning per calling resource. |
| `SendDarkChatLocation` | Unsupported | No DarkChat app. Returns the documented failure value and logs one warning per calling resource. |
| `SendDarkChatMessage` | Unsupported | No DarkChat app. Returns the documented failure value and logs one warning per calling resource. |
| `ToggleVerified` | Unsupported | No per-app social accounts. Returns the documented failure value and logs one warning per calling resource. |

### Checks

`AddCheck(event, handler)` stores the handler and `RemoveCheck(id)` removes it. kora_phone does not call the handlers itself yet: no Kora action maps onto lb-phone's check events (`postBirdy`, `buyCrypto` and so on). `KoraPhone.Compat.LbPhone.check(event, source, ...)` runs the stored handlers for code inside this resource that wants to honour them.

## Trust and limits

- An lb-phone app page is loaded as a document of the phone's own origin, so it can reach the same NUI callbacks the phone UI uses. That is the same trust level as the app resource's own client script, which already runs with full game natives, so install lb-phone apps only from sources you would run as scripts. Apps built for the Kora SDK or placed in `apps/` do not get this access through the iframe protocol, but a folder app is trusted code too (see [App SDK developer guide](./apps.md), Trust).
- Apps registered this way have no server-side manifest, so they have no storage, server callbacks or permission checks from this phone. Their own resource provides those.
- `SendNotification` to an offline phone is dropped: notifications are not stored.
- Verify new lb-phone apps in game. The shim is covered by tests with a fake window; the injected document and the NUI cross-origin behaviour can only be proven in a running client.
