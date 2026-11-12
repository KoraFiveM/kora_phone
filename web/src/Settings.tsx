import { useEffect, useRef, useState } from 'react';
import type { FormEvent, ReactNode } from 'react';
import { ArrowLeft, Check, ChevronRight, Cloud, Fingerprint, Info, Moon, Palette, ShieldCheck, Smartphone, Volume2, Wifi } from 'lucide-react';
import { asList } from './types';
import { isQuiet } from './quiet';
import { api } from './api';
import { ImagePicker } from './Images';
import { PHONE_CASES, CoverScene } from './CoverArt';
import { WALLPAPERS } from './Setup';
import { handsetIconStyle, handsetIdentity, resolveHandsetTheme, themeOptions } from './themes';
import type { Settings } from './types';
import { LoadState, useLoad, usePhone } from './PhoneContext';
import './settings-hub.css';

type Area = 'appearance' | 'connections' | 'cloud' | 'privacy' | 'sound' | 'about';
type PanelView = 'connections' | 'cloud' | 'security' | 'device';
type Status = 'idle' | 'saving' | 'saved' | 'error';
const WALLPAPER_CHOICES: { id: Settings['wallpaper']; label: string; swatch: string }[] = [
  ...WALLPAPERS,
  { id: 'custom', label: 'Your photo', swatch: 'repeating-linear-gradient(45deg, #8a8a8a 0 6px, #bcbcbc 6px 12px)' },
];
const ICON_STYLES: { id: NonNullable<Settings['iconStyle']>; label: string }[] = [{ id: 'circle', label: 'Circle' }, { id: 'squircle', label: 'Rounded' }, { id: 'outline', label: 'Outline' }, { id: 'solid', label: 'Solid' }];
const TITLES: Record<Area, string> = { appearance: 'Appearance', connections: 'Connections', cloud: 'Cloud account', privacy: 'Privacy & security', sound: 'Sound & alerts', about: 'About & resale' };
const STATUS_TEXT: Record<Status, string> = { idle: 'Changes save automatically', saving: 'Saving changes…', saved: 'All changes saved', error: 'Could not save. Try your change again.' };

