import { ArrowDownLeft,ArrowUpRight,Check,ShieldCheck,X } from 'lucide-react';
import { useRef,useState } from 'react';
import { api,isPreview,requestId } from '../../api';
import { dateLabel,Empty,money,Row } from '../../components';
import { LoadState,useLoad,usePhone } from '../../core/PhoneContext';
import { asList } from '../../types';


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
