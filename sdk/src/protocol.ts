export const PROTOCOL_NAME = 'phone' as const;
export const PROTOCOL_VERSION = 1 as const;
export const DEFAULT_HOST_ORIGIN = 'https://cfx-nui-kora_phone';
export const DEFAULT_TIMEOUT_MS = 10000;

export type Permission =
    | 'notify'
    | 'storage'
    | 'contacts.read'
    | 'contacts.write'
    | 'media.read'
    | 'location'
    | 'payments';

export type Handset = 'standard' | 'flip' | 'fold';
export type Scheme = 'dark' | 'light';

export type Json = string | number | boolean | null | Json[] | { [key: string]: Json };

export interface Contact {
    id?: string | number;
    name: string;
    number: string;
}

export interface ThemeState {
    vars: Record<string, string>;
    scheme: Scheme;
}

export interface InitPayload {
    appId: string;
    handset: Handset;
    locale: string;
    theme: ThemeState;
    permissions: Permission[];
}

/** iframe -> host requests: payload and response types per request type. */
export interface RequestMap {
    ready: { payload: Record<string, never> | undefined; result: unknown };
    callback: { payload: { name: string; payload?: unknown }; result: unknown };
    notify: { payload: { title: string; body: string }; result: unknown };
    'storage.get': { payload: { key: string }; result: Json | null };
    'storage.set': { payload: { key: string; value: Json }; result: unknown };
    'storage.remove': { payload: { key: string }; result: unknown };
    'contacts.list': { payload: undefined; result: Contact[] };
    'contacts.save': { payload: Contact; result: Contact | unknown };
    close: { payload: undefined; result: unknown };
    setTitle: { payload: { title: string }; result: unknown };
    haptic: { payload: Record<string, never>; result: unknown };
    getContext: { payload: undefined; result: InitPayload };
}
export type RequestType = keyof RequestMap;

/** host -> iframe pushes. */
export interface PushMap {
    init: InitPayload;
    theme: ThemeState;
    event: { name: string; data?: unknown };
    visibility: { visible: boolean };
}
export type PushType = keyof PushMap;

interface EnvelopeBase {
    kora: typeof PROTOCOL_NAME;
    v: typeof PROTOCOL_VERSION;
}

export interface RequestMessage<T extends RequestType = RequestType> extends EnvelopeBase {
    id: string;
    type: T;
    payload?: RequestMap[T]['payload'];
}

export interface ErrorBody {
    code: string;
    message: string;
}

export interface ResponseOk<R = unknown> extends EnvelopeBase {
    id: string;
    type: 'response';
    ok: true;
    payload?: R;
}

export interface ResponseError extends EnvelopeBase {
    id: string;
    type: 'response';
    ok: false;
    error: ErrorBody;
}

export type ResponseMessage<R = unknown> = ResponseOk<R> | ResponseError;

export type PushMessage = {
    [K in PushType]: EnvelopeBase & { id?: string; type: K; payload: PushMap[K] };
}[PushType];

export type HostMessage = ResponseMessage | PushMessage;

export const PUSH_TYPES: readonly PushType[] = ['init', 'theme', 'event', 'visibility'];

export function isEnvelope(value: unknown): value is EnvelopeBase & { type: string } {
    if (typeof value !== 'object' || value === null) return false;
    const v = value as Record<string, unknown>;
    return v.kora === PROTOCOL_NAME && v.v === PROTOCOL_VERSION && typeof v.type === 'string';
}

export type PhoneErrorCode = 'TIMEOUT' | 'NOT_READY' | 'DESTROYED' | 'REQUEST_FAILED' | string;
