import { Check,Download,Search,X } from 'lucide-react';
import { useState } from 'react';
import { api } from '../../api';
import type { OptionalApp } from '../../catalog';
import { optionalApps } from '../../catalog';
import { appDefinition } from '../../core/appRegistry';
import { usePhone } from '../../core/PhoneContext';
import { appCopy } from '../../locales';
import { CustomAppStore } from '../custom/CustomApps';
/** Store copy for an optional app comes from its registry entry. */
const listing = (id: OptionalApp) => appDefinition(id)!.optional!;

export function StoreScreen() {
  const { data, device, run, busy, updateData, navigate } = usePhone();
  const [search, setSearch] = useState(''); const [category, setCategory] = useState('All');
  const [tab, setTab] = useState('Discover'); const [removing, setRemoving] = useState<OptionalApp>();
  const [working, setWorking] = useState<OptionalApp>();
  const installed = (id: OptionalApp) => data.installedApps?.includes(id) ?? false;
  const supported = (id: OptionalApp) => device.capabilities[id] !== false;
  const change = (app: OptionalApp, value: boolean) => run(async () => {
    setWorking(app);
    try { updateData(await api('installApp', { app, installed: value })); setRemoving(undefined); }
    finally { setWorking(undefined); }
  });
  const visible = optionalApps.filter(id => supported(id)).filter(id => (tab !== 'Installed' || installed(id)) && (category === 'All' || listing(id).category === category) && `${appCopy(id).label} ${listing(id).description}`.toLowerCase().includes(search.toLowerCase()));
  return <div className="store"><div className="segments"><button className={tab === 'Discover' ? 'selected' : ''} onClick={() => setTab('Discover')}>Discover</button><button className={tab === 'Installed' ? 'selected' : ''} onClick={() => setTab('Installed')}>Installed · {data.installedApps?.length || 0}</button></div>
    <label className="store-search"><Search size={17} /><input aria-label="Search apps" placeholder="Find your next favorite" value={search} onChange={e => setSearch(e.target.value)} /></label>
    <div className="store-categories">{['All', 'Social', 'Life', 'Tools'].map(value => <button key={value} className={category === value ? 'selected' : ''} onClick={() => setCategory(value)}>{value}</button>)}</div>
    <div className="section-heading"><span className="section-label">{tab === 'Installed' ? 'ON THIS PHONE' : 'A LITTLE OF EVERYTHING'}</span><span className="store-count">{visible.length.toString().padStart(2, '0')}</span></div>
    {visible.map(id => { const item = listing(id); const Icon = appDefinition(id)!.icon; const name = appCopy(id).label; const busyHere = working === id; return <article className="store-app" key={id}><div className={`store-app-icon ${id === 'social' ? 'dark' : ''}`}><Icon size={25} strokeWidth={1.5} /></div><div className="store-app-copy"><h3>{name}</h3><small>{item.category} · Free</small><p>{item.description}</p>{!supported(id) && <small className="store-unavailable">Unavailable on this server</small>}{installed(id) && !busyHere && <button className="store-remove" disabled={busy} onClick={() => setRemoving(id)}>Remove</button>}</div><button className={`store-get ${installed(id) ? 'installed' : ''} ${busyHere ? 'working' : ''}`} aria-label={`${installed(id) ? 'Open' : 'Install'} ${name}`} disabled={busy || !supported(id)} onClick={() => installed(id) ? navigate(id) : change(id, true)}>{busyHere ? <span className="store-spinner" aria-hidden="true" /> : installed(id) ? <Check size={15} /> : <Download size={15} />}<span>{busyHere ? (installed(id) ? 'Removing' : 'Installing') : installed(id) ? 'Open' : 'Get'}</span></button>{busyHere && <div className="store-progress" aria-hidden="true"><i /></div>}</article>; })}
    {!visible.length && <div className="empty"><h3>{search ? 'Nothing here yet.' : 'Make room for something new.'}</h3><p>{search ? 'Try another name or category.' : 'Discover apps and add them to your phone.'}</p></div>}
    <CustomAppStore search={search} installedOnly={tab === 'Installed'} category={category} />
    <p className="store-footnote">Calling, messages, contacts, camera, gallery, settings, and the App Store come with your phone.</p>
    {removing && <div className="store-confirm" role="dialog" aria-modal="true" aria-label="Remove app"><button className="icon-button" aria-label="Cancel removal" onClick={() => setRemoving(undefined)}><X size={18} /></button><h3>Remove {appCopy(removing).label}?</h3><p>Your saved content stays on this device. Reinstall the app whenever you want.</p><button className="primary" disabled={busy} onClick={() => change(removing, false)}>Remove app</button><button className="text-button" onClick={() => setRemoving(undefined)}>Keep app</button></div>}
  </div>;
}
