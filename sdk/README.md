# @kora/phone-sdk

Typed SDK for Kora phone iframe apps (protocol v1). Zero-dependency core, optional React bindings.

## Quick start

```bash
npm i @kora/phone-sdk
```

app.json (declared in your resource fxmanifest as `kora_phone_app 'app.json'`):

```json
{ "id": "notes", "name": "Notes", "description": "Quick notes", "icon": "notebook",
  "entry": "ui/index.html", "version": "1.0.0", "permissions": ["storage", "notify"],
  "defaultInstalled": false }
```

Plain TypeScript:

```ts
import '@kora/phone-sdk/theme.css';
import { createPhoneClient } from '@kora/phone-sdk';

const phone = createPhoneClient();
const init = await phone.ready();          // waits for the host `init` push, applies theme vars
await phone.storage.set('draft', 'hello');
const reply = await phone.callback<{ id: number }, { ok: boolean }>('save', { id: 1 });
phone.on('refresh', (data) => console.log(data));
```

React:

```tsx
import { PhoneProvider, usePhoneStorage, useTheme } from '@kora/phone-sdk/react';

function Notes() {
    const { value, set } = usePhoneStorage<string>('draft');
    return <textarea value={value ?? ''} onChange={(e) => set(e.target.value)} />;
}
export const App = () => <PhoneProvider><Notes /></PhoneProvider>;
```

Theming: `theme.css` maps the real kora_theme tokens (HSL triplets the host forwards, such as `--background`, `--foreground`, `--primary`) to ready-to-use aliases: `--kp-bg`, `--kp-fg`, `--kp-surface`, `--kp-surface-raised`, `--kp-muted`, `--kp-accent`, `--kp-accent-fg`, `--kp-border`, `--kp-danger`, `--kp-success`, `--kp-radius`, `--kp-font`, `--kp-font-heading`, `--kp-font-mono`. Use them directly, for example `background: var(--kp-bg)`. Neutral fallbacks apply until `init` arrives. Also available: `phone.haptic()` and `phone.getContext()`.

Server callbacks are registered with `exports.kora_phone:RegisterAppCallback(appId, name, handler)`.
Errors are `PhoneError` with a `code` (`TIMEOUT`, `DESTROYED`, or the host's code).
The host origin defaults to `https://cfx-nui-kora_phone`; override with `createPhoneClient({ hostOrigin })`.
