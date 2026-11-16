import { errorText, type ServerResult } from './errors';
import { isPreview } from './env';

/** Some UI-facing route names differ from the client callback that serves them. */
const routeAliases: Record<string, string> = { uiReady: 'phone:ready', close: 'phone:close', captureDone: 'camera:close' };

/** Raw NUI POST to the phone client script. In the preview it answers `{ ok: true }`. */
export async function nui<T>(route: string, body: unknown = {}): Promise<T> {
    if (isPreview) return { ok: true } as T;
    // FiveM's embedded CEF predates AbortSignal.timeout (Chromium 103+); it is undefined there,
    // which used to throw on every request before any fetch was attempted. Fall back to no signal.
    const signal = typeof AbortSignal !== 'undefined' && typeof AbortSignal.timeout === 'function'
        ? AbortSignal.timeout(33000)
        : undefined;
    const response = await fetch(`https://${window.GetParentResourceName!()}/${routeAliases[route] || route}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body),
        signal,
    });
    if (!response.ok) throw new Error('Phone connection unavailable');
    return response.json();
}

/** NUI call to a server-backed route: unwraps `{ ok, data }` and throws the friendly error text. */
export async function server<T = unknown>(route: string, body: unknown = {}): Promise<T> {
    const result = await nui<ServerResult<T>>(route, body);
    if (!result.ok) throw new Error(errorText(result.error));
    return result.data;
}
