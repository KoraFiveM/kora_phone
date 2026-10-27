import { useCallback, useEffect, useRef, useState } from 'react';
import { Check, ChevronRight, Cloud, Copy, Fingerprint, RefreshCw, ShieldCheck, ShoppingBag, Smartphone, Wifi } from 'lucide-react';
import { isPreview, nui } from './api';
import './handsets.css';

type Model = 'standard' | 'flip' | 'fold';
type Phone = { slot: number; model: Model; id?: string };
type Shop = { id: string; label: string; business: boolean; prices: Record<string, number> };
type Status = {
  handset: { id: string; model: Model }; number: string; cellular: boolean;
  sim?: { id: string; status: string }; accountId?: string; faceId: boolean;
  wifi?: string; online: boolean; phones: Phone[]; sims: { slot: number; id?: string }[];
  hotspots: { id: string; label: string; private: boolean }[]; shops: Shop[];
  simSwap?: 'player' | 'shop' | 'both';
  accounts?: {id:string}[];
};
type Result<T> = { ok: true; data: T } | { ok: false; error?: string | { message?: string; code?: string } };
type Payload = { op: string; [key: string]: unknown };
type Secret = { accountId: string; recoveryCode: string };
type Confirmation = { title: string; detail: string; payload: Payload; success: string };
const names: Record<Model, string> = { standard: 'Orchard One', flip: 'Circuit Flip', fold: 'Atlas Fold' };
const itemNames: Record<string, string> = { phone_standard: 'Orchard One', phone_flip: 'Circuit Flip', phone_fold: 'Atlas Fold', phone_sim: 'Mobile SIM' };
const price = (value: number) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(value);
const previewStatus = (): Status => ({
  handset: { id: 'DEMO-ORCHARD-001', model: 'standard' }, number: '5551234567', cellular: true,
  sim: { id: 'DEMO-SIM-001', status: 'active' }, faceId: false, online: true,
  phones: [{ slot: 1, model: 'standard', id: 'DEMO-ORCHARD-001' }, { slot: 2, model: 'flip', id: 'DEMO-CIRCUIT-002' }, { slot: 3, model: 'fold', id: 'DEMO-ATLAS-003' }],
  sims: [{ slot: 4, id: 'DEMO-SIM-002' }],
  hotspots: [{ id: 'legion', label: 'Legion Public Wi-Fi', private: false }, { id: 'workshop', label: 'Workshop Private', private: true }],
  shops: [{ id: 'legion', label: 'Circuit Mobile', business: false, prices: { phone_standard: 1200, phone_flip: 1800, phone_fold: 2400, phone_sim: 100 } }], simSwap: 'both',
});

