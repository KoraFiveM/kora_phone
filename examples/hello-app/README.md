# hello-app

Minimal example app for the kora_phone SDK (v1).

## Build

The SDK is a local `file:` dependency, so build it first, then the UI. `ui/dist` is not committed.

```bash
cd ../../sdk && npm install && npm run build
cd ../examples/hello-app/ui && npm install && npm run build
```

## Install

Copy or symlink this folder into your resources, then `ensure kora_phone` followed by `ensure hello-app`. The app appears on the home screen because `defaultInstalled` is true.

Files: `app.json` (manifest), `server/main.lua` (callback `increment`), `ui/` (TypeScript + Vite). See `docs/apps.md`.
