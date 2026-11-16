import type { Post } from '../../types';
import { items } from '../adapters/common';
import { mapComment, mapListing, mapPost, mapReport, splitListing } from '../adapters/social';
import { mapActivity, mapMail, mapMailAccept, mapSystemMail } from '../adapters/mail';
import type { RawActivity, RawComment, RawListing, RawMail, RawMailAccept, RawPost, RawReport } from '../raw';
import type { HandlerSet } from '../routeTypes';
import { server } from '../transport';
import { uploadMedia } from '../upload';

const done = async (work: Promise<unknown>): Promise<true> => { await work; return true; };

const mailAndCommunity: HandlerSet<
    'feed' | 'post' | 'uploadMedia' | 'createProfile' | 'removePost' | 'reportListing' | 'moderationQueue'
    | 'moderationResolve' | 'markSold' | 'contactSeller' | 'like' | 'comments' | 'comment' | 'removeComment'
    | 'systemMailList' | 'systemActivity' | 'mailAccept' | 'systemMailRead' | 'systemMailDelete'
    | 'mailList' | 'mailSend' | 'mailRead' | 'mailDelete'
> = {
    feed: async (p): Promise<Post[]> => p.kind === 'classifieds'
        ? items(await server<{ items?: RawListing[] }>('market:getListings', { limit: 30, cursor: p.before })).map(mapListing)
        : items(await server<{ items?: RawPost[] }>('social:getFeed', { limit: 30, cursor: p.before })).map(mapPost),
    post: (p, { id }) => done(p.kind === 'classifieds'
        ? server('market:createListing', { ...splitListing(p.body), category: 'other', price: p.price, clientRequestId: id })
        : server('social:createPost', { body: p.body, mediaId: p.mediaId, clientRequestId: id })),
    uploadMedia: p => uploadMedia(p),
    createProfile: p => done(server('social:createAccount', { handle: p.handle, displayName: p.displayName })),
    removePost: p => done(server(p.kind === 'flash' ? 'social:deletePost' : 'market:removeListing', { id: p.id })),
    reportListing: p => done(server('social:report', { targetType: 'listing', targetId: p.id, reason: p.reason, details: p.details })),
    moderationQueue: async p => items(await server<{ items?: RawReport[] }>('moderation:getQueue', {
        status: p.status || 'open', limit: 50,
    })).map(mapReport),
    moderationResolve: p => done(server('moderation:resolve', { reportId: p.reportId, action: p.action, note: p.note })),
    markSold: p => done(server('market:markSold', { id: p.id })),
    contactSeller: (p, { id }) => done(server('market:contactSeller', { id: p.id, message: p.message, clientRequestId: id })),
    like: p => done(server('social:toggleLike', { postId: p.id, liked: p.liked })),
    comments: async p => items(await server<{ items?: RawComment[] }>('social:getComments', { postId: p.id, limit: 50 })).map(mapComment),
    comment: (p, { id }) => done(server('social:createComment', { postId: p.id, body: p.body, clientRequestId: id })),
    removeComment: p => done(server('social:deleteComment', { id: p.id })),
    systemMailList: async p => items(await server<{ items?: RawMail[] }>('mail:system:list', { limit: 50, cursor: p.before })).map(mapSystemMail),
    systemActivity: async p => items(await server<{ items?: RawActivity[] }>('mail:system:activity', { limit: 50, cursor: p.before })).map(mapActivity),
    mailAccept: async p => mapMailAccept(await server<RawMailAccept>('mail:system:accept', { id: p.id })),
    systemMailRead: p => done(server('mail:system:read', { id: p.id })),
    systemMailDelete: p => done(server('mail:system:delete', { id: p.id })),
    mailList: async p => items(await server<{ items?: RawMail[] }>('mail:list', { box: p.box, limit: 50, cursor: p.before })).map(mapMail),
    mailSend: (p, { id }) => done(server('mail:send', { to: p.to, subject: p.subject, body: p.body, clientRequestId: id })),
    mailRead: p => done(server('mail:read', { id: p.id })),
    mailDelete: p => done(server('mail:delete', { id: p.id })),
};

export const communityRoutes: HandlerSet<keyof typeof mailAndCommunity> = mailAndCommunity;
