import { api } from '../api';
import { mergeConversations } from '../chatMessages';
import { previewText } from '../chatTokens';
import { usePhoneStore } from './storeContext';

/** The unfolded tablet keeps the conversation list beside the open chat. */
export function FoldInbox() {
  const { state, dispatch, refs, actions, view } = usePhoneStore();
  const { device, foldInbox, foldInboxMore, target, busy } = state;
  if (!device) return null;
  const older = () => actions.run(async () => {
    const last = foldInbox[foldInbox.length - 1]; const expected = device.id;
    const rows = await api('conversations', { before: last.sortId ?? last.lastMessageId ?? last.id, cursorId: last.id });
    if (refs.notificationDevice.current === expected) dispatch({ type: 'patch', patch: { foldInbox: mergeConversations(foldInbox, rows), foldInboxMore: rows.length === 50 } });
  });
  return <aside className="fold-message-list"><h3>Conversations</h3><button className="text-button" onClick={() => actions.navigate('messages')}>New message</button>{foldInbox.map(conversation => {
    const number = (conversation.members || '').split(',').find(value => value !== device.number) || conversation.members || '';
    return <button key={conversation.id} className={number === target ? 'selected' : ''} onClick={() => actions.navigate('messages', number)}><strong>{view.data.contacts.find(contact => contact.number === number)?.name || number}</strong><small>{previewText(conversation.lastMessagePreview || conversation.last_body) || 'No messages yet'}</small></button>;
  })}{foldInboxMore && <button disabled={busy} onClick={older}>Older conversations</button>}{!foldInbox.length && <p>Your conversations will appear here.</p>}</aside>;
}
