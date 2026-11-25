---
title: UI
sidebar_position: 8
---

# UI

The NUI is a React, TypeScript and Vite app in `web/src`, built into `web/dist` (the manifest's `ui_page` is `web/dist/index.html`). The built assets are committed. The UI calls the NUI callbacks listed in [Events and callbacks](./events.md); outside FiveM `web/src/mock.ts` supplies seeded demo data.

## Handset styles

| Handset | Model | Experience |
| --- | --- | --- |
| Orchard One | `standard` | Kora OS styling, monochrome icons, dot-matrix clock, light and dark |
| Circuit Flip | `flip` | Tall inner display and a closed cover screen (clock, notifications, voice calls, music controls, camera preview) |
| Atlas Fold | `fold` | Complete outer phone that unfolds into larger layouts, with conversations beside the open chat |

Settings also offers a `classic` style, an appearance (dark or light), wallpapers, icon styles and flip-case art. See Theme below for how colour works.

## Theme

kora_theme owns every colour, font and shape in the phone. The phone loads kora_theme's `theme.css` and `theme.js` (the build points `index.html` at `https://cfx-nui-kora_theme`), and the stylesheets only use its CSS variables: HSL triplets such as `--background`, `--foreground`, `--primary`, `--border`, `--surface-raised` (used as `hsl(var(--primary))`), `--font-sans`, `--font-heading` and `--font-mono`. There are no hard-coded hex colours, no `@fontsource` fonts and no private palette in the web source. Handsets (Orchard One, Circuit Flip, Atlas Fold) only define structure: shell, layout, icon style, names. The accent colour is the server primary, or the player's own colour from `/theme`.

- **Appearance.** kora_theme ships a single dark palette and no light mode, so the phone derives one. `web/src/scheme.css` sets `--ink` and `--paper` on the phone screen: dark uses `--foreground` and `--background` as they are, light swaps the two. Every neutral shade (`--shade-5` to `--shade-95`), card, input and border is a `color-mix()` of those roles, so a server or player colour restyles both appearances. Light darkens the accent a little so it stays readable on a light surface.
- **Settings.** The picker offers Dark and Light. It stores `dark` or `light` in `settings.theme`. The server still accepts the retired ids (`kora_core`, `ocean`, `forest`, `amethyst`, `ember`); the phone shows them as dark. `kora_core` stays the default for new phones.
- **Wallpapers.** A wallpaper is a scene plus the text colour that reads on it. Orbit and Slate are light scenes, Midnight and Ember dark scenes, and the default, Plain and photo wallpapers follow the appearance. The default scene is tinted with the primary colour from a different corner per handset.
- **Fixed on purpose.** The hardware frame, hinge and cover art keep their metal and dark look in both appearances. The Flip cover scenes in `web/src/core/CoverArt.tsx` and the demo data in `mock.ts` are artwork and sample content, not UI colour.

Stylesheets: `scheme.css` (appearance, shade ramp, wallpapers), `style.css` (base and app screens), `surfaces.css` (shared surfaces of built-in apps), `social.css`, `settings-hub.css`, `setup.css`, `handset-panel.css`, `handset-shells.css` (Flip and Fold, including the hinge and cover), `handset-standard.css` (Orchard One) and `CustomApps.css`.

The web build imports kora_theme's Vite plugin straight from the sibling resource (`[standalone]/kora_theme/vite-plugin.mjs`, see `web/vite.config.ts`), so `npm run dev` serves the live theme at `/@kora_theme` and there is no vendored copy to keep in sync. A build needs kora_theme next to this resource.

## Apps

App ids (`AppId` in `web/src/types.ts`, screens registered in `web/src/core/appRegistry.ts`): Phone, Contacts, Messages (Pulse chat), Camera, Gallery, Maps (`gps`), Clock, Sound (`music`), Settings, plus the optional Pulse (`social`), Market (`classifieds`), and Flash. Notes, Weather, Calculator, Wallet (`banking`), Mail, Moderation, Work (`services`), Home (`property`) and Garage (`vehicles`) are folder apps (`apps/<id>/`, see the [App SDK developer guide](./apps.md)) and appear on the home screen as `app:<id>` entries. Availability depends on `Config.Apps`, `Config.LaunchApps`, and server checks reported at bootstrap (media provider, housing tables, garage table, transfers). Alarms and Sound stations are stored on the server ([Database](./database.md)). The list of installed optional apps (`installedApps`) and the home order are saved with the phone's settings on the server and validated against `Config.LaunchApps`; new phones start with Maps, Clock and Sound installed, plus every folder app whose `app.lua` sets `defaultInstalled = true` (Notes, Weather, Calculator and Mail). The NUI's `localStorage` only holds the last screen, notification history, Do Not Disturb times and alarm copies.

Custom apps appear in the App Store (unless `Config.AppStore` is `false`) and open in an embedded frame: SDK apps registered by manifest ([App SDK](./apps.md)) and client-registered apps from [Exports](./api/exports-events.md).

## Maps

Maps shows a road map image (`web/public/map.jpg`, fitted by `MAP_BOUNDS` in `web/src/apps/maps/GPSScreen.tsx`), the saved places from `Config.Server.Maps.Locations`, and visible game blips mirrored once per second while the app is open. The game minimap is repositioned behind the app and restored when it closes.

## Source layout

The React app lives in `web/src/`. `App.tsx` and `main.tsx` are a thin shell that mounts the phone.

- `core/` is the phone itself: the store and reducer, lock screen, home screen, status bar, notification shade, call overlay, handset chrome, the app registry (`appRegistry.ts`), and the hooks that wire the game in (`useHostEvents.ts` for NUI messages, `useBackgroundEffects.ts`, `useCallVideo.ts`, `usePhoneActions.ts`). Shared artwork such as `CoverArt.tsx` is here too.
- `apps/<app>/` holds one folder per built-in app (Mail, Wallet, Maps, Pulse, Flash, Market, Moderation, Settings and so on). Heavy apps load lazily in their own chunk. `apps/shared/` has pieces used by several social apps, and `apps/custom/` is the host for third-party apps.
- `api/` is the typed client for the game. `routes/` maps each UI action to a NUI route, `adapters/` converts raw server payloads into the UI types in `types.ts`, and `api/index.ts` is the only import the screens use.
- `sdk/` is the pure logic behind the third-party app host (protocol, permission gate, router, theme collector), shared with `@kora/phone-sdk` and covered by Node tests.

### Adding a built-in app

1. Create `web/src/apps/<app>/<App>.tsx` exporting a component that takes `{ target: string }`.
2. Add the id to `AppId` in `types.ts`, its label and tagline to `locales.ts`, and, if it is installable from the App Store, to `catalog.ts`.
3. Add one `entry(...)` line to `appRegistry` in `core/appRegistry.ts` with its icon, component (use the lazy `screen(...)` helper for heavy apps), placement (`grid`, `dock`, `system` or `hidden`) and optional App Store listing. Home screen, App Store, launch checks and routing all read this registry.
4. Add the server side id to the allow-list (see the features and config docs) and any routes the app needs under `web/src/api/routes/`.
5. Run `npx tsc --noEmit` and `npm run build` in `web/`, then the tests.

## Developing the UI

```sh
npm ci --prefix web
npm run dev --prefix web
npm run build --prefix web
```

Rebuild before deploying UI changes. `npm test --prefix web` runs the contract tests under `tests/`. Voice, game cameras, inventory and hosted media need a FiveM server; the standalone preview uses demonstration data. The `docs/images` folder holds the preview screenshots used by the README.

## App host

Third-party apps run in a sandboxed iframe at `https://cfx-nui-resource/entry` with `sandbox="allow-scripts allow-same-origin allow-forms"` and `referrerpolicy="no-referrer"`. The host lives in `web/src/apps/custom/CustomApps.tsx`; its pure logic is in `web/src/sdk/` (protocol, permission gate, router, theme collector) and is covered by `tests/customapps-host.test.js`.

- Messages use the envelope with fields `kora` set to `phone`, `v` set to `1`, `id`, `type` and `payload`. The host only accepts a message whose source is the iframe window and whose origin is the app origin, and drops anything else.
- Requests are `ready`, `callback`, `notify`, `storage.get`, `storage.set`, `storage.remove`, `contacts.list`, `contacts.save`, `close`, `setTitle`, `haptic` and `getContext`. Each gets a response with `ok` and either `payload` or `error` (code and message). Requests time out after 15 seconds with the code `TIMEOUT`, and at most 32 can be pending.
- The host pushes `init`, `theme`, `event` and `visibility`. `theme` is re-sent when the root element style or class changes. Colour values are the kora_theme HSL triplets, so apps use them as `hsl(var(--primary))`.
- The permission gate only improves the experience: a request without the manifest permission gets `PERMISSION_DENIED` without leaving the phone. The server re-checks every call against the registered manifest.
- Requests reach the server through a `HostTransport` with a single `request(route, payload)` method, defaulting to the NUI bridge. Routes are `apps:call`, `apps:notify`, `apps:storage:get`, `apps:storage:set`, `apps:storage:remove`, `apps:contacts:list` and `apps:contacts:save`, each with the app id added.
- The screen shows loading, error (no `ready` within 10 seconds, with a retry button) and offline (resource stopped) states, and removes all listeners and the theme observer when it unmounts.
- Events from the game side arrive as the NUI message `app:event` with fields app, name and data. Legacy `customMessage` messages carrying an action are delivered as events named after the action.

Legacy addons keep working through `web/public/compat.js`, which keeps `fetchNui`, `onNuiEvent`, `onSettingsChange`, `resourceName`, `appName` and `settings` on top of the protocol. Device settings reach them as the reserved event `kora:settings`.
