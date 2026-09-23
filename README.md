# qbphone

A phone for QBCore servers: calls, texts, mail, a real map, banking, a marketplace and more (over twenty apps), in a clean Nothing-style design with a QBCore theme.

The rule the whole thing is built on: **the server decides, the phone only asks.** Phone numbers, money, jobs, PINs and who can see what are all checked on the server, so a modified client can't send money it doesn't have or read someone else's messages.

## Quick start

1. Download `qbphone-vX.Y.Z.zip` from the [latest release](../../releases/latest) and unzip it into your `resources` folder. It unpacks as `qbphone/`.
2. Add these to `server.cfg`, in this order:

   ```cfg
   ensure oxmysql
   ensure qb-core
   ensure qblib
   ensure qbtheme
   ensure pma-voice
   ensure qbphone
   ```

3. Start the server. The database tables are created on first start, so there's no SQL to import.
4. Give a character the `phone` item and press **M** (or type `/phone`).

## What you need

| Resource | Needed for |
|---|---|
| `qb-core` | Everything: identity, jobs, money |
| `oxmysql` | Everything: all phone data is stored in MySQL |
| `qblib`, `qbtheme` | Everything: shared helpers and the phone's theme |
| `pma-voice` | Calls. Everything else works without it. |
| A media host (Fivemanage) | Camera, photos, Flash clips and videos in chat. Off until you set it up. |

OneSync should be on.

## The apps

| App | What it does |
|---|---|
| Phone, Contacts | Calls with ring timeout and history, video during a call, favourites and contact photos |
| Messages, Pulse | Direct and group chats with photos, clips and shared locations |
| Mail | Inbox and Sent between phone numbers |
| Maps | A road map you can drag and zoom, with your position, heading and waypoint. Tap anywhere to set a waypoint. |
| Wallet | Bank balance and history, your ID card and licences, and showing your ID to the player next to you |
| Market | Buy and sell listings between players, with reports |
| Work | Your QBCore job, duty toggle and job actions |
| Garage, Home | Your vehicles and properties, with waypoints home |
| Camera, Gallery, Flash | Photos and short video clips (needs a media host) |
| Notes, Clock, Sound, Weather, Calculator | The everyday things. Notes and alarms are saved on the server. |
| Moderation | A report queue for staff. Everyone else never sees it. |
| App Store | Players install and remove the optional apps |

Addon apps written for lb-phone, sd-phone, 17mov_Phone, YSeries or High Phone can register without changes, because qbphone answers the same exports those phones use. Apps that lean on another phone's built-in UI pieces (pickers, popups, its own map) won't look right.

Not everything is finished. The social feed works on the server, but its screens are limited and Flash is off until a media host is configured. Bank transfers between players are off by default.

## Settings worth changing

Everything lives in `config/`. The ones most servers touch:

| Setting | File | Default |
|---|---|---|
| Phone item, number format | `config/shared.lua` | `phone`, `555` + 7 digits |
| Keybind and command | `config/client.lua` | `M`, `/phone` |
| Photos and clips: `Media.Provider` | `config/server.lua` | `'disabled'`. Set `'fivemanage'` and see [media storage](docs/media-storage.md). |
| Player-to-player transfers: `Banking.AllowCompensatingTransfers` | `config/server.lua` | `false`. See [banking and jobs](docs/banking-jobs.md). |
| Saved places on the map: `Maps.Locations` | `config/server.lua` | Seven landmarks, from Legion Square to Paleto Bay |
| Garage and housing tables | `config/server.lua` | QBCore `player_vehicles`, qb-houses tables |

Two secrets go in `server.cfg`, never in a Lua file:

```cfg
set qbphone_fivemanage_token "your-fivemanage-media-token"
set qbphone_pin_pepper "a-long-random-string"
```

The pepper makes stored PINs harder to crack if your database ever leaks. Change it later and every existing PIN stops working.

## Where to read more

- [Features in detail](docs/features.md): how notifications, PIN lock, Do Not Disturb, sharing in chat and every other app behave
- [Installation and configuration](docs/installation.md): the full config checklist and clean-install checks
- [Media storage](docs/media-storage.md), [Banking and jobs](docs/banking-jobs.md), [Security](docs/security.md)
- [Acceptance tests](docs/acceptance-tests.md): the two-player checks to run before a big release

## Working on the code

The phone's screens are React and TypeScript in `web/src`, built into `web/dist`, which is committed so the resource runs straight from a clone.

```bash
cd web
npm ci
npm run build
npm test
```

`npm run dev` opens the phone in a browser with sample data, no server needed. The rest of the tests run from the repo root with plain Node and Lua; the list is in [tests/README.md](tests/README.md).

Releases are automatic. Every merge to `main` gets the next version tag, built from the commit messages (`feat:` bumps the minor version, anything else the patch), and a GitHub release with the zip attached. The release stamps its version into the zip's `fxmanifest.lua`, whatever the repo copy says.
