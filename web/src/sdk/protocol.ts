// Host <-> iframe wire protocol (v1). See docs/ui.md "App host".
export const PROTOCOL = 'phone';
export const PROTOCOL_VERSION = 1;

export type Handset = 'standard' | 'flip' | 'fold';
export type Scheme = 'dark' | 'light';

export const PERMISSIONS = [
    'notify', 'storage', 'contacts.read', 'contacts.write', 'media.read', 'location', 'payments',
] as const;
export type Permission = typeof PERMISSIONS[number];

export const REQUEST_TYPES = [
    'ready', 'callback', 'client', 'open', 'refresh', 'call', 'lb', 'notify', 'storage.get', 'storage.list', 'storage.set', 'storage.remove',
    'contacts.list', 'contacts.save', 'close', 'setTitle', 'haptic', 'getContext',
] as const;
export type RequestType = typeof REQUEST_TYPES[number];

export type PushType = 'init' | 'theme' | 'event' | 'visibility';

export interface ThemePayload { vars: Record<string, string>; scheme: Scheme }

export interface InitPayload {
    appId: string;
    handset: Handset;
    locale: string;
    theme: ThemePayload;
    permissions: Permission[];
    target?: string;
}

export interface Envelope {
    kora: typeof PROTOCOL;
    v: typeof PROTOCOL_VERSION;
    id?: string;
    type: string;
    payload?: unknown;
}

export interface RequestEnvelope extends Envelope { id: string; type: RequestType }

export interface ErrorBody { code: string; message: string }

export type ResponseEnvelope = Envelope & { type: 'response'; id: string } & (
    { ok: true; payload?: unknown } | { ok: false; error: ErrorBody }
);

export const isRecord = (value: unknown): value is Record<string, unknown> =>
    typeof value === 'object' && value !== null && !Array.isArray(value);

const isRequestType = (value: unknown): value is RequestType =>
    typeof value === 'string' && (REQUEST_TYPES as readonly string[]).includes(value);

/** Narrow an unknown message body into a request envelope, or null when it is not one of ours. */
export function parseRequest(data: unknown): RequestEnvelope | null {
    if (!isRecord(data)) return null;
    if (data.kora !== PROTOCOL || data.v !== PROTOCOL_VERSION) return null;
    if (typeof data.id !== 'string' || data.id.length === 0 || data.id.length > 64) return null;
    if (!isRequestType(data.type)) return null;
    return { kora: PROTOCOL, v: PROTOCOL_VERSION, id: data.id, type: data.type, payload: data.payload };
}

export const push = (type: PushType, payload: unknown): Envelope =>
    ({ kora: PROTOCOL, v: PROTOCOL_VERSION, type, payload });

export const okResponse = (id: string, payload?: unknown): ResponseEnvelope =>
    ({ kora: PROTOCOL, v: PROTOCOL_VERSION, id, type: 'response', ok: true, payload });

export const errorResponse = (id: string, code: string, message: string): ResponseEnvelope =>
    ({ kora: PROTOCOL, v: PROTOCOL_VERSION, id, type: 'response', ok: false, error: { code, message } });

/** Expected iframe origin for an app resource: https://cfx-nui-<resource>. */
export const appOrigin = (resource: string): string => `https://cfx-nui-${resource}`;

/** Build the iframe URL. Entries that are already absolute https URLs are kept (legacy YSeries style). */
export function appUrl(resource: string, entry: string, params: Record<string, string> = {}): string {
    const base = /^https?:\/\//.test(entry) ? entry : `${appOrigin(resource)}/${entry.replace(/^\/+/, '')}`;
    const query = new URLSearchParams(params).toString();
    return query ? `${base}${base.includes('?') ? '&' : '?'}${query}` : base;
}

/** Origin of an arbitrary URL string, or '' when it cannot be parsed. */
export function originOf(url: string): string {
    try { return new URL(url).origin; } catch { return ''; }
}
