---
title: UI
sidebar_position: 8
---

# UI

The NUI is a React, TypeScript and Vite app in `web/src`, built into `web/dist` (the manifest's `ui_page` is `web/dist/index.html`). The built assets are committed. The UI calls the NUI callbacks listed in [Events and callbacks](./events.md); outside FiveM `web/src/mock.ts` supplies seeded demo data.

## Handset styles

| Handset | Model | Experience |
| --- | --- | --- |
| Orchard One | `standard` | Nothing-inspired Android styling, monochrome icons, dot-matrix clock, light and dark |
| Circuit Flip | `flip` | Tall inner display and a closed cover screen (clock, notifications, voice calls, music controls, camera preview) |
| Atlas Fold | `fold` | Complete outer phone that unfolds into larger layouts, with conversations beside the open chat |

Settings also offers a `classic` style, themes (`light`, `dark`, `ocean`, `forest`, `amethyst`, `ember`, `kora_core`), wallpapers, icon styles and flip-case art.

## Apps

App ids in `web/src/App.tsx`: Phone, Contacts, Messages (Pulse chat), Camera, Gallery, Maps (`gps`), Mail, Notes, Weather, Calculator, Clock, Sound (`music`), Settings, plus the optional Wallet (`banking`), Pulse (`social`), Market (`classifieds`), Services, Home (`property`), Garage (`vehicles`), Flash and Moderation. Availability depends on `Config.Apps`, `Config.LaunchApps`, and server checks reported at bootstrap (media provider, housing tables, garage table, transfers). Notes, alarms and Sound stations are stored on the server ([Database](./database.md)). The list of installed optional apps is kept in the NUI's `localStorage`.

Custom apps registered through [Exports](./api/exports-events.md) appear in the App Store (unless `Config.AppStore` is `false`) and open in an embedded frame.

## Maps

Maps shows a road map image (`web/public/map.jpg`, fitted by `MAP_BOUNDS` in `web/src/Utilities.tsx`), the saved places from `Config.Server.Maps.Locations`, and visible game blips mirrored once per second while the app is open. The game minimap is repositioned behind the app and restored when it closes.

## Developing the UI

```sh
npm ci --prefix web
npm run dev --prefix web
npm run build --prefix web
```

Rebuild before deploying UI changes. `npm test --prefix web` runs the contract tests under `tests/`. Voice, game cameras, inventory and hosted media need a FiveM server; the standalone preview uses demonstration data. The `docs/images` folder holds the preview screenshots used by the README.
