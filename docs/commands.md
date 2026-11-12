---
title: Commands
sidebar_position: 7
---

# Commands, key mappings and interactions

## Commands

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
