import { mockRequest } from '../mock';
import type { Api } from '../types';
import { isPreview, requestId } from './env';
import { handlers } from './routes';
import type { Action, Handler } from './routeTypes';
import { device } from './state';
import { nui, server } from './transport';

export { isDemo, isEmbed, demoModel, isPreview, requestId } from './env';
export { adaptBootstrap } from './session';
export { mapCall as adaptLiveCall } from './adapters/messages';
export { nui, server };

// UI actions that write to one specific handset carry its id, so a swap mid-save is refused.
const bindsDevice = new Set<Action>(['settings', 'installApp']);
// Requests run one at a time so cache updates never interleave. Uploads bypass the queue
// so a slow upload does not block the rest of the phone.
let queue: Promise<void> = Promise.resolve();

/** One call per UI action; typed by the `Api` table in types.ts. */
export function api<K extends keyof Api>(action: K, payload: Api[K][0], id = requestId()): Promise<Api[K][1]> {
    if (isPreview) return mockRequest(action, payload, id);
    const run = handlers[action] as Handler<K>;
    if (action === 'uploadMedia') return run(payload, { id });
    const bound = bindsDevice.has(action)
        ? { ...payload, expectedDeviceId: (payload as { expectedDeviceId?: string }).expectedDeviceId ?? device.activeId }
        : payload;
    const result = queue.then(() => run(bound, { id }));
    queue = result.then(() => undefined, () => undefined);
    return result;
}

/** Fire-and-forget: the server relays this to whoever is on the other end of the active call. */
export function sendSignal(data: Api['videoSignal'][0]): void {
    void api('videoSignal', data).catch(() => undefined);
}
