---
title: "App style guide"
sidebar_position: 5.6
---

# App style guide

Every app that ships in `apps/` follows this guide, and `tools/check-app.mjs` enforces the rules that can be checked by a machine. Apps from other resources should follow it too; lb-phone apps are exempt because they bring their own look (see [lb-phone apps](./lb-phone.md)).

The goal: a player cannot tell which app was written by whom. The phone owns colour, type and shape through `kora_theme`; an app owns layout and content.

## The rules the linter checks

Run `node tools/check-app.mjs` (all apps) or `node tools/check-app.mjs apps/notes` (one). It runs inside `LUA=lua5.4 bash test/run.sh` as well, so a style error fails the build.

| Rule | What fails | Do this instead |
| --- | --- | --- |
| `colour-hex`, `colour-rgb`, `colour-hsl`, `colour-name` | Any hex, `rgb()`, `hsl()` with numbers, or named colour in CSS, a `style` block or a `style` attribute | Use a kit class, `var(--kp-accent)`, or wrap a token: `hsl(var(--primary))` |
| `font-family` | A `font-family` that is not `inherit` or a `var()` | Nothing: the theme font is already applied. Monospace: `var(--kp-font-mono)` |
| `radius-px` | A fixed `border-radius` | `var(--kp-radius)`, `var(--kp-radius-sm)`, `var(--kp-radius-lg)` |
| `important` | `!important` | Fix the selector |
| `external-url` | Any `http` or `https` URL that is not the phone itself | Ship the file inside the app folder |
| `app-lua`, `app-id`, `app-field`, `ui-entry` | Missing or wrong `app.lua`, id not equal to the folder name, no `name` or `icon`, UI entry file missing | See [App SDK developer guide](./apps.md) |
| `kit-css` | `ui/index.html` does not link `/sdk/runtime/kora-ui.css` | Add the link |
| `states` (warning) | No loading, empty or error state in the UI | Use `states.*` or `load()` from the kit |

## Colour, type and shape

- Colour comes from kora_theme tokens only. The kit maps them to `--kp-*` aliases: `--kp-bg`, `--kp-fg`, `--kp-surface`, `--kp-surface-raised`, `--kp-muted`, `--kp-accent`, `--kp-accent-fg`, `--kp-border`, `--kp-danger`, `--kp-success`, `--kp-warning`.
- Use accent colour for the one primary action on a screen, never for decoration. Use `danger` only for destructive actions and errors.
- Light and dark both work because you never name a colour. Test your app in both (Settings, Appearance).
- Text sizes: body is the default (15px). Use the kit title class for page titles and `kp-section-label` for section headings. Do not set your own font sizes below 0.75rem.
- Corners and shadows come from the theme. An app must not decide that it is rounder or sharper than the rest of the phone.

## Layout

- Your page fills the phone's app area. The handset (Standard, Flip, Fold) is not your business: use ordinary `@media` and `@container` queries on your own width.
- Structure every screen as `kp-app` containing `kp-header` and `kp-content` (optionally `kp-footer`). The header holds one title and at most two icon buttons.
- Touch targets are at least 44px (`--kp-target`). Spacing uses multiples of 4px. Lists use `kp-list` and `kp-row`.
- Use `kp-split` for list plus detail. On a narrow screen it shows one pane at a time, on an unfolded Atlas Fold it shows both.
- Never scroll the whole page. The content area scrolls; the header and footer stay put.
- Navigation: a detail screen has a back icon button at the start of the header. The phone's own home button leaves the app, so an app never needs a home button.

## The three states

Every screen that loads data shows one of these, never a blank area:

| State | Kit helper | Tone |
| --- | --- | --- |
| Loading | `states.loading()` | Spinner, optional short label |
| Empty | `states.empty(title, detail)` | A title that invites an action ("Space to think") plus one sentence |
| Error | `states.error(title, detail, retry)` | Say what happened in plain words and offer Try again |

`load(root, loader, view, options)` runs the loader and picks the state for you.

## Copy

- Sentence case. Short labels. A button says what it does ("Save note", not "OK").
- Write for a player, not a developer: no error codes, no resource names.
- Every visible string goes through `i18n({ en: {...}, nl: {...} })` from the kit. English is the fallback, so an app with only `en` is valid.
- Dates and numbers use `Intl` with the locale from the phone, never a hard-coded format.

## Icons

- The app icon is a single-colour SVG at `apps/<id>/icon.svg`, drawn on a 24 by 24 grid with a 1.75 stroke and `currentColor`. `icon = 'icon.svg'` in `app.lua` points at it; the phone draws it as a mask in the theme colour, so it can never clash.
- Icons inside the UI come from the kit (`icon('plus')`) or inline SVG that uses `currentColor`.
- Never ship a coloured, photographic or gradient app icon.

## Motion and feedback

- Keep transitions at or under the theme durations (`--duration-fast`, `--duration-popover`). The kit already respects reduced motion.
- Confirm destructive actions with `confirm({ danger: true })`. Confirm success with `toast()`, not a dialog.
- Call `phone.haptic()` on a meaningful tap (a toggle, a delete), not on every tap.

## Accessibility

- Buttons that only show an icon need an `aria-label`.
- Inputs need a visible label or an `aria-label`. Errors use `aria-invalid` and text, not colour alone.
- Everything must work with a mouse only (the phone is used with the NUI cursor) and show a visible focus ring (the kit supplies one).

## Reference apps

`apps/notes` is the model for a data app (storage, list and detail, confirm on delete, all three states). `apps/calculator` is the model for a pure-UI app and `apps/weather` for an app that reads game state through its `client.lua`. `node tools/new-app.mjs my-app "My App"` scaffolds a new app that already passes the linter.
