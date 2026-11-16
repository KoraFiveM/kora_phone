import type { Api } from '../types';

/** Every UI action: what the screen sends (`in`) and what it gets back (`out`). Derived from the `Api` table in types.ts. */
export type Routes = { [K in keyof Api]: { in: Api[K][0]; out: Api[K][1] } };
export type Action = keyof Routes;

/** Per-request context handed to every handler. */
export interface Ctx {
    /** Idempotency key for this UI action; sent to the server as `clientRequestId`. */
    id: string;
}

export type Handler<K extends Action> = (payload: Routes[K]['in'], ctx: Ctx) => Promise<Routes[K]['out']>;
/** A group of handlers; the full table must cover every action (checked in routes/index.ts). */
export type HandlerSet<K extends Action> = { [P in K]: Handler<P> };
export type Handlers = HandlerSet<Action>;
