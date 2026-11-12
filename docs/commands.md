---
title: "Commands"
sidebar_position: 4
---


# Commands

Three commands: one client-side to open the phone, one server-side moderation/reset tool, and one client-side developer tool for previewing notifications.

## Built-in commands

### `/phone`

Toggles the selected handset open/closed (`KoraPhone.Open`/`Close`, registered with `RegisterCommand`/`RegisterKeyMapping`). Refused while dead/downed (if `Config.Client.DisableWhileDead`) or while another resource holds the `koraUiBlocked` state bag true.

| Field | Details |
| --- | --- |
| Context | In-game · client command (`Config.Client.Command`, keybind `Config.Client.Keybind` default `M`) |
| Arguments | No arguments. |
| Access | Any player; the phone item requirement (`Config.RequirePhoneItem`) and down-state checks are enforced when it runs, not by who may type the command. |

**Example**

```text
/phone
```

**Result**

Opens the phone and sends `phone:open` to the NUI with the current state snapshot, or shows a "You cannot use your phone right now" / "You don't have a phone" notification if unavailable.

### `/phonereset [id]`

Wipes the target's phone settings and PIN so the setup screen shows again on next open (`setupComplete = false`, PIN cleared, enrolled Face ID citizen id cleared). Omitting `id` resets the caller's own phone.

| Field | Details |
| --- | --- |
| Context | In-game or console · server command (`RegisterCommand('phonereset', ...)`, `server/main.lua`) |
| Arguments | id? — server id of the target player. Required from the server console (console has no "own phone" to default to). |
| Access | `KoraPhone.Services.Moderation.isModerator(caller)` (kora.phone.moderate ace or QBCore admin/god) for any in-game caller; the console (`caller == 0`) may always run it and must supply an id. |

**Example**

```text
/phonereset 12
```

**Result**

Replies "Phone reset for player 12" (or "No phone found for player 12"), and the target's open phone is force-closed and reloaded via `kora_phone:client:reset`.

### `/testphonenotify [app|all|sms]`

Developer tool: pushes a sample notification into your own phone so you can see how one looks. Named `testphonenotify` rather than `testnotify` because kora_lib-playground registers a plain `/testnotify`.

| Field | Details |
| --- | --- |
| Context | In-game · client command |
| Arguments | app? — one of `messages`, `phone`, `banking`, `mail`, `social`, `classifieds`, `gps`, `weather`, `flash`, `clock` or `system`; `all` sends every sample about 0.8 s apart; `sms` sends a sample text message. With no argument it sends the first sample and prints the usage line. |
| Access | Any player (the command is not ACE-restricted). |

**Example**

```text
/testphonenotify banking
```

**Result**

A sample notification (for example "Wallet: You received $2,500 from Maya.") appears on your phone. An unknown app name prints `unknown app` to the console.

## Developer-only command

`/testphonenotify` (client, `client/notifications.lua`) is the only sample-notification command; see its section above. It runs entirely client-side and is not gated by any permission, so treat it as a dev tool, not a player-facing feature. There is no separate `/testnotify` command in this resource (the name is used by kora_lib-playground, which is why this one is called `testphonenotify`).

## Command summary


| Command | Side | Who | Behaviour |
| --- | --- | --- | --- |
| `/phone` (`Config.Client.Command`) | Client | Everyone | Toggles the phone. If the phone cannot open because the player is down, a notification explains why (`Config.Client.NoPhoneNoticeWhileDown`) |
| `/phonereset [id]` | Server | Moderators (see [Permissions](./permissions.md)); the console must pass an id | Sets `setupComplete` to false, clears the PIN and Face ID enrolment of the target's current handset, and reloads the phone so the setup screen returns. No id resets the caller's own phone |
| `/testphonenotify [all, sms, or an app id]` | Client | Everyone | Developer command that pushes sample notifications into the caller's own phone UI. It does not touch the server |
| `+kora_phone_camera_look` / `-kora_phone_camera_look` | Client | Everyone | Key-mapped command (default left Alt, `Config.Camera.lookKey`) that aims the camera while the Camera app is open. Not registered when `Config.Camera.lookMode` is `off` |

## Key mappings

| Mapping | Default | Notes |
| --- | --- | --- |
| Open phone | `M` (`Config.Client.Keybind`) | Registered with `RegisterKeyMapping`; players can rebind it in game settings |
| Phone camera: aim the camera | Left Alt | Rebindable; default from `Config.Camera.lookKey` |

## Interactions

- **Service counters:** every entry in `Config.PhoneServices.shops` is a `kora_lib` circle zone with the option named by its `label` (default "Circuit Mobile"), which opens the phone services sheet.
- **Share phone number:** a `kora_target` option on other players, shown only when `Config.ShareNumber.Enabled` is true, `kora_target` is started, and the player holds a handset. See [Features](./features.md).
- **Handset items:** using a handset item selects it and opens the phone.
