import {
    DEFAULT_HOST_ORIGIN,
    DEFAULT_TIMEOUT_MS,
    PROTOCOL_NAME,
    PROTOCOL_VERSION,
    PUSH_TYPES,
    isEnvelope,
    type Contact,
    type InitPayload,
    type Json,
    type PushMap,
    type PushType,
    type RequestMap,
    type RequestMessage,
    type RequestType,
    type ThemeState,
} from './protocol.js';

export class PhoneError extends Error {
    readonly code: string;
    constructor(code: string, message: string) {
        super(message);
        this.name = 'PhoneError';
        this.code = code;
    }
}

export interface MessageEventLike {
    data: unknown;
    origin: string;
    source: unknown;
}

/** Minimal window surface the client needs (lets tests inject a fake). */
export interface PhoneWindow {
    parent: { postMessage(message: unknown, targetOrigin: string): void };
    addEventListener(type: 'message', listener: (event: MessageEventLike) => void): void;
    removeEventListener(type: 'message', listener: (event: MessageEventLike) => void): void;
    document?: { documentElement: { style: { setProperty(name: string, value: string): void } } };
}

export interface PhoneClientOptions {
    /** Window to use. Defaults to the global window. */
    window?: PhoneWindow;
    /** Accepted host origin. Defaults to https://cfx-nui-kora_phone. */
    hostOrigin?: string;
    /** Per-request timeout in ms. Default 10000. */
    timeoutMs?: number;
    /** Generates request ids. Defaults to crypto.randomUUID. */
    idFactory?: () => string;
}

export type Unsubscribe = () => void;

export interface PhoneClient {
    ready(): Promise<InitPayload>;
    readonly theme: ThemeState | null;
    readonly init: InitPayload | null;
    callback<TIn = unknown, TOut = unknown>(name: string, payload?: TIn): Promise<TOut>;
    notify(title: string, body: string): Promise<void>;
    storage: {
        get<T extends Json = Json>(key: string): Promise<T | null>;
        set<T extends Json = Json>(key: string, value: T): Promise<void>;
        remove(key: string): Promise<void>;
    };
    contacts: {
        list(): Promise<Contact[]>;
        save(contact: Contact): Promise<Contact>;
    };
    on(event: string, cb: (data: unknown) => void): Unsubscribe;
    onTheme(cb: (theme: ThemeState) => void): Unsubscribe;
    onVisibility(cb: (visible: boolean) => void): Unsubscribe;
    close(): Promise<void>;
    setTitle(title: string): Promise<void>;
    haptic(): Promise<void>;
    getContext(): Promise<InitPayload>;
    destroy(): void;
}

interface Pending {
    resolve(value: unknown): void;
    reject(error: PhoneError): void;
    timer: ReturnType<typeof setTimeout>;
}

function defaultId(): string {
    return globalThis.crypto.randomUUID();
}

export function applyTheme(
    win: PhoneWindow,
    theme: ThemeState,
    applied: Set<string> = new Set(),
): void {
    const style = win.document?.documentElement.style;
    if (!style) return;
    for (const [name, value] of Object.entries(theme.vars)) {
        if (typeof value !== 'string') continue;
        style.setProperty(name.startsWith('--') ? name : `--${name}`, value);
        applied.add(name);
    }
    style.setProperty('color-scheme', theme.scheme);
}

