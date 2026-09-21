import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { ArrowLeft, ArrowUpRight, AudioLines, Ban, Camera, ChevronRight, Image as ImageIcon, LogOut, MapPin, MessageCircle, Plus, RefreshCw, Search, Send, UserPlus, Users, Video } from 'lucide-react';
import { useClipRecorder } from './useClipRecorder';
import { api } from './api';
import { asList } from './types';
import type { ChatMessage, Conversation } from './types';
import { Empty } from './components';
import { PhotoImage, imageUrl } from './Images';
import { locationBody, parseToken, photoBody, previewText } from './chatTokens';
import { LoadState, useLoad, usePhone } from './PhoneContext';
import { SocialAvatar, SocialHeader, SocialSheet, messageTime } from './SocialUI';
// A photo from someone who is not in your contacts stays hidden until tapped, so a stranger cannot make your phone fetch their link.
function ChatPhoto({ url, trusted, video = false }: { url: string; trusted: boolean; video?: boolean }) {
  const [shown, setShown] = useState(trusted);
  if (shown) return video && imageUrl(url) ? <video src={url} controls playsInline preload="metadata" /> : <PhotoImage src={url} alt="Shared photo" />;
  return <button type="button" className="pulse-loc" onClick={() => setShown(true)}>{video ? <Video size={18} /> : <ImageIcon size={18} />}<span><strong>{video ? 'Clip' : 'Photo'}</strong><small>From someone not in your contacts. Tap to load.</small></span></button>;
}
function peerNumber(conversation: Conversation) { return (conversation.members || '').split(',')[0] || ''; }
function ConversationThread({ conversation, onBack }: { conversation: Conversation; onBack: () => void }) {
  const { device, data, run, busy, notify, revision, updateData } = usePhone();
  const thread = useLoad(() => api('conversation', { id: conversation.id }), [conversation.id, revision]);
  const [older, setOlder] = useState<ChatMessage[]>([]);
  const messages = [...asList<ChatMessage>(thread.value), ...older].filter((m, i, all) => all.findIndex(x => x.id === m.id) === i).sort((a, b) => a.id - b.id);
  const [body, setBody] = useState('');
  const [leaving, setLeaving] = useState(false);
  const [progress, setProgress] = useState(0);
  const [adding, setAdding] = useState<string | null>(null);
  const [blocking, setBlocking] = useState(false);
  const [saving, setSaving] = useState<string | null>(null);
  const [recordPanel, setRecordPanel] = useState(false);
  const [sheet, setSheet] = useState<'' | 'attach' | 'photos'>('');
  const scroll = useRef<HTMLDivElement>(null);
  const stickToBottom = useRef(true);
  useLayoutEffect(() => {
    if (scroll.current && stickToBottom.current) scroll.current.scrollTop = scroll.current.scrollHeight;
  }, [messages.length, messages[messages.length - 1]?.id]);
  const { recording, clip, discardClip, stopRecording, start } = useClipRecorder(device.flash ? device.flash.maxSeconds : 15);
  const startRecording = () => run(start);
  const sendText = () => run(async () => { await api('sendChatMessage', { conversationId: conversation.id, body }); setBody(''); stickToBottom.current = true; thread.refresh(); });
  const sendClip = () => run(async () => {
    if (!clip) return;
    if (device.flash && device.flash.maxBytes && clip.blob.size > device.flash.maxBytes) throw new Error('That clip is too big. Try a shorter one.');
    setProgress(0);
    try {
      const media = await api('uploadMedia', { blob: clip.blob, onProgress: setProgress });
      await api('sendChatMessage', { conversationId: conversation.id, body: '', mediaKind: 'video', media: media.url, mediaId: media.id });
      discardClip(); setRecordPanel(false); stickToBottom.current = true; thread.refresh();
    } finally { setProgress(0); }
  });
  // Opening a chat (or a new message arriving while it's open) marks it read, so unread counts clear.
  const newest = messages[messages.length - 1];
  useEffect(() => { if (newest) void api('markConversationRead', { id: conversation.id, messageId: newest.id }).catch(() => undefined); }, [newest?.id]);
  const sendToken = (text: string) => run(async () => { await api('sendChatMessage', { conversationId: conversation.id, body: text }); setSheet(''); stickToBottom.current = true; thread.refresh(); });
  const shareLocation = () => run(async () => {
    const place = await api('myLocation', {});
    await api('sendChatMessage', { conversationId: conversation.id, body: locationBody(place) });
    setSheet(''); stickToBottom.current = true; thread.refresh();
  });
  const peerLabel = conversation.kind === 'group' ? conversation.name || 'Group' : (data.contacts.find(c => c.number === peerNumber(conversation))?.name || peerNumber(conversation));
  const senderLabel = (number: string) => data.contacts.find(c => c.number === number)?.name || number;
  const contact = data.contacts.find(c => c.number === peerNumber(conversation));
  return <div className="pulse-thread">
    <header className="pulse-thread-header">
      <button className="icon-button" aria-label="Back to chats" onClick={onBack}><ArrowLeft size={20} /></button>
      <SocialAvatar name={peerLabel} photo={contact?.photo} group={conversation.kind === 'group'} />
      <div><h2>{peerLabel}</h2><small>{conversation.kind === 'group' ? 'Group conversation' : peerNumber(conversation)}</small></div>
      {conversation.kind === 'group' ? <span className="pulse-header-actions"><button className="icon-button" aria-label="Add someone" onClick={() => setAdding('')}><UserPlus size={18} /></button><button className="icon-button" aria-label="Leave group" onClick={() => setLeaving(true)}><LogOut size={18} /></button></span> : <span className="pulse-header-actions">{!contact && <button className="icon-button" aria-label="Save to contacts" onClick={() => setSaving('')}><UserPlus size={17} /></button>}<button className="icon-button" aria-label="Block this number" onClick={() => setBlocking(true)}><Ban size={17} /></button><button className="icon-button" aria-label="Refresh conversation" disabled={busy} onClick={thread.refresh}><RefreshCw size={17} /></button></span>}
    </header>
    <div className="pulse-message-list" ref={scroll} onScroll={() => { const el = scroll.current!; stickToBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 90; }}>
      <div className="conversation-intro"><SocialAvatar name={peerLabel} photo={contact?.photo} group={conversation.kind === 'group'} /><strong>{peerLabel}</strong><span>A little closer, one message at a time.</span></div>
      <LoadState {...thread} retry={thread.refresh} />
      {messages.length >= 50 && <button className="text-button centered" disabled={busy} onClick={() => run(async () => {
        const rows = await api('conversation', { id: conversation.id, before: Math.min(...messages.map(m => m.id)) });
        stickToBottom.current = false; setOlder(previous => [...previous, ...asList<ChatMessage>(rows)]);
      })}>Earlier messages</button>}
      {messages.map((message,index) => {
        const date = new Date(message.created_at);
        const day = Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString('en-GB', { day: 'numeric', month: 'long' });
        const token = parseToken(message.body);
        const newDay = index === 0 || new Date(messages[index - 1].created_at).toDateString() !== date.toDateString();
        return <div key={message.id} className="pulse-message-group">
          {newDay && day && <div className="pulse-day">{day}</div>}
          <div className={'pulse-bubble ' + (message.sender_number === device.number ? 'sent' : '')}>
            {conversation.kind === 'group' && message.sender_number !== device.number && <strong className="pulse-sender">{senderLabel(message.sender_number)}</strong>}
            {message.media_kind === 'video' && message.media_url && <video src={message.media_url} controls playsInline preload="metadata" />}
            {message.media_kind === 'photo' && message.media_url && <PhotoImage src={message.media_url} alt="Shared photo" />}
            {message.shared_from_post && <span className="pulse-shared"><ArrowUpRight size={12} />Shared from Flash</span>}
            {token?.kind === 'location' && <button type="button" className="pulse-loc" onClick={() => run(async () => { await api('waypoint', { x: token.x, y: token.y }); notify('Waypoint set on your map'); })}><MapPin size={18} /><span><strong>{token.label || 'Shared location'}</strong><small>Set waypoint</small></span></button>}
            {(token?.kind === 'photo' || token?.kind === 'video') && <ChatPhoto url={token.url} video={token.kind === 'video'} trusted={message.sender_number === device.number || data.contacts.some(c => c.number === message.sender_number)} />}
            {!token && message.body && <p>{message.body}</p>}<time>{messageTime(message.created_at)}</time>
          </div>
        </div>;
      })}
      {!messages.length && !thread.loading && <p className="pulse-first-message">Say hello. The rest will follow.</p>}
    </div>
    <form className="pulse-composer" onSubmit={e => { e.preventDefault(); if (body.trim()) sendText(); }}>
      <button className="icon-button" type="button" aria-label="Attach something" onClick={() => setSheet('attach')}><Plus size={22} /></button>
      <textarea aria-label="Message" rows={1} maxLength={2000} placeholder="Say something…" value={body} onChange={e => setBody(e.target.value)} />
      <button className="pulse-send" aria-label="Send message" disabled={busy || !body.trim()}><Send size={18} /></button>
    </form>
    {leaving && <SocialSheet title="Leave this group?" detail="Someone in the group will need to add you again." onClose={() => setLeaving(false)}><button className="primary" disabled={busy} onClick={() => run(async () => { await api('leaveGroup', { id: conversation.id }); notify('Left group'); onBack(); })}>Leave group</button></SocialSheet>}
    {sheet === 'attach' && <SocialSheet title="Add to your message." detail="Share where you are, or a photo." onClose={() => setSheet('')}>
      <div className="pulse-attach">
        <button type="button" disabled={busy} onClick={shareLocation}><MapPin size={20} /><span><strong>Share my location</strong><small>They can set a waypoint to you.</small></span></button>
        <button type="button" disabled={busy} onClick={() => setSheet('photos')}><ImageIcon size={20} /><span><strong>Send a photo</strong><small>Pick one from your gallery.</small></span></button>
        {device.flash && <button type="button" disabled={busy} onClick={() => { setSheet(''); setRecordPanel(true); }}><Video size={20} /><span><strong>Record a clip</strong><small>Up to {device.flash.maxSeconds} seconds.</small></span></button>}
      </div>
    </SocialSheet>}
    {sheet === 'photos' && <SocialSheet title="Choose a photo." detail="Only photos with an https link can be shared." onClose={() => setSheet('')}>
      {data.photos.some(photo => imageUrl(photo.url) && photoBody(photo.url).length <= 2000) ? <div className="image-picker-gallery">{data.photos.filter(photo => imageUrl(photo.url) && photoBody(photo.url).length <= 2000).map(photo => <button type="button" key={photo.id} aria-label={`Send gallery photo ${photo.id}`} disabled={busy} onClick={() => sendToken(photoBody(photo.url))}><PhotoImage src={photo.url} alt="Gallery photo" /></button>)}</div> : <p className="muted">No shareable photos yet. Take one with the Camera first.</p>}
    </SocialSheet>}
    {saving !== null && <SocialSheet title="Save this number." detail={peerNumber(conversation)} onClose={() => setSaving(null)}>
      <form className="form" onSubmit={e => { e.preventDefault(); run(async () => { updateData(await api('contactSave', { name: saving.trim(), number: peerNumber(conversation) })); setSaving(null); notify('Saved to contacts'); }); }}>
        <label>Name<input required autoFocus maxLength={60} value={saving} onChange={e => setSaving(e.target.value)} /></label>
        <button className="primary" disabled={busy || !saving.trim()}>Save contact</button>
      </form>
    </SocialSheet>}
    {blocking && <SocialSheet title={`Block ${peerLabel}?`} detail="They won't be able to call, message or mail you, and you won't be able to reach them. You can undo this in Settings." onClose={() => setBlocking(false)}><button className="primary" disabled={busy} onClick={() => run(async () => { await api('setBlocked', { number: peerNumber(conversation), blocked: true }); setBlocking(false); notify('Blocked. You can undo it in Settings.'); onBack(); })}>Block number</button></SocialSheet>}
    {adding !== null && <SocialSheet title="Add someone." detail="Anyone in the group can add people." onClose={() => setAdding(null)}>
      <form className="form" onSubmit={e => { e.preventDefault(); run(async () => { await api('addMember', { id: conversation.id, number: adding }); setAdding(null); notify('Added to the group'); }); }}>
        <label>Phone number<input required inputMode="tel" pattern="[0-9]{7,16}" maxLength={16} placeholder="555…" value={adding} onChange={e => setAdding(e.target.value.replace(/\D/g, ''))} /></label>
        <button className="primary" disabled={busy}>Add to group</button>
      </form>
    </SocialSheet>}
    {recordPanel && <SocialSheet title="A little face time." detail="Record a clip with your real webcam and microphone." onClose={() => { discardClip(); setRecordPanel(false); }}>
      <div className="social-record-stage">{clip ? <video src={clip.url} controls playsInline /> : <><Video size={48} strokeWidth={1} /><p>{recording ? 'Recording your clip…' : 'Make it personal.'}</p><small>Up to {device.flash ? device.flash.maxSeconds : 15} seconds</small></>}</div>
      {progress > 0 && progress < 1 && <div className="upload-progress" role="progressbar" aria-label="Uploading" aria-valuenow={Math.round(progress * 100)} aria-valuemin={0} aria-valuemax={100}><i style={{ width: `${Math.round(progress * 100)}%` }} /></div>}
      {clip ? <><button className="primary" disabled={busy} onClick={sendClip}><Send size={17} />Send clip</button><button className="text-button centered" onClick={discardClip}>Retake</button></> : <button className="primary" disabled={busy} onClick={recording ? stopRecording : startRecording}>{recording ? 'Stop recording' : 'Record webcam clip'}</button>}
    </SocialSheet>}
  </div>;
}

