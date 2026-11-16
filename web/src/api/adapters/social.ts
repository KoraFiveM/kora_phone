import type { Comment, ModerationReport, Post } from '../../types';
import type { RawComment, RawListing, RawPost, RawReport } from '../raw';
import { isFlag } from '../raw';
import { kindOf, stamp } from './common';

export const mapListing = (x: RawListing): Post => ({
    id: x.id,
    number: x.sellerHandle || x.sellerName || 'seller',
    body: x.title + (x.description ? `\n${x.description}` : ''),
    price: x.price,
    created_at: stamp(x.createdAt),
    likes: 0,
    comments: 0,
    liked: false,
    mine: x.isOwner ?? false,
});

export const mapPost = (x: RawPost): Post => ({
    id: x.id,
    number: x.handle || x.displayName || '',
    body: x.body,
    price: 0,
    created_at: stamp(x.createdAt),
    likes: x.likeCount || 0,
    comments: x.commentCount || 0,
    liked: !!x.liked,
    mine: isFlag(x.mine),
    media_url: x.mediaUrl || undefined,
    media_kind: kindOf(x.mediaMime, x.mediaUrl),
});

export const mapComment = (x: RawComment): Comment => ({
    id: x.id,
    number: x.handle || x.displayName || '',
    body: x.body,
    created_at: stamp(x.createdAt),
});

export const mapReport = (x: RawReport): ModerationReport => ({
    id: x.id,
    targetType: x.targetType,
    targetId: x.targetId,
    reason: x.reason,
    details: x.details || '',
    status: x.status,
    createdAt: stamp(x.createdAt),
    snapshot: x.snapshot || {},
});

/** A classified is posted as one text box: the first line is the title, the rest the description. */
export function splitListing(body: string): { title: string; description: string } {
    const lines = String(body).split('\n');
    return { title: lines[0].slice(0, 80), description: lines.slice(1).join('\n') };
}
