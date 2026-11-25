import { appOrigin, errorResponse, okResponse, parseRequest, push, isRecord } from './protocol';
import type { Handset, InitPayload, Permission, RequestEnvelope, ResponseEnvelope, ThemePayload } from './protocol';
import { isAllowed } from './permissions';

/** Sends a request to the phone's NUI routes. Resolves with the data, rejects with an Error (optional `code`). */
export interface HostTransport {
    request(route: string, payload: Record<string, unknown>): Promise<unknown>;
}

export interface RouterOptions {
    appId: string;
    resource: string;
    permissions: readonly Permission[];
    transport: HostTransport;
    handset: Handset;
    locale: string;
    getTheme: () => ThemePayload;
    /** Replies and pushes go through this; it is bound to iframe.contentWindow + the app origin. */
    post: (message: unknown) => void;
    /** Called after the ready response and the init push have been posted. */
    onReady?: () => void;
    onClose?: () => void;
    onSetTitle?: (title: string) => void;
    /** Opens another app. Receives a validated app id and an optional short target (a number, a thread). */
    onOpen?: (app: string, target?: string) => void;
    /** Starts a call. Receives a validated number (7 to 16 digits). */
    onCall?: (number: string) => Promise<unknown> | unknown;
    /** Reloads the data the host keeps for other screens (contacts and the like). */
    onRefresh?: () => Promise<unknown> | unknown;
    /** Opening hint for this app (see InitPayload.target). */
    target?: string;
    /** lb-phone compatibility actions (contacts, gallery, call, openApp). Absent for every other app, which then cannot use the `lb` request. */
    onLb?: (action: string, payload: Record<string, unknown>) => Promise<unknown> | unknown;
    timeoutMs?: number;
    /** Allowed overrides for tests/legacy hosts that hand back a fully qualified entry URL. */
    origin?: string;
}

export interface MessageLike { source: unknown; origin: string; data: unknown }

export const REQUEST_TIMEOUT_MS = 15000;
const MAX_PENDING = 32;

/** Source + origin validation. `expectedSource` is iframe.contentWindow. */
export function isTrustedMessage(event: MessageLike, expectedSource: unknown, origin: string): boolean {
    return expectedSource !== null && expectedSource !== undefined
        && event.source === expectedSource && event.origin === origin;
}

const errorOf = (error: unknown): { code: string; message: string } => {
    if (isRecord(error) || error instanceof Error) {
        const body = error as { code?: unknown; message?: unknown };
        return {
            code: typeof body.code === 'string' ? body.code : 'REQUEST_FAILED',
            message: typeof body.message === 'string' ? body.message : 'Request failed',
        };
    }
    return { code: 'REQUEST_FAILED', message: typeof error === 'string' ? error : 'Request failed' };
};

class RouteError extends Error {
    constructor(public code: string, message: string) { super(message); }
}

/** Server replies are `{ok,data}` / `{ok:false,error}`; unwrap them, pass anything else through. */
export function unwrap(result: unknown): unknown {
    if (isRecord(result) && typeof result.ok === 'boolean') {
        if (result.ok) return 'data' in result ? result.data : undefined;
        throw errorOf(result.error ?? result);
    }
    return result;
}

const str = (value: unknown, max: number): string | undefined =>
    typeof value === 'string' && value.length > 0 && value.length <= max ? value : undefined;