export function PulseScreen() {
  const { data, device, run, busy, revision } = usePhone();
  const list = useLoad(() => api('conversations', {}), [revision]);
  const [open, setOpen] = useState<Conversation>();
  const [mode, setMode] = useState<'' | 'chat' | 'group'>('');
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<'All' | 'People' | 'Groups'>('All');
  const [number, setNumber] = useState('');
  const [groupName, setGroupName] = useState('');
  const [groupNumbers, setGroupNumbers] = useState('');
  const startChat = (target = number) => run(async () => {
    const result = await api('startChat', { number: target });
    setMode(''); setNumber('');
    setOpen({ id: result.id, kind: 'direct', name: null, members: target, last_body: '', last_kind: null, last_number: null, last_at: null });
    list.refresh();
  });
  const createGroup = () => run(async () => {
    const numbers = groupNumbers.split(',').map(value => value.trim()).filter(Boolean);
    const result = await api('createGroup', { name: groupName, numbers });
    setMode(''); setGroupName(''); setGroupNumbers('');
    setOpen({ id: result.id, kind: 'group', name: groupName, members: numbers.join(','), last_body: '', last_kind: null, last_number: null, last_at: null });
    list.refresh();
  });
  if (open) return <ConversationThread key={open.id} conversation={open} onBack={() => { setOpen(undefined); list.refresh(); }} />;
  const label = (conversation: Conversation) => conversation.kind === 'group' ? conversation.name || 'Group' : (data.contacts.find(c => c.number === peerNumber(conversation))?.name || peerNumber(conversation));
  const chats = asList<Conversation>(list.value);
  const visible = chats.filter(c => (filter === 'All' || c.kind === (filter === 'Groups' ? 'group' : 'direct')) && (label(c) + ' ' + (c.members || '') + ' ' + (c.last_body ?? '')).toLowerCase().includes(search.toLowerCase()));
  return <div className="pulse-app">
    <SocialHeader name="Pulse" mark={<AudioLines size={23} />} actions={<button className="icon-button" aria-label="Refresh chats" disabled={busy} onClick={list.refresh}><RefreshCw size={17} /></button>} />
    <div className="pulse-inbox-scroll">
      <section className="pulse-intro"><span className="social-kicker">YOUR INNER CIRCLE</span><h2>Good company.</h2><p>Keep your people close.</p><div className="pulse-wave" aria-hidden="true">{[12,24,15,38,55,30,18,43,26,12].map((height,i) => <i key={i} style={{ height }} />)}</div></section>
      <div className="pulse-quick-actions"><button onClick={() => setMode('chat')}><MessageCircle size={19} /><span>New chat</span><Plus size={16} /></button><button onClick={() => setMode('group')}><Users size={19} /><span>New group</span><Plus size={16} /></button></div>
      <label className="social-search"><Search size={17} /><input aria-label="Search chats" placeholder="Find a conversation" value={search} onChange={e => setSearch(e.target.value)} /></label>
      {data.contacts.length > 0 && !search && <section className="pulse-people"><div className="social-section-title"><span>A QUICK HELLO</span><span>{data.contacts.length}</span></div><div className="pulse-contact-strip">{[...data.contacts].sort((a, b) => Number(!!b.favorite) - Number(!!a.favorite)).slice(0, 8).map(contact => <button key={contact.number} disabled={busy} onClick={() => startChat(contact.number)}><SocialAvatar name={contact.name} photo={contact.photo} /><span>{contact.name.split(' ')[0]}</span></button>)}</div></section>}
      <div className="social-filter" aria-label="Filter conversations">{(['All','People','Groups'] as const).map(value => <button key={value} aria-pressed={filter === value} onClick={() => setFilter(value)}>{value}{value === 'All' && <span>{chats.length}</span>}</button>)}</div>
      <LoadState {...list} retry={list.refresh} />
      <div className="pulse-chat-list">{visible.map(conversation => <button className="pulse-chat-row" key={conversation.id} onClick={() => setOpen(conversation)}>
        <SocialAvatar name={label(conversation)} photo={data.contacts.find(c => c.number === peerNumber(conversation))?.photo} group={conversation.kind === 'group'} />
        <span className="pulse-chat-copy"><span><strong>{label(conversation)}</strong><time>{messageTime(conversation.last_at)}</time>{!!conversation.unreadCount && <b className="pulse-unread" aria-label={`${conversation.unreadCount} unread`}>{conversation.unreadCount}</b>}</span><small>{conversation.last_kind === 'video' ? <><Video size={13} />Video message</> : conversation.last_kind === 'photo' ? <><Camera size={13} />Photo message</> : (conversation.last_number === device.number ? 'You: ' : '') + (previewText(conversation.last_body) || 'Start the conversation')}</small></span><ChevronRight size={14} />
      </button>)}</div>
      {!visible.length && !list.loading && <Empty title={search ? 'No conversations found' : filter === 'Groups' ? 'Better together.' : 'Room for your people.'} detail={search ? 'Try a name, number, or message.' : 'Start a chat or bring your crew into a group.'} />}
      <p className="social-endnote">LESS SCROLLING. MORE CONNECTING.</p>
    </div>
    {mode && <SocialSheet title={mode === 'chat' ? 'Say hello.' : 'Bring your people.'} detail={mode === 'chat' ? 'Start with a number or someone you know.' : 'A space for the whole crew.'} onClose={() => setMode('')}>
      <form className="form" onSubmit={e => { e.preventDefault(); if (mode === 'chat') startChat(); else createGroup(); }}>
        {mode === 'chat' ? <label>Phone number<input required inputMode="tel" pattern="[0-9]{7,16}" maxLength={16} placeholder="555…" value={number} onChange={e => setNumber(e.target.value)} /></label> : <><label>Group name<input required maxLength={60} placeholder="The night crew" value={groupName} onChange={e => setGroupName(e.target.value)} /></label><label>Phone numbers<input required maxLength={850} placeholder="555…, 555…" value={groupNumbers} onChange={e => setGroupNumbers(e.target.value)} /></label><p className="muted">Separate numbers with commas. Up to 49 people.</p></>}
        <button className="primary" disabled={busy || (mode === 'group' && !groupName.trim())}>{mode === 'chat' ? 'Start conversation' : 'Create group'}<ArrowUpRight size={17} /></button>
      </form>
      {mode === 'chat' && <div className="pulse-picker">{data.contacts.map(contact => <button key={contact.number} disabled={busy} onClick={() => startChat(contact.number)}><SocialAvatar name={contact.name} photo={contact.photo} /><span><strong>{contact.name}</strong><small>{contact.number}</small></span><ArrowUpRight size={17} /></button>)}</div>}
    </SocialSheet>}
  </div>;
}
