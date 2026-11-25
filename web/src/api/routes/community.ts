import { items } from '../adapters/common';
import { mapMail } from '../adapters/mail';
import type { RawMail } from '../raw';
import type { HandlerSet } from '../routeTypes';
import { server } from '../transport';
import { uploadMedia } from '../upload';

const done = async (work: Promise<unknown>): Promise<true> => { await work; return true; };

const mailAndCommunity: HandlerSet<
    'uploadMedia'
    | 'mailList' | 'mailSend' | 'mailRead' | 'mailDelete'
> = {
    uploadMedia: p => uploadMedia(p),
    mailList: async p => items(await server<{ items?: RawMail[] }>('mail:list', { box: p.box, limit: 50, cursor: p.before })).map(mapMail),
    mailSend: (p, { id }) => done(server('mail:send', { to: p.to, subject: p.subject, body: p.body, clientRequestId: id })),
    mailRead: p => done(server('mail:read', { id: p.id })),
    mailDelete: p => done(server('mail:delete', { id: p.id })),
};

export const communityRoutes: HandlerSet<keyof typeof mailAndCommunity> = mailAndCommunity;
