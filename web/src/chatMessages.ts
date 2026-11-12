import type { ChatMessage, Conversation } from './types';

export function mergeChatMessages(current: ChatMessage[], incoming: ChatMessage[]): ChatMessage[] {
  const messages = new Map(current.map(message => [message.id, message]));
  for (const message of incoming) messages.set(message.id, message);
  return [...messages.values()].sort((a, b) => a.id - b.id);
}

export function mergeConversations(current: Conversation[], incoming: Conversation[]): Conversation[] {
  const rows=new Map(current.map(row=>[row.id,row]));
  for(const row of incoming) rows.set(row.id,row);
  return [...rows.values()].sort((a,b)=>(b.sortId??b.lastMessageId??b.id)-(a.sortId??a.lastMessageId??a.id)||b.id-a.id);
}