export function SettingsScreen({ handsetPanel }: { handsetPanel?: (view: PanelView) => ReactNode }) {
  const { data, device, updateData, setHasPin, run, busy, notify } = usePhone();
  const settings = data.settings;
  const model = device.model || 'standard';
  const identity = handsetIdentity(model);
  const palette = resolveHandsetTheme(model, settings.theme);
  const [area, setArea] = useState<Area>();
  const [status, setStatus] = useState<Status>('idle');
  const latest = useRef(settings);
  latest.current = settings;
  const saveVersion = useRef(0);
  const pendingSave = useRef<{settings:Settings;version:number}|undefined>(undefined);
  const saving = useRef(false);
  const lastSave = useRef(0);
  const mounted = useRef(true);
  const title = useRef<HTMLHeadingElement>(null);
  const [currentPin, setCurrentPin] = useState(''); const [pin, setPin] = useState(''); const [confirm, setConfirm] = useState('');
  const [pinOpen, setPinOpen] = useState(false);
  const [wallpaperPhotoOpen, setWallpaperPhotoOpen] = useState(settings.wallpaper === 'custom');
  const [casePhotoOpen, setCasePhotoOpen] = useState(settings.phoneCase === 'custom');
  const blocked = useLoad(() => api('blocked', {}), []);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  useEffect(() => { if (area) title.current?.focus(); }, [area]);

  const persist = async () => {
    if (saving.current) return;
    saving.current=true;
    try {
      while (pendingSave.current) {
        const delay=300-(Date.now()-lastSave.current);
        if (delay>0) await new Promise(resolve=>window.setTimeout(resolve,delay));
        const write=pendingSave.current;
        pendingSave.current=undefined;
        lastSave.current=Date.now();
        try {
          await api('settings',Object.assign({},write.settings,{expectedDeviceId:device.id}));
          if (mounted.current && write.version===saveVersion.current) setStatus('saved');
        } catch (error) {
          if (mounted.current && write.version===saveVersion.current) {
            setStatus('error'); notify(error instanceof Error ? error.message : 'Could not save settings');
          }
        }
      }
    } finally { saving.current=false; }
  };
  // Keep the latest slider/text change without flooding the server or losing it on navigation.
  const change = (patch: Partial<Settings>) => {
    const next = { ...latest.current, ...patch };
    latest.current = next;
    updateData({ ...data, settings: next });
    if (!next.name.trim() || (next.wallpaper === 'custom' && !next.wallpaperUrl) || (next.phoneCase === 'custom' && !next.phoneCaseUrl)) return;
    const version = ++saveVersion.current;
    setStatus('saving');
    pendingSave.current={settings:next,version};
    void persist();
  };
  const resetPin = () => { setCurrentPin(''); setPin(''); setConfirm(''); setPinOpen(false); };
  const open = (next?: Area) => { resetPin(); setArea(next); };
  const submitPin = (event: FormEvent) => {
    event.preventDefault();
    if (pin !== confirm) { notify('Those PINs don’t match. Try again.'); return; }
    void run(async () => {
      const result = await api('pin', { pin, currentPin });
      setHasPin(result.hasPin); resetPin(); notify(device.hasPin ? 'PIN updated' : 'PIN protection enabled');
    });
  };
  const removePin = () => {
    if (!currentPin) { notify('Enter your current PIN to remove it.'); return; }
    void run(async () => { const result = await api('pin', { pin: '', currentPin }); setHasPin(result.hasPin); resetPin(); notify('PIN removed'); });
  };
  const pinInput = (label: string, value: string, set: (value: string) => void) => <label>{label}<input required type="password" inputMode="numeric" pattern="[0-9]{4,8}" maxLength={8} autoComplete="off" value={value} onChange={event => set(event.target.value)} /></label>;
  const panel = (view: PanelView) => <div className="settings-connected-panel" inert={status === 'saving'}>{handsetPanel?.(view)}</div>;
  const categories = [
    { id: 'appearance' as const, icon: Palette, text: 'Wallpaper, icons & display', value: palette.label },
    { id: 'connections' as const, icon: Wifi, text: 'SIM, Wi-Fi & phone number', value: device.number ? 'Mobile' : 'No SIM' },
    { id: 'cloud' as const, icon: Cloud, text: 'Back up & restore your content', value: '' },
    { id: 'privacy' as const, icon: Fingerprint, text: 'PIN, Face ID & blocked numbers', value: device.hasPin ? 'Protected' : 'No PIN' },
    { id: 'sound' as const, icon: Volume2, text: 'Volume & quiet hours', value: isQuiet(settings) ? 'Quiet' : `${Math.round(settings.volume * 100)}%` },
    { id: 'about' as const, icon: Info, text: 'Handset, name & prepare for resale', value: '' },
  ];
  return <div className={`settings-hub ${area ? 'has-detail' : ''}`}>
    {!area ? <>
      <section className="settings-identity" aria-label="Your phone">
        <span className={`settings-device-mark model-${model}`} aria-hidden="true"><Smartphone size={30} strokeWidth={1.2} /></span>
        <div><span className="settings-overline">{identity.os}</span><h2>{settings.name || identity.name}</h2><p>{device.number || 'No active SIM'}<span>{identity.name}</span></p></div>
      </section>
      <p className="settings-intro">Make it feel like yours.</p>
      <nav className="settings-category-list" aria-label="Settings categories">{categories.map(item => <button type="button" className="settings-category" key={item.id} disabled={status === 'saving'} onClick={() => open(item.id)}>
        <span className={`settings-category-icon category-${item.id}`}><item.icon size={20} strokeWidth={1.6} /></span><span className="settings-category-copy"><strong>{TITLES[item.id]}</strong><small>{item.text}</small></span>{item.value && <span className="settings-category-value">{item.value}</span>}<ChevronRight size={16} />
      </button>)}</nav>
      <p className="settings-system-note">{identity.subtitle}</p>
    </> : <section className="settings-detail" aria-label={TITLES[area]}>
      <button type="button" className="settings-return" disabled={status === 'saving'} onClick={() => open()}><ArrowLeft size={15} />All settings</button>
      <header className="settings-detail-heading"><span className="settings-overline">{identity.os}</span><h2 ref={title} tabIndex={-1}>{TITLES[area]}</h2></header>
      {area === 'appearance' && <>
        <section className="settings-theme-preview" aria-label="Current appearance" style={{ background: palette.color, color: palette.dark ? '#f5f5f5' : '#202020' }}><div><span>{identity.name}</span><strong>{palette.label}</strong></div><span className="settings-preview-dots" aria-hidden="true"><i /><i /><i /></span></section>
        <section className="settings-group form" aria-label="Appearance choices"><fieldset className="settings-palette-grid"><legend>Color theme</legend>{themeOptions(model).map(theme => <button type="button" key={theme.id} className="settings-palette-choice" aria-pressed={palette.id === theme.id} onClick={() => change({ theme: theme.id })}><span style={{ background: theme.color, color: theme.dark ? '#fff' : '#202020' }}>{palette.id === theme.id && <Check size={17} />}</span><strong>{theme.label}</strong></button>)}</fieldset>
          <fieldset className="settings-wallpaper-grid"><legend>Wallpaper</legend>{WALLPAPER_CHOICES.map(item => <button type="button" key={item.id} aria-pressed={settings.wallpaper === item.id} onClick={() => { setWallpaperPhotoOpen(item.id === 'custom'); if (item.id !== 'custom' || settings.wallpaperUrl) change({ wallpaper: item.id }); }}><span style={{ background: item.id === 'kora_core' ? palette.wallpaper : item.id === 'plain' ? palette.bg : item.swatch }} />{item.label}{settings.wallpaper === item.id && <Check size={12} />}</button>)}</fieldset>
          {wallpaperPhotoOpen && <ImagePicker label="Wallpaper photo" value={settings.wallpaperUrl || ''} onChange={wallpaperUrl => change({ wallpaper: wallpaperUrl ? 'custom' : 'plain', wallpaperUrl })} photos={data.photos} />}
          {model === 'standard' ? <p className="settings-explanation">The monochrome icon pack is part of this handset’s identity.</p> : <fieldset className="settings-icon-options"><legend>Icon style</legend>{ICON_STYLES.map(item => <button type="button" key={item.id} aria-pressed={handsetIconStyle(model,settings.iconStyle) === item.id} onClick={() => change({ iconStyle: item.id })}>{item.label}</button>)}</fieldset>}
          <label>Display size <span className="settings-field-value">{Math.round(settings.scale * 100)}%</span><input aria-label="Display size" type="range" min="0.75" max="1.15" step="0.05" value={settings.scale} onChange={event => change({ scale: Number(event.target.value) })} /></label>
        </section>
        {model === 'flip' && <section className="settings-group form" aria-label="Phone case"><h3>Cover screen case</h3><fieldset className="cover-choices"><legend>Case design</legend>{PHONE_CASES.map(item => <button type="button" className="cover-choice" key={item.id} aria-pressed={(settings.phoneCase ?? 'default') === item.id} onClick={() => { setCasePhotoOpen(item.id === 'custom'); if (item.id !== 'custom' || settings.phoneCaseUrl) change({ phoneCase: item.id }); }}><span className="cover-thumb">{item.id === 'default' || item.id === 'custom' ? <i className={`cover-thumb-${item.id}`} /> : <CoverScene id={item.id} />}</span>{item.label}</button>)}</fieldset>{casePhotoOpen && <ImagePicker label="Case photo" value={settings.phoneCaseUrl || ''} onChange={phoneCaseUrl => change({ phoneCase: phoneCaseUrl ? 'custom' : 'default', phoneCaseUrl })} photos={data.photos} />}</section>}
      </>}
      {area === 'connections' && <><p className="settings-detail-description">Your SIM carries your number. Wi-Fi keeps cloud services available without mobile service.</p>{panel('connections')}</>}
      {area === 'cloud' && <><p className="settings-detail-description">Keep contacts, messages, photos and preferences ready for your next handset.</p>{panel('cloud')}</>}
      {area === 'privacy' && <>
        <form className="settings-group form" onSubmit={submitPin} aria-label="Device security"><h3><ShieldCheck size={18} />Screen lock<span className="settings-state">{device.hasPin ? 'ON' : 'OFF'}</span></h3><p className="settings-explanation">{device.hasPin ? 'Your PIN protects this handset whenever you close it.' : 'Anyone holding this handset can open it until you set a PIN.'}</p>{pinOpen ? <>{device.hasPin && pinInput('Current PIN', currentPin, setCurrentPin)}{pinInput(device.hasPin ? 'New PIN (4–8 digits)' : 'Set a PIN (4–8 digits)', pin, setPin)}{pinInput('Confirm PIN', confirm, setConfirm)}<button className="primary" disabled={busy}>{device.hasPin ? 'Change PIN' : 'Turn on PIN'}</button>{device.hasPin && <button type="button" className="text-button danger" disabled={busy} onClick={removePin}>Remove PIN</button>}<button type="button" className="text-button" onClick={resetPin}>Cancel</button></> : <button type="button" className="primary" onClick={() => setPinOpen(true)} aria-expanded={false}>{device.hasPin ? 'Change or remove PIN' : 'Set a PIN'}</button>}</form>
        {panel('security')}
        <section className="settings-group form" aria-label="Blocked numbers"><h3>Blocked numbers<span className="settings-state">{asList(blocked.value).length}</span></h3><LoadState {...blocked} retry={blocked.refresh} />{!blocked.loading && !blocked.error && !asList(blocked.value).length && <p className="settings-explanation">No blocked numbers. You can block a number from its conversation.</p>}{asList<string>(blocked.value).map(number => <div className="blocked-row" key={number}><span>{data.contacts.find(c => c.number === number)?.name || number}<small>{number}</small></span><button type="button" className="text-button" disabled={busy} onClick={() => run(async () => { await api('setBlocked', { number, blocked: false }); blocked.refresh(); notify('Unblocked'); })}>Unblock</button></div>)}</section>
      </>}
      {area === 'sound' && <>
        <section className="settings-group form" aria-label="Volume"><label>Phone volume<span className="settings-field-value">{Math.round(settings.volume * 100)}%</span><input aria-label="Phone volume" type="range" min="0" max="1" step="0.05" value={settings.volume} onChange={event => change({ volume: Number(event.target.value) })} /></label></section>
        <section className="settings-group form" aria-label="Do not disturb"><h3><Moon size={17} />Do not disturb<span className="settings-state">{isQuiet(settings) ? 'ON' : 'OFF'}</span></h3><div className="segments" role="group" aria-label="Do not disturb">{[false, true].map(on => <button type="button" key={String(on)} className={!!settings.dnd === on ? 'selected' : ''} aria-pressed={!!settings.dnd === on} onClick={() => change({ dnd: on })}>{on ? 'On' : 'Off'}</button>)}</div><div className="quiet-hours"><label>Quiet from<input type="time" value={settings.dndFrom ?? ''} onChange={event => change({ dndFrom: event.target.value })} /></label><label>Until<input type="time" value={settings.dndTo ?? ''} onChange={event => change({ dndTo: event.target.value })} /></label></div>{(settings.dndFrom || settings.dndTo) && <button type="button" className="text-button" onClick={() => change({ dndFrom: '', dndTo: '' })}>Clear schedule</button>}<p className="settings-explanation">Silences alerts and ringtones. Calls still arrive, and notifications stay in your shade. Set both times for a daily schedule.</p></section>
      </>}
      {area === 'about' && <>
        <section className="settings-group form" aria-label="Device"><div className="settings-about-model"><Smartphone size={27} strokeWidth={1.3} /><div><h3>{identity.name}</h3><p>{identity.os}</p></div></div><label>Device name<input aria-label="Device name" required maxLength={32} value={settings.name} onChange={event => change({ name: event.target.value })} /></label><dl className="settings-device-facts"><div><dt>Phone number</dt><dd>{device.number || 'No active SIM'}</dd></div><div><dt>Handset type</dt><dd>{model === 'fold' ? 'Foldable' : model === 'flip' ? 'Flip' : 'Standard'}</dd></div><div><dt>Screen lock</dt><dd>{device.hasPin ? 'PIN protected' : 'Not set'}</dd></div></dl></section>
        {panel('device')}
        <p className="settings-explanation">The handset keeps local content. Your SIM holds your number. Your cloud account keeps your backup.</p>
      </>}
    </section>}
    <p className="settings-save-state" role="status" aria-live="polite" data-status={status}>{status === 'saved' && <Check size={12} />}{STATUS_TEXT[status]}</p>
  </div>;
}