export function createRouter(options: RouterOptions) {
    const { appId, transport, post } = options;
    const origin = options.origin ?? appOrigin(options.resource);
    const timeoutMs = options.timeoutMs ?? REQUEST_TIMEOUT_MS;
    let pending = 0;
    let ready = false;
    let disposed = false;

    const withTimeout = <T,>(work: Promise<T>): Promise<T> => new Promise<T>((resolve, reject) => {
        const timer = setTimeout(() => reject(new RouteError('TIMEOUT', 'The request timed out')), timeoutMs);
        work.then(
            value => { clearTimeout(timer); resolve(value); },
            error => { clearTimeout(timer); reject(error); },
        );
    });

    const call = async (route: string, payload: Record<string, unknown>): Promise<unknown> =>
        unwrap(await withTimeout(transport.request(route, { app: appId, ...payload })));

    const handlers: Record<RequestEnvelope['type'], (payload: Record<string, unknown>) => Promise<unknown> | unknown> = {
        ready: () => { ready = true; return init(); },
        getContext: () => init(),
        callback: payload => {
            const name = typeof payload.name === 'string' && /^[a-zA-Z0-9_:.-]{1,48}$/.test(payload.name) ? payload.name : undefined;
            if (!name) throw new RouteError('INVALID_PAYLOAD', 'Invalid callback name');
            return call('apps:call', { name, payload: payload.payload });
        },
        open: payload => {
            const app = typeof payload.app === 'string' && /^[a-z0-9][a-z0-9_-]{1,31}$/.test(payload.app) ? payload.app : undefined;
            if (!app) throw new RouteError('INVALID_PAYLOAD', 'Invalid app id');
            const target = typeof payload.target === 'string' && payload.target.length <= 64 ? payload.target : undefined;
            options.onOpen?.(app, target);
            return null;
        },
        call: async payload => {
            const number = typeof payload.number === 'string' && /^\d{7,16}$/.test(payload.number) ? payload.number : undefined;
            if (!number) throw new RouteError('INVALID_PAYLOAD', 'Enter a valid number');
            if (!options.onCall) throw new RouteError('PERMISSION_DENIED', 'Not available to this app');
            await options.onCall(number);
            return null;
        },
        refresh: async () => { await options.onRefresh?.(); return null; },
        lb: payload => {
            if (!options.onLb) throw new RouteError('PERMISSION_DENIED', 'Not available to this app');
            const action = str(payload.action, 32);
            if (!action) throw new RouteError('INVALID_PAYLOAD', 'An action is required');
            return options.onLb(action, payload);
        },
        client: payload => {
            const name = typeof payload.name === 'string' && /^[a-zA-Z0-9_:.-]{1,48}$/.test(payload.name) ? payload.name : undefined;
            if (!name) throw new RouteError('INVALID_PAYLOAD', 'Invalid client callback name');
            return call('apps:client', { name, payload: payload.payload });
        },
        notify: async payload => {
            const title = str(payload.title, 64);
            if (!title) throw new RouteError('INVALID_PAYLOAD', 'A title is required');
            const body = typeof payload.body === 'string' ? payload.body.slice(0, 200) : '';
            await call('apps:notify', { title, body });
            return true;
        },
        'storage.get': async payload => {
            const data = await call('apps:storage:get', { key: requireKey(payload) });
            return isRecord(data) && data.value !== undefined ? data.value : null;
        },
        'storage.list': async payload => {
            const prefix = typeof payload.prefix === 'string' ? payload.prefix.slice(0, 64) : undefined;
            const data = await call('apps:storage:list', { prefix });
            return isRecord(data) && isRecord(data.values) ? data.values : {};
        },
        'storage.set': async payload => {
            await call('apps:storage:set', { key: requireKey(payload), value: payload.value });
            return true;
        },
        'storage.remove': async payload => {
            await call('apps:storage:remove', { key: requireKey(payload) });
            return true;
        },
        'contacts.list': async () => {
            const data = await call('apps:contacts:list', {});
            return isRecord(data) && Array.isArray(data.contacts) ? data.contacts : [];
        },
        'contacts.save': async payload => {
            const name = str(payload.name, 64);
            const number = str(payload.number, 32);
            if (!name || !number) throw new RouteError('INVALID_PAYLOAD', 'A name and number are required');
            const data = await call('apps:contacts:save', { id: payload.id, name, number });
            return { id: isRecord(data) ? data.id : payload.id, name, number };
        },
        close: () => { options.onClose?.(); return null; },
        setTitle: payload => { options.onSetTitle?.(str(payload.title, 48) ?? ''); return null; },
        haptic: () => true,
    };

    function requireKey(payload: Record<string, unknown>): string {
        const key = str(payload.key, 64);
        if (!key) throw new RouteError('INVALID_PAYLOAD', 'A storage key is required');
        return key;
    }

    function init(): InitPayload {
        return {
            appId,
            handset: options.handset,
            locale: options.locale,
            theme: options.getTheme(),
            permissions: [...options.permissions],
            ...(options.target ? { target: options.target } : {}),
        };
    }

    async function respond(request: RequestEnvelope): Promise<ResponseEnvelope> {
        if (!isAllowed(options.permissions, request.type)) {
            return errorResponse(request.id, 'PERMISSION_DENIED', `Missing permission for ${request.type}`);
        }
        try {
            const payload = isRecord(request.payload) ? request.payload : {};
            return okResponse(request.id, await handlers[request.type](payload));
        } catch (error) {
            const { code, message } = errorOf(error);
            return errorResponse(request.id, code, message);
        }
    }

    /** Returns true when the message was ours and handled; false when it was dropped. */
    async function handle(event: MessageLike, expectedSource: unknown): Promise<boolean> {
        if (disposed || !isTrustedMessage(event, expectedSource, origin)) return false;
        const request = parseRequest(event.data);
        if (!request) return false;
        if (pending >= MAX_PENDING) {
            post(errorResponse(request.id, 'RATE_LIMITED', 'Too many pending requests'));
            return true;
        }
        pending += 1;
        try {
            const response = await respond(request);
            if (!disposed) {
                post(response);
                // SDK clients resolve ready() only after the response AND this init push.
                if (request.type === 'ready' && response.ok) {
                    post(push('init', init()));
                    options.onReady?.();
                }
            }
        } finally {
            pending -= 1;
        }
        return true;
    }

    return {
        origin,
        handle,
        isReady: () => ready,
        dispose: () => { disposed = true; },
    };
}

export type Router = ReturnType<typeof createRouter>;
