---
title: "Commands"
sidebar_position: 4
---


# Commands

Two commands: a client command to open the phone and a server-side moderation and reset tool. The key mappings below are registered through `Kora.keybind`.

## Built-in commands

### `/phone`

Toggles the selected handset open/closed (`KoraPhone.Open`/`Close`). The typed command is a plain client `RegisterCommand` (a `Kora.commands` command would add a server round trip just to open the phone); the key is registered through `Kora.keybind.add` as `kora_phone_toggle`. Refused while dead/downed (if `Config.Client.DisableWhileDead`) or while another resource holds the `koraUiBlocked` state bag true.

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
| Access | `KoraPhone.Services.Moderation.isModerator(caller)` (`kora.phone.moderate` ACE, or the kora_core permission `admin` or `god`) for any in-game caller; the console (`caller == 0`) may always run it and must supply an id. |

**Example**

```text
/phonereset 12
```

**Result**

Replies "Phone reset for player 12" (or "No phone found for player 12"), and the target's open phone is force-closed and reloaded via `kora_phone:client:reset`. The reply is written to the server log when run from the console; for an in-game caller it is sent as a `QBCore:Notify` client event, which only shows if some resource on your server handles that event.

## Command summary


| Command | Side | Who | Behaviour |
| --- | --- | --- | --- |
| `/phone` (`Config.Client.Command`) | Client | Everyone | Toggles the phone. If the phone cannot open because the player is down, a notification explains why (`Config.Client.NoPhoneNoticeWhileDown`) |
| `/phonereset [id]` | Server | Moderators (see [Permissions](./permissions.md)); the console must pass an id | Sets `setupComplete` to false, clears the PIN and Face ID enrolment of the target's current handset, and reloads the phone so the setup screen returns. No id resets the caller's own phone |
| `+kora_phone_camera_look` / `-kora_phone_camera_look` | Client | Everyone | Registered with `Kora.keybind.add` (default left Alt, `Config.Camera.lookKey`) to aim the camera while the Camera app is open. Not registered when `Config.Camera.lookMode` is `off`. The binding is read once when the resource starts, so changing `lookMode` or `lookKey` needs a restart |

## Key mappings

| Mapping | Default | Notes |
| --- | --- | --- |
| Open phone | `M` (`Config.Client.Keybind`) | Registered with `Kora.keybind.add` (`kora_phone_toggle`); players can rebind it in game settings. A key binding saved under an older name is not carried over, so players may need to rebind once |
| Phone camera: aim the camera (`kora_phone_camera_look`) | Left Alt | Rebindable; default from `Config.Camera.lookKey` |

## Interactions

- **Service counters:** every entry in `Config.PhoneServices.shops` is a `kora_lib` circle zone with the option named by its `label` (default "Circuit Mobile"), which opens the phone services sheet.
- **Share phone number:** a `kora_target` option on other players, shown only when `Config.ShareNumber.Enabled` is true, `kora_target` is started, and the player holds a handset. See [Features](./features.md).
- **Handset items:** using a handset item selects it and opens the phone.
