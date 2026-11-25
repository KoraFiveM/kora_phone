import { ArrowDownLeft,ArrowUpRight,Delete,ImagePlus,Phone,Plus,Send,Trash2,X } from 'lucide-react';
import { useEffect,useState } from 'react';
import { api } from '../../api';
import { mergeChatMessages,mergeConversations } from '../../chatMessages';
import { previewText } from '../../chatTokens';
import { dateLabel,Empty,Row } from '../../components';
import { LoadState,useLoad,usePhone } from '../../core/PhoneContext';
import { ImagePicker,PhotoImage } from '../../Images';
import type { CallHistory,ChatMessage,Conversation } from '../../types';
import { asList } from '../../types';

export function PhoneScreen({ target }: { target: string }) {
  const { run, busy, setCall, device, data } = usePhone();
  const [number, setNumber] = useState(target);
  const [tab, setTab] = useState('keypad');
  const history = useLoad(() => api('history', {}), []);
  return <><div className="segments"><button className={tab === 'keypad' ? 'selected' : ''} onClick={() => setTab('keypad')}>Keypad</button><button className={tab === 'recent' ? 'selected' : ''} onClick={() => { setTab('recent'); history.refresh(); }}>Recent</button></div>
    {tab === 'keypad' ? <div className="dialer"><input className="dial-number" aria-label="Phone number" inputMode="tel" value={number} maxLength={16} placeholder="Enter number" onChange={e => setNumber(e.target.value.replace(/\D/g, ''))} /><p className="muted">{data.contacts.find(c => c.number === number)?.name || 'A little closer. One call away.'}</p><div className="keypad">{'123456789*0#'.split('').map((digit, i) => <button key={digit} onClick={() => setNumber(n => (n + digit).slice(0, 16))}><span>{digit}</span><small>{['', 'ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ', '', '+', ''][i]}</small></button>)}</div><div className="dial-actions"><span /><button className="call-button" aria-label="Call number" disabled={busy || !/^\d{7,16}$/.test(number)} onClick={() => run(async () => setCall(await api('dial', { number })))}><Phone size={25} /></button><button className="icon-button" aria-label="Delete last digit" onClick={() => setNumber(n => n.slice(0, -1))}><Delete size={23} /></button></div></div>
      : <><LoadState {...history} retry={history.refresh} />{asList<CallHistory>(history.value).map(call => { const incoming = call.recipient === device.number; const peer = incoming ? call.caller : call.recipient; return <Row key={call.id} title={data.contacts.find(c => c.number === peer)?.name || peer} detail={`${call.status} · ${dateLabel(call.created_at)}`} icon={incoming ? <ArrowDownLeft size={19} /> : <ArrowUpRight size={19} />} onClick={() => { setNumber(peer); setTab('keypad'); }} />; })}{!history.loading && !asList(history.value).length && <Empty title="Your first hello" detail="Your recent calls will appear here." />}</>}
  </>;
}
export function MessagesScreen({ target }: { target: string }) {
  const { data, device, run, busy, revision } = usePhone();
  const inbox = useLoad(() => api('conversations', {}), [revision]);
  const [moreConversations,setMoreConversations]=useState(true);
  useEffect(()=>{setMoreConversations(true);},[revision]);
  const [active, setActive] = useState<Conversation>();
  const [recipient, setRecipient] = useState(target);
  const [composing, setComposing] = useState(!!target);
  const [body, setBody] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [attachment, setAttachment] = useState<string>();
  const [picking, setPicking] = useState(false);
  const [chatError, setChatError] = useState('');
  const photo = data.photos.find(item => item.id === attachment);
  const name = (number?: string | null) => data.contacts.find(c => c.number === number)?.name || number || 'Conversation';
  const peerOf = (c: Conversation) => c.peerPhoneNumber || c.members || '';
  const titleOf = (c: Conversation) => c.title || (c.kind === 'group' ? c.name || 'Group' : c.displayLabel || name(peerOf(c)));
  const archived = !!active && peerOf(active).startsWith('@group:');
  const open = (conversation: Conversation) => {
    setMessages([]); setActive(conversation); setComposing(true); setRecipient(peerOf(conversation));
    setAttachment(undefined); setPicking(false); setChatError('');
  };
  useEffect(() => {
    if (!active) return;
    let live = true;
    void api('conversation', { id: active.id }).then(rows => {
      if (!live) return;
      setMessages(current => mergeChatMessages(current, rows)); setChatError('');
      void api('markConversationRead', { id: active.id, messageId: rows[0]?.id }).catch(() => undefined);
    }).catch(error => { if (live) setChatError(error instanceof Error ? error.message : 'Could not load messages'); });
    return () => { live = false; };
  }, [active?.id, revision]);
  useEffect(() => {
    if (!target) return;
    let live = true;
    void run(async () => { const conversation = await api('startChat', { number: target }); if (live) open({ ...conversation, peerPhoneNumber: target }); });
    return () => { live = false; };
  }, [target]);
  const reset = (compose: boolean) => { setMoreConversations(true); setComposing(compose); setActive(undefined); setRecipient(''); setMessages([]); setBody(''); setAttachment(undefined); setPicking(false); setChatError(''); };
  const send = () => run(async () => {
    const conversation = active || await api('startChat', { number: recipient });
    const sent = await api('sendChatMessage', { conversationId: conversation.id, body: body.trim(), ...(photo ? { mediaId: Number(photo.id) } : {}) });
    setActive({ ...conversation, peerPhoneNumber: recipient }); setMessages(current => mergeChatMessages(current, [sent]));
    setBody(''); setAttachment(undefined); setPicking(false); inbox.refresh();
  });
  return <><LoadState {...inbox} retry={inbox.refresh} />
    {!composing ? <><button className="primary compose-button" onClick={() => reset(true)}><Plus size={18} />New message</button>
      {asList<Conversation>(inbox.value).map(conversation => <Row key={conversation.id} title={titleOf(conversation)} detail={`${previewText(conversation.lastMessagePreview ?? conversation.last_body) || (conversation.last_kind ? 'Photo' : 'No messages yet')}${conversation.unreadCount ? ` · ${conversation.unreadCount} unread` : ''}`} icon={<PhotoImage src={data.contacts.find(c => c.number === peerOf(conversation))?.photo} className="contact-photo" alt={titleOf(conversation)} />} onClick={() => open(conversation)} />)}
      {moreConversations && (inbox.value?.length||0)>=50 && <button className="text-button" disabled={busy} onClick={()=>run(async()=>{
        const last=inbox.value![inbox.value!.length-1];
        const rows=await api('conversations',{before:last.sortId??last.lastMessageId??last.id,cursorId:last.id});
        inbox.setValue(current=>mergeConversations(current||[],rows));setMoreConversations(rows.length===50);
      })}>Older conversations</button>}
      {!asList(inbox.value).length && !inbox.loading && <Empty title="Start a conversation" detail="A simple hello goes a long way." />}</>
      : <><button className="text-button" onClick={() => { reset(false); inbox.refresh(); }}>← All messages</button>
        {chatError && <p role="alert">{chatError}</p>}
        <form className="message-form" onSubmit={e => { e.preventDefault(); void send(); }}>
          <label className="recipient-field">To<input aria-label="Recipient number" required disabled={!!active} inputMode="tel" pattern="[0-9]{7,16}" maxLength={16} placeholder="Phone number" list="contacts" value={recipient} onChange={e => setRecipient(e.target.value.replace(/\D/g, ''))} /><datalist id="contacts">{data.contacts.map(c => <option key={c.number} value={c.number}>{c.name}</option>)}</datalist></label>
          <div className="conversation" aria-live="polite">{messages.map(message => <div key={message.id} className={`bubble ${(message.isMine ?? message.sender_number === device.number) ? 'sent' : ''}`}>
            {message.media_url && message.media_kind === 'photo' && <PhotoImage className="chat-photo" src={message.media_url} alt="Message photo" />}
            {message.body && <p>{previewText(message.body)}</p>}
            <small>{dateLabel(message.createdAt || message.created_at)} · {(message.isMine ?? message.sender_number === device.number) ? 'You' : name(message.senderNumber || message.sender_number)}</small>
            <button type="button" className="text-button danger" aria-label="Delete message for me" disabled={busy} onClick={() => run(async () => { await api('deleteChatMessage', { messageId: message.id }); setMessages(current => current.filter(item => item.id !== message.id)); })}><Trash2 size={13} /></button>
          </div>)}</div>
          {archived ? <p className="muted">Archived group · read only</p> : <>
            {picking && <ImagePicker label="Message attachment" value={photo?.url || ''} photos={data.photos} galleryOnly onChange={url => setAttachment(data.photos.find(item => item.url === url)?.id)} />}
            {picking && !data.photos.length && <p className="muted">Take a photo in Camera before attaching it here.</p>}
            {photo && <div className="chat-attachment"><PhotoImage src={photo.url} alt="Selected attachment" /><button type="button" className="icon-button" aria-label="Remove attachment" onClick={() => setAttachment(undefined)}><X size={17} /></button></div>}
            <div className="composer"><button type="button" className="icon-button" aria-label="Attach gallery photo" aria-pressed={picking} onClick={() => setPicking(value => !value)}><ImagePlus size={19} /></button>
              <textarea aria-label="Message" required={!photo} maxLength={1000} placeholder="Say something…" value={body} onChange={e => setBody(e.target.value)} />
              <button className="round-button red" aria-label="Send message" disabled={busy || (!body.trim() && !photo)}><Send size={18} /></button>
            </div></>}
        </form></>}
    {active && messages.length >= 50 && <button className="text-button" disabled={busy} onClick={() => run(async () => { const rows = await api('conversation', { id: active.id, before: Math.min(...messages.map(m => m.id)) }); setMessages(current => mergeChatMessages(current, rows)); })}>Load older messages</button>}
  </>;
}
