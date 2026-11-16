import { photoBody, videoBody } from '../../chatTokens';
import { items } from '../adapters/common';
import { mapCall, mapCallHistory, mapConversation, mapMessage } from '../adapters/messages';
import type { RawCall, RawCallHistory, RawConversation, RawMessage } from '../raw';
import { requestId } from '../env';
import type { HandlerSet } from '../routeTypes';
import { server } from '../transport';

/** A shared link plus its caption must each fit the server's message limit. */
const MAX_BODY = 1900;

export const messagingRoutes: HandlerSet<
    'history' | 'dial' | 'answer' | 'hangup' | 'videoSignal' | 'sendMessage' | 'messages' | 'conversations'
    | 'startChat' | 'conversation' | 'sendChatMessage' | 'shareToChat' | 'markConversationRead'
    | 'deleteChatMessage' | 'addMember' | 'createGroup' | 'leaveGroup' | 'blocked' | 'setBlocked'
> = {
    history: async () => items(await server<{ items?: RawCallHistory[] }>('calls:history', { limit: 50 })).map(mapCallHistory),
    dial: async p => mapCall(await server<RawCall>('calls:start', { to: p.number })),
    answer: async p => mapCall(await server<RawCall>('calls:accept', { id: p.id })),
    hangup: async p => { await server(p.reject ? 'calls:reject' : 'calls:hangup', { id: p.id }); return true; },
    videoSignal: async p => {
        await server('calls:signal', { id: p.id, epoch: p.epoch, kind: p.kind, sdp: p.sdp, candidate: p.candidate });
        return true;
    },
    sendMessage: async (p, { id }) => {
        await server('messages:send', { to: p.recipient, body: p.body, clientRequestId: id });
        return { sent: true };
    },
    messages: async () => { throw new Error('Conversation history needs the peer-number repository upgrade'); },
    conversations: async p => items(await server<{ items?: RawConversation[] } | RawConversation[]>('messages:getConversations', {
        limit: 50, cursor: p.before, cursorId: p.cursorId,
    })).map(mapConversation),
    startChat: async p => mapConversation(await server<RawConversation>('messages:startDirect', { to: p.number })),
    conversation: async p => items(await server<{ items?: RawMessage[] } | RawMessage[]>('messages:getPage', {
        conversationId: p.id, limit: 50, cursor: p.before,
    })).map(mapMessage),
    sendChatMessage: async (p, { id }) => mapMessage(await server<RawMessage>('messages:send', {
        conversationId: p.conversationId, body: p.body, mediaId: p.mediaId, clientRequestId: id,
    })),
    shareToChat: async (p, { id }) => {
        // The clip belongs to whoever posted it, so it travels as a link the receiver's phone plays, plus the caption as text.
        const tooLong = (p.mediaUrl || '').length > MAX_BODY;
        const linked = !!p.mediaUrl && !tooLong;
        if (linked) {
            const body = (p.mediaKind === 'video' ? videoBody : photoBody)(p.mediaUrl!);
            await server('messages:send', { conversationId: p.conversationId, body, clientRequestId: id });
        }
        const text = [p.body, tooLong ? p.mediaUrl : ''].filter(Boolean).join('\n').slice(0, MAX_BODY);
        if (text || !p.mediaUrl) {
            await server('messages:send', {
                conversationId: p.conversationId,
                body: text || 'A moment from Flash',
                clientRequestId: linked ? requestId() : id,
            });
        }
        return true;
    },
    markConversationRead: async p => { await server('messages:markRead', { conversationId: p.id, messageId: p.messageId }); return true; },
    deleteChatMessage: async p => { await server('messages:deleteForSelf', { messageId: p.messageId }); return true; },
    addMember: async p => { await server('messages:addMember', { conversationId: p.id, number: p.number }); return true; },
    createGroup: p => server<{ id: number }>('messages:createGroup', { name: p.name, numbers: p.numbers }),
    leaveGroup: async p => { await server('messages:leaveGroup', { conversationId: p.id }); return true; },
    blocked: async () => items(await server<{ items?: { number: string }[] }>('blocks:list')).map(x => String(x.number)),
    setBlocked: async p => { await server('blocks:set', { number: p.number, blocked: p.blocked }); return true; },
};