export function HandsetPanel({ onReload, previewModel, onPreviewModel, view='all' }: { onReload: () => Promise<void> | void; previewModel?: Model; onPreviewModel?: (model:Model)=>void; view?: 'all'|'connections'|'cloud'|'security'|'device' }) {
  const [status, setStatus] = useState<Status>();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');
  const [secret, setSecret] = useState<Secret>();
  const [confirmation, setConfirmation] = useState<Confirmation>();
  const [shopId, setShopId] = useState('');
  const [target, setTarget] = useState('');
  const [targetSlot, setTargetSlot] = useState('');
  const dialog = useRef<HTMLDivElement>(null);
  const [accountId, setAccountId] = useState('');
  const [code, setCode] = useState('');
  const [number, setNumber] = useState('');
  const [hotspot, setHotspot] = useState('');
  const [password, setPassword] = useState('');
  const [swapAtShop, setSwapAtShop] = useState(false);
  const demo = useRef(previewStatus());
  useEffect(() => {
    if (!isPreview || !previewModel) return;
    const phone=demo.current.phones.find(p=>p.model===previewModel);
    if (phone?.id) { demo.current.handset={id:phone.id,model:previewModel}; setStatus(structuredClone(demo.current)); }
  },[previewModel]);
  const mounted = useRef(true);
  const pending = useRef(false);
  useEffect(() => {
    if (!confirmation) return;
    const previous = document.activeElement as HTMLElement | null;
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); setConfirmation(undefined); }
      if (event.key !== 'Tab') return;
      const buttons = dialog.current?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)');
      if (!buttons?.length) return;
      const first = buttons[0], last = buttons[buttons.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', keydown);
    return () => { document.removeEventListener('keydown', keydown); previous?.focus(); };
  }, [confirmation]);
  const request = useCallback(async <T,>(payload: Payload): Promise<T> => {
    if (isPreview) {
      const d = demo.current;
      if (payload.op === 'status') return structuredClone(d) as T;
      if (payload.op === 'select') {
        const phone = d.phones.find(item => item.slot === payload.slot);
        if (phone?.id) { d.handset = { id: phone.id, model: phone.model }; onPreviewModel?.(phone.model); }
      } else if (payload.op === 'wifi') { d.wifi = String(payload.id); d.online = true; }
      else if (payload.op === 'faceEnroll') d.faceId = true;
      else if (payload.op === 'registerCloud' || payload.op === 'recoverCloud') {
        d.accountId = d.accountId || 'DEMO-CLOUD-001';
        return { accountId: d.accountId, recoveryCode: 'DEMO-RECOVERY-CODE-SAVE-THIS' } as T;
      } else if (payload.op === 'restoreCloud') d.accountId = String(payload.accountId);
      else if (payload.op === 'removeSim') {
        if (d.sim) d.sims.push({ slot: 5, id: d.sim.id });
        d.sim = undefined; d.cellular = false; d.number = ''; d.online = Boolean(d.wifi);
      } else if (payload.op === 'insertSim') {
        if (d.sim) throw new Error('Remove the inserted SIM first');
        const sim = d.sims.find(item => item.slot === payload.slot);
        if (sim) { d.sim = { id: sim.id || 'DEMO-SIM', status: 'active' }; d.sims = d.sims.filter(item => item !== sim); d.cellular = true; d.number = '5551234567'; d.online = true; }
      } else if (payload.op === 'reset') {
        if (d.sim) throw new Error('Remove the SIM before resetting');
        d.accountId = undefined; d.faceId = false;
      }
      return true as T;
    }
    const response = await nui<Result<T>>('handset:action', payload);
    if (!response.ok) {
      const problem = response.error;
      throw new Error(typeof problem === 'string' ? problem : problem?.message || problem?.code || 'Phone operation failed');
    }
    return response.data;
  }, [onPreviewModel]);
  const refresh = useCallback(async () => {
    const next = await request<Status>({ op: 'status' });
    if (mounted.current) setStatus(next);
  }, [request]);
  useEffect(() => {
    mounted.current = true;
    void refresh().catch(problem => { if (mounted.current) setError(problem instanceof Error ? problem.message : 'Cannot load handset details'); });
    return () => { mounted.current = false; };
  }, [refresh]);
  const execute = async (payload: Payload, success: string) => {
    if (pending.current) return;
    pending.current = true; setBusy(true); setMessage(''); setError('');
    try {
      const result = await request<unknown>(payload);
      if (!mounted.current) return;
      if (result && typeof result === 'object' && 'recoveryCode' in result && 'accountId' in result) {
        setSecret({ accountId: String(result.accountId), recoveryCode: String(result.recoveryCode) });
      }
      if (payload.op === 'wifi') setPassword('');
      if (payload.op === 'restoreCloud') { setCode(''); setAccountId(''); }
      setMessage(success);
      await refresh();
      if (payload.op !== 'status') await onReload();
    } catch (problem) {
      if (mounted.current) setError(problem instanceof Error ? problem.message : 'Phone operation failed');
    } finally {
      pending.current = false;
      if (mounted.current) setBusy(false);
    }
  };
  const shop = status?.shops.find(item => item.id === shopId) || status?.shops[0];
  const selectedHotspot = status?.hotspots.find(item => item.id === hotspot) || status?.hotspots[0];
  const customer = shop?.business && target.trim() ? { target: Number(target) } : {};
  const services = { shop: shop?.id, ...customer };
  const shopSwap = status?.simSwap === 'shop' || swapAtShop;
  const swapContext = shopSwap ? { shop: shop?.id } : {};
  const confirm = (title: string, detail: string, payload: Payload, success: string) => setConfirmation({ title, detail, payload, success });
  const copySecret = async () => {
    if (!secret) return;
    try {
      await navigator.clipboard.writeText(`Cloud account: ${secret.accountId}\nRecovery code: ${secret.recoveryCode}`);
      setMessage('Recovery details copied. Save them somewhere safe.');
    } catch { setError('Copy is unavailable here. Select and save the recovery details manually.'); }
  };

  return <section className="handset-panel" data-view={view} aria-label="Handset, SIM and cloud">
    <header className="hs-header"><span className="hs-kicker">YOUR CONNECTION</span><div><h2>Handset & cloud</h2><button type="button" className="hs-icon" aria-label="Refresh handset details" disabled={busy} onClick={() => void execute({ op: 'status' }, 'Handset details refreshed')}><RefreshCw size={17} /></button></div><p>Your phone, your number, your memories.</p></header>
    {isPreview && <p className="hs-preview">Interactive preview · no server data changes</p>}
    {error && <p className="hs-notice hs-error" role="alert">{error}</p>}
    {message && <p className="hs-notice" role="status"><Check size={15} />{message}</p>}
    {secret && <section className="hs-secret" aria-label="Save your recovery details"><ShieldCheck size={24} /><h3>Keep this somewhere safe.</h3><p>This recovery code is shown once. It gives access to your cloud backup.</p><label>Cloud account<code tabIndex={0}>{secret.accountId}</code></label><label>Recovery code<code tabIndex={0}>{secret.recoveryCode}</code></label><div className="hs-actions"><button type="button" className="hs-button hs-primary" onClick={() => void copySecret()}><Copy size={15} />Copy details</button><button type="button" className="hs-button" onClick={() => setSecret(undefined)}>I saved it</button></div></section>}
    {!status ? <p className="hs-empty">Loading your handset…</p> : <div className="hs-grid">
      <section className="hs-card hs-identity" data-section="device"><div className="hs-card-heading"><Smartphone size={19} /><h3>{names[status.handset.model]}</h3><span className={`hs-pill ${status.online ? 'is-on' : ''}`}>{status.online ? 'Online' : 'Offline'}</span></div><p className="hs-number">{status.number || 'No mobile service'}</p><dl><div><dt>Handset</dt><dd title={status.handset.id}>{status.handset.id}</dd></div><div><dt>SIM</dt><dd>{status.sim ? status.sim.status : 'Not inserted'}</dd></div><div><dt>Cloud</dt><dd title={status.accountId}>{status.accountId || 'Not signed in'}</dd></div></dl>
        <div className="hs-list" aria-label="Your handsets">{status.phones.map(phone => <button type="button" className="hs-phone-row" key={phone.slot} disabled={busy || phone.id === status.handset.id} onClick={() => confirm('Switch handset?', 'Any active call will end. The selected handset keeps its own SIM, lock and cloud login.', { op: 'select', slot: phone.slot }, 'Handset selected')}><Smartphone size={17} /><span>{names[phone.model]}<small>Inventory slot {phone.slot}</small></span>{phone.id === status.handset.id ? <Check size={17} /> : <ChevronRight size={17} />}</button>)}</div>
      </section>
      <section className="hs-card" data-section="security"><div className="hs-card-heading"><Fingerprint size={19} /><h3>Face ID</h3><span className="hs-pill">{status.faceId ? 'Enrolled' : 'Not set'}</span></div><p>Recognises your character on this handset. Set a backup PIN in Device security first.</p><button type="button" className="hs-button" disabled={busy} onClick={() => void execute({ op: 'faceEnroll' }, 'Face ID enrolled for this character')}>{status.faceId ? 'Enrol this character again' : 'Set up Face ID'}</button></section>
      <section className="hs-card" data-section="connections"><div className="hs-card-heading"><Smartphone size={19} /><h3>Mobile SIM</h3></div><p>Your number follows the SIM. Your cloud history stays with your account.</p>
        {status.simSwap !== 'player' && <label className="hs-check"><input type="checkbox" checked={status.simSwap === 'shop' || swapAtShop} disabled={status.simSwap === 'shop' || busy} onChange={event => setSwapAtShop(event.target.checked)} />Use selected shop counter</label>}
        {shopSwap && <p className="hs-caption">Counter: {shop?.label || 'No authorised shop nearby'}</p>}
        {status.sim ? <button type="button" className="hs-button" disabled={busy || (shopSwap && !shop)} onClick={() => void execute({ op: 'removeSim', ...swapContext }, 'SIM returned to your inventory')}>Remove inserted SIM</button> : status.sims.length ? <div className="hs-list">{status.sims.map(sim => <button type="button" className="hs-phone-row" key={sim.slot} disabled={busy || (shopSwap && !shop)} onClick={() => void execute({ op: 'insertSim', slot: sim.slot, ...swapContext }, 'SIM inserted')}><span>Insert SIM<small>Slot {sim.slot} · {sim.id || 'New SIM'}</small></span><ChevronRight size={17} /></button>)}</div> : <p className="hs-empty">No loose SIM in your inventory.</p>}
      </section>
      <section className="hs-card" data-section="connections"><div className="hs-card-heading"><Wifi size={19} /><h3>Wi-Fi</h3></div><p>Back up and restore without a SIM. Calls still need mobile service.</p>{status.wifi && <p className="hs-caption">Connected: {status.hotspots.find(item => item.id === status.wifi)?.label || status.wifi}</p>}
        {status.hotspots.length ? <form onSubmit={event => { event.preventDefault(); void execute({ op: 'wifi', id: selectedHotspot?.id, password }, 'Wi-Fi connected'); }}><label>Nearby network<select value={selectedHotspot?.id || ''} disabled={busy} onChange={event => { setHotspot(event.target.value); setPassword(''); }}>{status.hotspots.map(network => <option key={network.id} value={network.id}>{network.label}{network.private ? ' · Private' : ''}</option>)}</select></label>{selectedHotspot?.private && <label>Network password<input type="password" autoComplete="off" value={password} onChange={event => setPassword(event.target.value)} required maxLength={128} /></label>}<button className="hs-button" disabled={busy}>Connect</button></form> : <p className="hs-empty">No Wi-Fi networks in range.</p>}
      </section>
      <section className="hs-card" data-section="cloud"><div className="hs-card-heading"><Cloud size={19} /><h3>Cloud backup</h3></div><p>Save contacts, messages, photos and preferences. Restoring replaces this handset’s local content.</p>
        {status.accountId ? <button type="button" className="hs-button hs-primary" disabled={busy || !status.online} onClick={() => void execute({ op: 'backup' }, 'Cloud backup saved')}>Back up now</button> : <button type="button" className="hs-button hs-primary" disabled={busy || !status.online} onClick={() => void execute({ op: 'registerCloud' }, 'Cloud account created. Save your recovery code.')}>Create cloud account</button>}
        {!status.online && <p className="hs-caption">Connect to Wi-Fi or insert an active SIM first.</p>}
        <details className="hs-details"><summary>Restore a cloud account</summary><form onSubmit={event => { event.preventDefault(); confirm('Replace local content?', 'Contacts, messages, photos and preferences on this handset will be replaced by this cloud backup. Back up anything you want to keep first.', { op: 'restoreCloud', accountId: accountId.trim(), code: code.trim() }, 'Cloud backup restored'); }}><label>Cloud account ID (optional for one registered account)<input list="owned-cloud-accounts" value={accountId} onChange={event => setAccountId(event.target.value)} required maxLength={128} autoComplete="off" /></label><label>Recovery code<input type="password" value={code} onChange={event => setCode(event.target.value)} required maxLength={128} autoComplete="off" /></label><button className="hs-button" disabled={busy || !status.online}>Restore account</button></form></details>
      </section>
      <section className="hs-card" data-section="device"><div className="hs-card-heading"><ShoppingBag size={19} /><h3>Mobile services</h3></div>{status.shops.length ? <><label>Nearby counter<select value={shop?.id || ''} onChange={event => { setShopId(event.target.value); setTarget(''); }} disabled={busy}>{status.shops.map(counter => <option key={counter.id} value={counter.id}>{counter.label}{counter.business ? ' · Player business' : ''}</option>)}</select></label>{shop?.business && <label>Customer server ID <span className="hs-optional">optional</span><input type="number" min={1} step={1} placeholder="Leave blank for yourself" value={target} onChange={event => setTarget(event.target.value)} /></label>}
        <div className="hs-list">{Object.entries(shop?.prices || {}).map(([item, amount]) => <button type="button" className="hs-phone-row" key={item} disabled={busy} onClick={() => confirm(`Buy ${itemNames[item] || item}?`, `${price(amount)} will be charged by ${shop?.label}. Stock, payment and inventory space must be available.`, { op: 'buy', item, ...services }, 'Purchase completed')}><span>{itemNames[item] || item}</span><strong>{price(amount)}</strong></button>)}</div>
        <details className="hs-details"><summary>Replace a lost or stolen SIM</summary><form onSubmit={event => { event.preventDefault(); confirm('Replace this SIM?', 'The number stays the same. Its old SIM will be permanently disabled, including any hacked copy. The configured service fee applies.', { op: 'replaceSim', number: number.trim(), ...services }, 'Replacement SIM issued'); }}><label>Registered phone number<input inputMode="tel" value={number} onChange={event => setNumber(event.target.value)} maxLength={24} required /></label><button className="hs-button" disabled={busy}>Request replacement</button></form></details>
        <details className="hs-details"><summary>Recover a cloud account</summary><form onSubmit={event => { event.preventDefault(); confirm('Recover this account?', 'The service checks the registering character, charges its configured fee, replaces the recovery code and signs out previous cloud sessions.', { op: 'recoverCloud', accountId: accountId.trim(), ...services }, 'Account recovered. Save the new recovery code.'); }}><label>Cloud account ID (optional for one registered account)<input list="owned-cloud-accounts" value={accountId} onChange={event => setAccountId(event.target.value)} maxLength={64} autoComplete="off" /></label><datalist id="owned-cloud-accounts">{status.accounts?.map(a => <option key={a.id} value={a.id} />)}</datalist><button className="hs-button" disabled={busy}>Verify identity & recover</button></form></details>
        <details className="hs-details"><summary>Sell a reset handset</summary><p>Remove its SIM and factory-reset it first. The shop checks that it is ready for resale.</p>{shop?.business && target.trim() ? <form onSubmit={event => { event.preventDefault(); confirm('Sell customer handset?', `The reset handset in customer inventory slot ${targetSlot} will be sold. The configured resale payout applies.`, { op: 'resell', slot: Number(targetSlot), ...services }, 'Handset sold'); }}><label>Customer handset slot<input type="number" min={1} step={1} required value={targetSlot} onChange={event => setTargetSlot(event.target.value)} /></label><button className="hs-button" disabled={busy}>Sell customer handset</button></form> : status.phones.map(phone => <button type="button" className="hs-phone-row" key={phone.slot} disabled={busy} onClick={() => confirm(`Sell ${names[phone.model]}?`, `The handset in slot ${phone.slot} will leave the selected customer's inventory. The configured resale payout applies.`, { op: 'resell', slot: phone.slot, ...services }, 'Handset sold')}><span>{names[phone.model]}<small>Slot {phone.slot}</small></span><ChevronRight size={17} /></button>)}</details>
        </> : <p className="hs-empty">Visit a mobile shop to buy a handset or SIM, recover your account, or sell a reset phone.</p>}</section>
      <section className="hs-card hs-reset" data-section="device"><div className="hs-card-heading"><ShieldCheck size={19} /><h3>Prepare for resale</h3></div><p>Factory reset removes this handset’s PIN, Face ID, cloud login and local content. Your existing cloud backup stays safe.</p><button type="button" className="hs-button hs-danger" disabled={busy || Boolean(status.sim)} onClick={() => confirm('Factory-reset this handset?', 'Local contacts, messages, photos and settings will be cleared. Save a cloud backup first. This cannot be undone on the handset.', { op: 'reset' }, 'Handset reset')}>Erase handset</button>{status.sim && <p className="hs-caption">Remove the SIM before resetting.</p>}</section>
    </div>}
    {confirmation && <div ref={dialog} className="hs-confirm" role="alertdialog" aria-modal="true" aria-labelledby="hs-confirm-title" aria-describedby="hs-confirm-detail"><div><ShieldCheck size={25} /><h3 id="hs-confirm-title">{confirmation.title}</h3><p id="hs-confirm-detail">{confirmation.detail}</p><div className="hs-actions"><button type="button" className="hs-button" disabled={busy} autoFocus onClick={() => setConfirmation(undefined)}>Cancel</button><button type="button" className="hs-button hs-primary" disabled={busy} onClick={() => { const action = confirmation; setConfirmation(undefined); void execute(action.payload, action.success); }}>Confirm</button></div></div></div>}
  </section>;
}
