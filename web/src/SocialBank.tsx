import { useRef, useState } from 'react';
import { ArrowDownLeft, ArrowUpRight, Check, Flag, MessageCircle, Send, ShieldCheck, Trash2, X } from 'lucide-react';
import { api, isPreview, requestId } from './api';
import { asList } from './types';
import type { Comment, Post } from './types';
import { dateLabel, Empty, money, Row } from './components';
import { LoadState, useLoad, usePhone } from './PhoneContext';
import { SocialSheet } from './SocialUI';

// Wallet has two sections: the money, and the character's ID card (licences read from the server).
export function BankScreen() {
  const [tab, setTab] = useState<'money' | 'id'>('money');
  return <><div className="segments wallet-tabs" role="group" aria-label="Wallet section">{([['money', 'Money'], ['id', 'ID & licences']] as const).map(([id, label]) => <button type="button" key={id} className={tab === id ? 'selected' : ''} aria-pressed={tab === id} onClick={() => setTab(id)}>{label}</button>)}</div>{tab === 'money' ? <MoneyPanel /> : <IdPanel />}</>;
}
function IdPanel() {
  const { run, busy, notify } = usePhone();
  const card = useLoad(() => api('wallet', {}), []);
  return <><LoadState {...card} retry={card.refresh} />{card.value && <>
    <div className="id-card"><div className="id-card-top"><span>LOS SANTOS / IDENTITY</span><ShieldCheck size={18} /></div><h2>{card.value.name}</h2>
      <dl><div><dt>Date of birth</dt><dd>{card.value.birthdate || '—'}</dd></div><div><dt>Citizen ID</dt><dd>{card.value.citizenId}</dd></div><div><dt>Nationality</dt><dd>{card.value.nationality || '—'}</dd></div><div><dt>Occupation</dt><dd>{card.value.job || '—'}</dd></div></dl></div>
    <p className="section-label">LICENCES</p>
    {asList(card.value.licences).map(licence => <Row key={licence.id} title={licence.label} detail={licence.valid ? 'Valid' : 'Not held'} icon={licence.valid ? <Check size={18} /> : <X size={18} />} />)}
    <button className="primary" disabled={busy} onClick={() => run(async () => { await api('showWallet', {}); notify('Shown to the person next to you'); })}>Show my ID to the person next to me</button>
    <small className="muted">Only someone standing close by will see it.</small>
  </>}</>;
}
function MoneyPanel() {
  const { run, busy, notify, device, data } = usePhone();
  const who = (value: string) => data.contacts.find(c => c.number === value)?.name || value;
  const bank = useLoad(() => api('bank', {}), []);
  const [recipient, setRecipient] = useState(''); const [amount, setAmount] = useState('');
  const [review, setReview] = useState(false); const [attempted, setAttempted] = useState(false);
  const transferId = useRef(requestId());
  return <><LoadState {...bank} retry={bank.refresh} />{bank.value && <>
    <div className="bank-card"><div className="bank-card-top"><span>MAZE / PERSONAL</span><ShieldCheck size={18} /></div><p>Available balance</p><h2>{money(bank.value.balance)}</h2><div className="bank-card-bottom"><span>{bank.value.name}</span><span>•• {bank.value.account.slice(-4)}</span></div></div>
    <p className="account-caption">YOUR ACCOUNT · {bank.value.account}</p>
    {!device.transfers ? <section className="panel"><h3>Send money</h3><p className="muted">Transfers are turned off on this server. Your balance and history are still here.</p></section> : <section className="panel"><h3>Send money <ArrowUpRight size={17} /></h3><form className="form" onSubmit={e => { e.preventDefault(); setReview(true); }}>
      <label>Recipient phone number<input required inputMode="numeric" pattern="[0-9]{7,16}" maxLength={16} placeholder={isPreview ? 'Try 5550192042' : '555…'} value={recipient} disabled={review} onChange={e => setRecipient(e.target.value.replace(/\D/g, ''))} /></label><label>Amount<input required inputMode="numeric" type="number" min="1" max="100000" step="1" placeholder="$ 0" value={amount} disabled={review} onChange={e => setAmount(e.target.value)} /></label>
      {review ? <div className="transfer-review"><p>Send <strong>{money(Number(amount))}</strong> to <strong>{recipient}</strong>?</p><small>The recipient must be online.</small><button type="button" className="primary" disabled={busy} onClick={() => run(async () => {
        setAttempted(true);
        const result = await api('transfer', { recipient, amount: Number(amount) }, transferId.current);
        notify(result.status === 'completed' ? 'Transfer completed' : `Transfer ${result.status}. ${result.status === 'pending' ? 'Contact an administrator before sending again.' : 'No further action was taken.'}`);
        bank.refresh();
        if (result.status !== 'pending') { setReview(false); setAttempted(false); setAmount(''); transferId.current = requestId(); }
      })}>{attempted ? 'Check / retry same transfer' : 'Confirm transfer'}</button>{!attempted && <button type="button" className="text-button" onClick={() => setReview(false)}>Edit details</button>}{attempted && <p className="muted">This request keeps the same reference. Check its status before making another transfer.</p>}</div> : <button className="primary" disabled={busy}>Review transfer <ArrowUpRight size={16} /></button>}
    </form></section>}<p className="section-label">RECENT ACTIVITY</p>
    {asList(bank.value.history).map(transaction => { const outgoing = transaction.citizenid === bank.value!.account; return <Row key={transaction.id} title={`${outgoing ? 'To' : 'From'} ${who(outgoing ? transaction.recipient : transaction.citizenid)}`} detail={`${transaction.status} · ${dateLabel(transaction.created_at)}`} icon={outgoing ? <ArrowUpRight size={18} /> : <ArrowDownLeft size={18} />} end={<strong className="transaction-amount">{outgoing ? '−' : '+'}{money(transaction.amount)}</strong>} />; })}
    {!asList(bank.value.history).length && <Empty title="A clean slate" detail="Your phone transfers will appear here." />}
  </>}</>;
}
export function Comments({ post }: { post: Post }) {
  const { run, busy, device } = usePhone();
  const comments = useLoad(() => api('comments', { id: post.id }), [post.id]);
  const [body, setBody] = useState('');
  return <div className="comments"><LoadState {...comments} retry={comments.refresh} />{asList<Comment>(comments.value).map(comment => <div className="comment" key={comment.id}><div><strong>{comment.number}</strong><p>{comment.body}</p></div>{(device.admin || comment.number === device.number) && <button className="icon-button" aria-label="Delete comment" disabled={busy} onClick={() => run(async () => { await api('removeComment', { id: comment.id }); comments.refresh(); })}><Trash2 size={14} /></button>}</div>)}<form className="composer" onSubmit={e => { e.preventDefault(); run(async () => { await api('comment', { id: post.id, body }); setBody(''); comments.refresh(); }); }}><input aria-label="Comment" required maxLength={500} value={body} placeholder="Add your thoughts" onChange={e => setBody(e.target.value)} /><button className="icon-button" disabled={busy} aria-label="Send comment"><Send size={17} /></button></form></div>;
}
export function FeedScreen() {
  const { device, run, busy, navigate, notify } = usePhone();
  const feed = useLoad(() => api('feed', { kind: 'classifieds' }), []);
  const [contact, setContact] = useState<Post>(); const [note, setNote] = useState('');
  const [reporting, setReporting] = useState<Post>(); const [reason, setReason] = useState('scam'); const [details, setDetails] = useState('');
  const [body, setBody] = useState(''); const [price, setPrice] = useState('');
  const [remove, setRemove] = useState<number>();
  const [older, setOlder] = useState<Post[]>([]);
  const posts = [...asList<Post>(feed.value), ...older].filter((p, i, all) => all.findIndex(x => x.id === p.id) === i);
  return <><form className="post-composer panel" onSubmit={e => { e.preventDefault(); run(async () => { await api('post', { kind: 'classifieds', body, price: Number(price) || 0 }); setBody(''); setPrice(''); feed.refresh(); }); }}><label htmlFor="post-body">Find it a new home.</label><textarea id="post-body" required maxLength={2000} placeholder="Describe what you’re selling…" value={body} onChange={e => setBody(e.target.value)} /><input aria-label="Asking price" type="number" min="0" max="100000000" step="1" required placeholder="Asking price ($)" value={price} onChange={e => setPrice(e.target.value)} /><div className="post-composer-bottom"><small>{body.length}/2000</small><button className="small-primary" disabled={busy || !body.trim()}>List item <ArrowUpRight size={15} /></button></div></form>
    <div className="section-heading"><span className="section-label">THE MARKETPLACE</span><button className="text-button" onClick={feed.refresh}>Refresh</button></div><LoadState {...feed} retry={feed.refresh} />
    {posts.map(post => <article className="post" key={post.id}><div className="post-meta"><span className="avatar">{post.number.slice(-2)}</span><div><strong>{post.mine || post.number === device.number ? 'You' : post.number}</strong><small>{dateLabel(post.created_at)} · Los Santos</small></div>{(!!post.mine || device.admin) && <button className="icon-button" aria-label="Remove post" onClick={() => setRemove(remove === post.id ? undefined : post.id)}><Trash2 size={15} /></button>}</div><p className="post-body">{post.body}</p><strong className="price">{money(post.price)}</strong>{remove === post.id && <div className="remove-confirm"><p>Remove this post from the feed?</p><button className="text-button danger" disabled={busy} onClick={() => run(async () => { await api('removePost', { id: post.id }); setOlder(list => list.filter(item => item.id !== post.id)); feed.refresh(); setRemove(undefined); })}>Confirm removal</button><button className="text-button" onClick={() => setRemove(undefined)}>Cancel</button></div>}<div className="post-actions">{post.mine ? <button disabled={busy} onClick={() => run(async () => { await api('markSold', { id: post.id }); setOlder(list => list.filter(item => item.id !== post.id)); feed.refresh(); notify('Marked as sold'); })}><ShieldCheck size={17} />Mark sold</button> : <><button onClick={() => { setNote('Hi, is this still available?'); setContact(post); }}><MessageCircle size={17} />Contact seller</button><button onClick={() => { setReason('scam'); setDetails(''); setReporting(post); }}><Flag size={16} />Report</button></>}<span>↗</span></div></article>)}
    {contact && <SocialSheet title="Message the seller" detail="They’ll get it in Messages." onClose={() => setContact(undefined)}><form onSubmit={e => { e.preventDefault(); run(async () => { await api('contactSeller', { id: contact.id, message: note }); setContact(undefined); notify('Message sent'); navigate('messages'); }); }}><textarea aria-label="Message" required maxLength={1000} value={note} onChange={e => setNote(e.target.value)} /><button className="primary" disabled={busy || !note.trim()}>Send message</button></form></SocialSheet>}
    {reporting && <SocialSheet title="Report this listing" detail="A moderator will take a look." onClose={() => setReporting(undefined)}><form onSubmit={e => { e.preventDefault(); run(async () => { await api('reportListing', { id: reporting.id, reason, details }); setReporting(undefined); notify('Report sent. Thank you.'); }); }}><select aria-label="Reason" value={reason} onChange={e => setReason(e.target.value)}>{['scam', 'spam', 'harassment', 'illegal', 'other'].map(value => <option key={value} value={value}>{value[0].toUpperCase() + value.slice(1)}</option>)}</select><textarea aria-label="Details" maxLength={1000} placeholder="Anything a moderator should know? (optional)" value={details} onChange={e => setDetails(e.target.value)} /><button className="primary" disabled={busy}>Send report</button></form></SocialSheet>}
    {!posts.length && !feed.loading && <Empty title="Room for something new" detail="List an item to get the marketplace started." />}
    {posts.length >= 30 && <button className="text-button" disabled={busy} onClick={() => run(async () => { const rows = await api('feed', { kind: 'classifieds', before: Math.min(...posts.map(p => p.id)) }); setOlder(previous => [...previous, ...asList<Post>(rows)]); })}>Load older posts</button>}
  </>;
}
