import { useEffect, useState } from 'react';
import { ArrowDownLeft, ArrowUpRight, Delete, Mail as MailIcon, MessageCircle, Phone, Plus, Send, Star, Trash2 } from 'lucide-react';
import { api, isPreview } from './api';
import { ImagePicker, PhotoImage } from './Images';
import { asList } from './types';
import type { CallHistory, ChatMessage, Conversation, MailItem } from './types';
import { dateLabel, Empty, Row } from './components';
import { previewText } from './chatTokens';
import { LoadState, useLoad, usePhone } from './PhoneContext';

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
export function ContactsScreen() {
  const { data, updateData, navigate, run, busy } = usePhone();
  const [search, setSearch] = useState('');
  const [editing, setEditing] = useState(false);
  const [contactId, setContactId] = useState<number>();
  const [photo, setPhoto] = useState('');
  const [name, setName] = useState(''); const [number, setNumber] = useState('');
  return <><div className="search-row"><input aria-label="Search contacts" placeholder="Find your people" value={search} onChange={e => setSearch(e.target.value)} /><button className="round-button" aria-label="Add contact" onClick={() => { setContactId(undefined); setName(''); setNumber(''); setPhoto(''); setEditing(!editing); }}><Plus size={20} /></button></div>
    {editing && <form className="panel form" onSubmit={e => { e.preventDefault(); run(async () => { updateData(await api('contactSave', { id: contactId, name, number, photo, favorite: data.contacts.find(c => contactId ? c.id === contactId : c.number === number)?.favorite })); setEditing(false); setContactId(undefined); setName(''); setNumber(''); }); }}><label>Name<input required maxLength={60} value={name} onChange={e => setName(e.target.value)} /></label><label>Number<input required inputMode="tel" pattern="[0-9]{7,16}" maxLength={16} value={number} onChange={e => setNumber(e.target.value)} /></label><ImagePicker label="Contact photo" value={photo} onChange={setPhoto} photos={data.photos} galleryOnly={!isPreview} /><button className="primary" disabled={busy}>Save contact</button></form>}
    <p className="section-label">YOUR CIRCLE / {data.contacts.length.toString().padStart(2, '0')}</p>
    {data.contacts.filter(c => `${c.name} ${c.number}`.toLowerCase().includes(search.toLowerCase())).sort((a, b) => Number(!!b.favorite) - Number(!!a.favorite) || a.name.localeCompare(b.name)).map(contact => <div key={contact.number} className="contact-card"><Row title={contact.name} detail={contact.number} icon={<PhotoImage src={contact.photo} className="contact-photo" alt={contact.name} />} /><div className="contact-actions"><button aria-label={contact.favorite ? `Remove ${contact.name} from favourites` : `Add ${contact.name} to favourites`} aria-pressed={!!contact.favorite} disabled={busy} onClick={() => run(async () => updateData(await api('contactSave', { ...contact, favorite: !contact.favorite })))}><Star size={16} fill={contact.favorite ? 'currentColor' : 'none'} /></button><button aria-label={`Call ${contact.name}`} onClick={() => navigate('phone', contact.number)}><Phone size={16} />Call</button><button aria-label={`Message ${contact.name}`} onClick={() => navigate('messages', contact.number)}><MessageCircle size={16} />Message</button><button aria-label={`Edit ${contact.name}`} onClick={() => { setContactId(contact.id); setName(contact.name); setNumber(contact.number); setPhoto(contact.photo || ''); setEditing(true); }}>Edit</button><button aria-label={`Delete ${contact.name}`} disabled={busy} onClick={() => run(async () => updateData(await api('contactSave', { ...contact, remove: true })))}><Trash2 size={16} /></button></div></div>)}
    {!data.contacts.length && <Empty title="Make a connection" detail="Add a number to start building your circle." />}
  </>;
}
export function MessagesScreen({ target }: { target: string }) {
  const { data, device, run, busy, revision } = usePhone();
  const inbox = useLoad(() => api('conversations', {}), [revision]);
  const [active, setActive] = useState<Conversation>();
  const [recipient, setRecipient] = useState(target); const [composing, setComposing] = useState(!!target);
  const [body, setBody] = useState(''); const [messages, setMessages] = useState<ChatMessage[]>([]);
  const name = (number?: string | null) => data.contacts.find(c => c.number === number)?.name || number || 'Conversation';
  const peerOf = (c: Conversation) => c.peerPhoneNumber || c.members || '';
  const titleOf = (c: Conversation) => c.kind === 'group' ? c.name || 'Group' : c.displayLabel || name(peerOf(c));
  const open = async (conversation: Conversation) => {
    setActive(conversation); setComposing(true); setRecipient(peerOf(conversation));
    const rows = await api('conversation', { id: conversation.id }); setMessages(rows.slice().reverse());
    const newest = rows[0]?.id; await api('markConversationRead', { id: conversation.id, messageId: newest });
  };
  useEffect(() => { if (!target) return; let live = true; run(async () => { const conversation = await api('startChat', { number: target }); if (live) await open(conversation); }); return () => { live = false; }; }, [target]);
  return <><LoadState {...inbox} retry={inbox.refresh} />
    {!composing ? <><button className="primary compose-button" onClick={() => { setComposing(true); setActive(undefined); setRecipient(''); setMessages([]); }}><Plus size={18} />New message</button>{asList<Conversation>(inbox.value).map(conversation => <Row key={conversation.id} title={titleOf(conversation)} detail={`${previewText(conversation.lastMessagePreview ?? conversation.last_body) || 'No messages yet'}${conversation.unreadCount ? ` · ${conversation.unreadCount} unread` : ''}`} icon={<PhotoImage src={data.contacts.find(c => c.number === peerOf(conversation))?.photo} className="contact-photo" alt={titleOf(conversation)} />} onClick={() => run(() => open(conversation))} />)}{!asList(inbox.value).length && !inbox.loading && <Empty title="Start a conversation" detail="A simple hello goes a long way." />}</>
      : <><button className="text-button" onClick={() => { setComposing(false); setActive(undefined); setRecipient(''); setMessages([]); inbox.refresh(); }}>← All messages</button><form className="message-form" onSubmit={e => { e.preventDefault(); run(async () => { const conversation = active || await api('startChat', { number: recipient }); const sent = await api('sendChatMessage', { conversationId: conversation.id, body: body.trim() }); setActive(conversation); setMessages(current => [...current, sent]); setBody(''); inbox.refresh(); }); }}><label className="recipient-field">To<input aria-label="Recipient number" required disabled={!!active} inputMode="tel" pattern="[0-9]{7,16}" maxLength={16} placeholder="Phone number" list="contacts" value={recipient} onChange={e => setRecipient(e.target.value.replace(/\D/g, ''))} /><datalist id="contacts">{data.contacts.map(c => <option key={c.number} value={c.number}>{c.name}</option>)}</datalist></label><div className="conversation">{messages.map(message => <div key={message.id} className={`bubble ${(message.isMine ?? message.sender_number === device.number) ? 'sent' : ''}`}><p>{previewText(message.body)}</p><small>{dateLabel(message.createdAt || message.created_at)} · {(message.isMine ?? message.sender_number === device.number) ? 'You' : name(message.senderNumber || message.sender_number)}</small><button type="button" className="text-button danger" aria-label="Delete message for me" disabled={busy} onClick={() => run(async () => { await api('deleteChatMessage', { messageId: message.id }); setMessages(current => current.filter(item => item.id !== message.id)); })}><Trash2 size={13} /></button></div>)}</div><div className="composer"><textarea aria-label="Message" required maxLength={1000} placeholder="Say something…" value={body} onChange={e => setBody(e.target.value)} /><button className="round-button red" aria-label="Send message" disabled={busy || !body.trim()}><Send size={18} /></button></div></form></>}
    {active && messages.length >= 50 && <button className="text-button" disabled={busy} onClick={() => run(async () => { const rows = await api('conversation', { id: active.id, before: Math.min(...messages.map(m => m.id)) }); setMessages(current => [...rows.slice().reverse(), ...current]); })}>Load older messages</button>}
  </>;
}
export function MailScreen({ target }: { target: string }) {
  const { data, run, busy, revision, notify } = usePhone();
  const [box, setBox] = useState<'inbox' | 'sent'>('inbox');
  const list = useLoad(() => api('mailList', { box }), [box, revision]);
  const [open, setOpen] = useState<MailItem>();
  const [composing, setComposing] = useState(!!target);
  const [to, setTo] = useState(target); const [subject, setSubject] = useState(''); const [body, setBody] = useState('');
  const name = (number: string) => data.contacts.find(c => c.number === number)?.name || number;
  const send = () => run(async () => { await api('mailSend', { to, subject, body }); setComposing(false); setTo(''); setSubject(''); setBody(''); notify('Mail sent'); list.refresh(); });
  const read = (item: MailItem) => { setOpen(item); if (item.unread) void api('mailRead', { id: item.id }).then(list.refresh).catch(() => undefined); };
  if (composing) return <form className="form" onSubmit={e => { e.preventDefault(); send(); }}>
    <button type="button" className="text-button" onClick={() => setComposing(false)}>← Back</button>
    <label>To<input required inputMode="tel" pattern="[0-9]{7,16}" maxLength={16} placeholder="Phone number" list="mail-contacts" value={to} onChange={e => setTo(e.target.value.replace(/\D/g, ''))} /><datalist id="mail-contacts">{data.contacts.map(c => <option key={c.number} value={c.number}>{c.name}</option>)}</datalist></label>
    <label>Subject<input required maxLength={120} value={subject} onChange={e => setSubject(e.target.value)} /></label>
    <textarea className="note-editor" aria-label="Mail body" required maxLength={4000} placeholder="Write something worth reading…" value={body} onChange={e => setBody(e.target.value)} />
    <button className="primary" disabled={busy}><Send size={17} />Send mail</button>
  </form>;
  if (open) return <article className="mail-read">
    <button className="text-button" onClick={() => setOpen(undefined)}>← {box === 'inbox' ? 'Inbox' : 'Sent'}</button>
    <h3>{open.subject}</h3><p className="muted">{box === 'inbox' ? 'From' : 'To'} {name(open.peer)} · {dateLabel(open.created_at)}</p>
    <p className="mail-body">{open.body}</p>
    <button className="primary" onClick={() => { setTo(open.peer); setSubject(/^re:/i.test(open.subject) ? open.subject : `Re: ${open.subject}`.slice(0, 120)); setBody(''); setOpen(undefined); setComposing(true); }}>Reply</button>
    <button className="text-button danger" disabled={busy} onClick={() => run(async () => { await api('mailDelete', { id: open.id }); setOpen(undefined); list.refresh(); })}><Trash2 size={15} />Delete</button>
  </article>;
  const items = asList<MailItem>(list.value);
  return <><div className="segments" role="group" aria-label="Mailbox">{(['inbox', 'sent'] as const).map(value => <button type="button" key={value} className={box === value ? 'selected' : ''} aria-pressed={box === value} onClick={() => setBox(value)}>{value === 'inbox' ? 'Inbox' : 'Sent'}</button>)}</div>
    <button className="primary compose-button" onClick={() => { setTo(''); setSubject(''); setBody(''); setComposing(true); }}><Plus size={18} />New mail</button>
    <LoadState {...list} retry={list.refresh} />
    {items.map(item => <Row key={item.id} title={item.subject} detail={`${box === 'inbox' ? 'From' : 'To'} ${name(item.peer)} · ${dateLabel(item.created_at)}`} icon={<MailIcon size={18} />} end={item.unread ? <i className="mail-dot" aria-label="Unread" /> : undefined} onClick={() => read(item)} />)}
    {!items.length && !list.loading && <Empty title={box === 'inbox' ? 'Nothing new' : 'Nothing sent'} detail={box === 'inbox' ? 'Longer messages land here.' : 'Mail you send will be kept here.'} />}
  </>;
}
