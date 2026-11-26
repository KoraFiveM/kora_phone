import { items } from '../adapters/common';
import { mapCall } from '../adapters/messages';
import type { RawCall } from '../raw';
import type { HandlerSet } from '../routeTypes';
import { server } from '../transport';

export const messagingRoutes: HandlerSet<
    'dial' | 'answer' | 'hangup' | 'videoSignal' | 'blocked' | 'setBlocked'
> = {
    dial: async p => mapCall(await server<RawCall>('calls:start', { to: p.number })),
    answer: async p => mapCall(await server<RawCall>('calls:accept', { id: p.id })),
    hangup: async p => { await server(p.reject ? 'calls:reject' : 'calls:hangup', { id: p.id }); return true; },
    videoSignal: async p => {
        await server('calls:signal', { id: p.id, epoch: p.epoch, kind: p.kind, sdp: p.sdp, candidate: p.candidate });
        return true;
    },
    blocked: async () => items(await server<{ items?: { number: string }[] }>('blocks:list')).map(x => String(x.number)),
    setBlocked: async p => { await server('blocks:set', { number: p.number, blocked: p.blocked }); return true; },
};
