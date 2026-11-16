import type { Call, CallHistory, ChatMessage, Conversation } from '../../types';
import type { RawCall, RawCallHistory, RawConversation, RawMessage } from '../raw';
import { kindOf, stamp } from './common';

/** The server names message fields differently from the chat screens: map them once, here. */
export const mapMessage = (m: RawMessage): ChatMessage => ({
    ...(m as unknown as ChatMessage),
    sender_number: String(m.senderNumber || ''),
    created_at: stamp(m.createdAt),
    media_url: m.mediaUrl || undefined,
    media_kind: kindOf(m.mediaMime, m.mediaUrl),
});

export const mapConversation = (c: RawConversation): Conversation => ({
    ...(c as unknown as Conversation),
    kind: c.type === 'group' ? 'group' : 'direct',
    name: c.title ?? null,
    members: String(c.peerPhoneNumber || ''),
    last_body: c.lastMessagePreview || '',
    last_kind: kindOf(c.lastMediaMime, c.lastMediaMime) ?? null,
    last_number: null,
    last_at: c.lastMessageAt ? stamp(c.lastMessageAt) : null,
});

export const mapCall = (v: RawCall): Call => ({
    id: String(v.id),
    status: (v.status === 'rejected' ? 'declined' : v.status) as Call['status'],
    number: String(v.remoteNumber || ''),
    direction: v.direction || 'outgoing',
    deviceId: 'kora_phone',
});

export const mapCallHistory = (x: RawCallHistory): CallHistory => ({
    id: x.id,
    caller: x.callerNumber,
    recipient: x.calleeNumber,
    status: x.status,
    created_at: stamp(x.startedAt),
});
