import { useState } from 'react';
import { AlarmClock, Aperture, ArrowUpRight, Check, CloudSun, CreditCard, Download, House, Mail, MapPin, Music, Radio, Search, ShieldCheck, StickyNote, Tag, Calculator, Car, X } from 'lucide-react';
import { api } from './api';
import { CustomAppStore } from './CustomApps';
import { optionalApps } from './catalog';
import type { OptionalApp } from './catalog';
import { appCopy } from './locales';
import { usePhone } from './PhoneContext';
const details = {
  banking: { icon: CreditCard, category: 'Life', description: 'Your balance, transfers, and everyday peace of mind.' },
  social: { icon: Radio, category: 'Social', description: 'Message your people, one-on-one or in a group.' },
  classifieds: { icon: Tag, category: 'Life', description: 'Buy, sell, and find something worth keeping.' },
  gps: { icon: MapPin, category: 'Tools', description: 'Familiar places. New directions. Your city, mapped.' },
  services: { icon: ShieldCheck, category: 'Life', description: 'Get in touch with the people who keep the city moving.' },
  notes: { icon: StickyNote, category: 'Tools', description: 'A home for your plans, ideas, and little reminders.' },
  mail: { icon: Mail, category: 'Social', description: 'For the things that deserve more than a text.' },
  weather: { icon: CloudSun, category: 'Life', description: 'A look outside before you head out.' },
  calculator: { icon: Calculator, category: 'Tools', description: 'Everyday numbers, made a little simpler.' },
  property: { icon: House, category: 'Life', description: 'Your properties and a shortcut home.' },
  vehicles: { icon: Car, category: 'Life', description: 'Your vehicles, fuel, and last registered garage.' },
  flash: { icon: Aperture, category: 'Social', description: 'Short videos and photos from around the city, for everyone to see.' },
  music: { icon: Music, category: 'Tools', description: 'Save YouTube, SoundCloud, or stream links and play them from your phone.' },
  clock: { icon: AlarmClock, category: 'Tools', description: 'Set alarms that ring on your local clock, even with the phone closed.' },
};
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
  const visible = optionalApps.filter(id => (tab !== 'Installed' || installed(id)) && (category === 'All' || details[id].category === category) && `${appCopy(id, device.locale).label} ${details[id].description}`.toLowerCase().includes(search.toLowerCase()));
  return <div className="store"><div className="segments"><button className={tab === 'Discover' ? 'selected' : ''} onClick={() => setTab('Discover')}>Discover</button><button className={tab === 'Installed' ? 'selected' : ''} onClick={() => setTab('Installed')}>Installed · {data.installedApps?.length || 0}</button></div>
    {tab === 'Discover' && !search && category === 'All' && <section className="store-feature"><span className="eyebrow">MADE FOR YOUR CITY</span><Radio size={40} strokeWidth={1} /><h2>Find your<br />frequency.</h2><p>Pulse. The conversation starts here.</p><button disabled={busy || !supported('social')} onClick={() => installed('social') ? navigate('social') : change('social', true)}>{working === 'social' ? <span className="store-spinner" aria-hidden="true" /> : <ArrowUpRight size={16} />}{working === 'social' ? 'Installing' : installed('social') ? 'Open Pulse' : 'Get Pulse — Free'}</button>{working === 'social' && <div className="store-progress store-progress-feature" aria-hidden="true"><i /></div>}<div className="store-orbit" /></section>}
    <label className="store-search"><Search size={17} /><input aria-label="Search apps" placeholder="Find your next favorite" value={search} onChange={e => setSearch(e.target.value)} /></label>
    <div className="store-categories">{['All', 'Social', 'Life', 'Tools'].map(value => <button key={value} className={category === value ? 'selected' : ''} onClick={() => setCategory(value)}>{value}</button>)}</div>
    <div className="section-heading"><span className="section-label">{tab === 'Installed' ? 'ON THIS PHONE' : 'A LITTLE OF EVERYTHING'}</span><span className="store-count">{visible.length.toString().padStart(2, '0')}</span></div>
    {visible.map(id => { const item = details[id]; const Icon = item.icon; const name = appCopy(id, device.locale).label; const busyHere = working === id; return <article className="store-app" key={id}><div className={`store-app-icon ${id === 'social' ? 'dark' : ''}`}><Icon size={25} strokeWidth={1.5} /></div><div className="store-app-copy"><h3>{name}</h3><small>{item.category} · Free</small><p>{item.description}</p>{!supported(id) && <small className="store-unavailable">Unavailable on this server</small>}{installed(id) && !busyHere && <button className="store-remove" disabled={busy} onClick={() => setRemoving(id)}>Remove</button>}</div><button className={`store-get ${installed(id) ? 'installed' : ''} ${busyHere ? 'working' : ''}`} aria-label={`${installed(id) ? 'Open' : 'Install'} ${name}`} disabled={busy || !supported(id)} onClick={() => installed(id) ? navigate(id) : change(id, true)}>{busyHere ? <span className="store-spinner" aria-hidden="true" /> : installed(id) ? <Check size={15} /> : <Download size={15} />}<span>{busyHere ? (installed(id) ? 'Removing' : 'Installing') : installed(id) ? 'Open' : 'Get'}</span></button>{busyHere && <div className="store-progress" aria-hidden="true"><i /></div>}</article>; })}
    {!visible.length && <div className="empty"><h3>{search ? 'Nothing here yet.' : 'Make room for something new.'}</h3><p>{search ? 'Try another name or category.' : 'Discover apps and add them to your phone.'}</p></div>}
    {category === 'All' && <CustomAppStore search={search} installedOnly={tab === 'Installed'} />}
    <p className="store-footnote">Calling, messages, contacts, camera, gallery, settings, and the App Store come with your phone.</p>
    {removing && <div className="store-confirm" role="dialog" aria-modal="true" aria-label="Remove app"><button className="icon-button" aria-label="Cancel removal" onClick={() => setRemoving(undefined)}><X size={18} /></button><h3>Remove {appCopy(removing, device.locale).label}?</h3><p>Your saved content stays on this device. Reinstall the app whenever you want.</p><button className="primary" disabled={busy} onClick={() => change(removing, false)}>Remove app</button><button className="text-button" onClick={() => setRemoving(undefined)}>Keep app</button></div>}
  </div>;
}