export function createPhoneClient(options: PhoneClientOptions = {}): PhoneClient {
    const win: PhoneWindow = options.window ?? (globalThis as unknown as { window: PhoneWindow }).window;
    if (!win) throw new PhoneError('NO_WINDOW', 'createPhoneClient requires a window');
    const hostOrigin = options.hostOrigin ?? DEFAULT_HOST_ORIGIN;
    const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    const nextId = options.idFactory ?? defaultId;

    const pending = new Map<string, Pending>();
    const eventSubs = new Map<string, Set<(data: unknown) => void>>();
    const themeSubs = new Set<(theme: ThemeState) => void>();
    const visibilitySubs = new Set<(visible: boolean) => void>();
    let init: InitPayload | null = null;
    let theme: ThemeState | null = null;
    let destroyed = false;
    let readyPromise: Promise<InitPayload> | null = null;
    let resolveInit: ((value: InitPayload) => void) | null = null;
    const initPromise = new Promise<InitPayload>((resolve) => {
        resolveInit = resolve;
    });

    const handlePush = <K extends PushType>(type: K, payload: PushMap[K]): void => {
        if (type === 'init') {
            const p = payload as PushMap['init'];
            init = p;
            theme = p.theme;
            applyTheme(win, p.theme);
            resolveInit?.(p);
        } else if (type === 'theme') {
            const p = payload as PushMap['theme'];
            theme = p;
            applyTheme(win, p);
            themeSubs.forEach((cb) => cb(p));
        } else if (type === 'event') {
            const p = payload as PushMap['event'];
            eventSubs.get(p.name)?.forEach((cb) => cb(p.data));
        } else if (type === 'visibility') {
            const p = payload as PushMap['visibility'];
            visibilitySubs.forEach((cb) => cb(p.visible));
        }
    };

    const listener = (event: MessageEventLike): void => {
        if (event.source !== win.parent) return;
        if (event.origin !== hostOrigin) return;
        const msg = event.data;
        if (!isEnvelope(msg)) return;
        const record = msg as unknown as Record<string, unknown>;
        if (msg.type === 'response') {
            const id = record.id;
            if (typeof id !== 'string') return;
            const entry = pending.get(id);
            if (!entry) return;
            pending.delete(id);
            clearTimeout(entry.timer);
            if (record.ok === true) {
                entry.resolve(record.payload);
            } else {
                const err = record.error as { code?: unknown; message?: unknown } | undefined;
                entry.reject(
                    new PhoneError(
                        typeof err?.code === 'string' ? err.code : 'REQUEST_FAILED',
                        typeof err?.message === 'string' ? err.message : 'Request failed',
                    ),
                );
            }
            return;
        }
        if ((PUSH_TYPES as readonly string[]).includes(msg.type)) {
            handlePush(msg.type as PushType, record.payload as PushMap[PushType]);
        }
    };
    win.addEventListener('message', listener);

    function request<T extends RequestType>(
        type: T,
        payload?: RequestMap[T]['payload'],
    ): Promise<RequestMap[T]['result']> {
        if (destroyed) return Promise.reject(new PhoneError('DESTROYED', 'Phone client destroyed'));
        const id = nextId();
        const message: RequestMessage<T> = {
            kora: PROTOCOL_NAME,
            v: PROTOCOL_VERSION,
            id,
            type,
            ...(payload === undefined ? {} : { payload }),
        };
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                pending.delete(id);
                reject(new PhoneError('TIMEOUT', `Request ${type} timed out after ${timeoutMs}ms`));
            }, timeoutMs);
            pending.set(id, { resolve: resolve as (v: unknown) => void, reject, timer });
            win.parent.postMessage(message, hostOrigin);
        });
    }

    function subscribe<T>(set: Set<T>, cb: T): Unsubscribe {
        set.add(cb);
        return () => {
            set.delete(cb);
        };
    }

    return {
        ready() {
            if (!readyPromise) {
                readyPromise = request('ready', undefined).then(() => initPromise);
                // Surface the failure but allow retry.
                readyPromise.catch(() => {
                    readyPromise = null;
                });
            }
            return readyPromise;
        },
        get theme() {
            return theme;
        },
        get init() {
            return init;
        },
        async callback<TIn = unknown, TOut = unknown>(name: string, payload?: TIn): Promise<TOut> {
            return (await request('callback', { name, payload })) as TOut;
        },
        async notify(title, body) {
            await request('notify', { title, body });
        },
        storage: {
            async get<T extends Json = Json>(key: string) {
                const value = await request('storage.get', { key });
                return (value ?? null) as T | null;
            },
            async set(key, value) {
                await request('storage.set', { key, value });
            },
            async remove(key) {
                await request('storage.remove', { key });
            },
        },
        contacts: {
            async list() {
                return (await request('contacts.list', undefined)) ?? [];
            },
            async save(contact) {
                return (await request('contacts.save', contact)) as Contact;
            },
        },
        on(name, cb) {
            let set = eventSubs.get(name);
            if (!set) {
                set = new Set();
                eventSubs.set(name, set);
            }
            return subscribe(set, cb);
        },
        onTheme: (cb) => subscribe(themeSubs, cb),
        onVisibility: (cb) => subscribe(visibilitySubs, cb),
        async close() {
            await request('close', undefined);
        },
        async setTitle(title) {
            await request('setTitle', { title });
        },
        async haptic() {
            await request('haptic', {});
        },
        async getContext() {
            const ctx = (await request('getContext', undefined)) as InitPayload;
            init = ctx;
            return ctx;
        },
        destroy() {
            destroyed = true;
            win.removeEventListener('message', listener);
            for (const [id, entry] of pending) {
                clearTimeout(entry.timer);
                entry.reject(new PhoneError('DESTROYED', 'Phone client destroyed'));
                pending.delete(id);
            }
        },
    };
}
