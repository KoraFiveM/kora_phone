import { useRef, useState } from 'react';
import type { FormEvent } from 'react';
import { Moon, ShieldCheck } from 'lucide-react';
import { asList } from './types';
import { isQuiet } from './quiet';
import { api } from './api';
import { ImagePicker } from './Images';
import { PHONE_CASES, CoverScene } from './CoverArt';
import { WALLPAPERS } from './Setup';
import { themeChip, themes } from './themes';
import type { Theme } from './themes';
import type { Settings } from './types';
import { LoadState, useLoad, usePhone } from './PhoneContext';

type Status = 'idle' | 'saving' | 'saved' | 'error';
const WALLPAPER_CHOICES: { id: Settings['wallpaper']; label: string; swatch: string }[] = [
  ...WALLPAPERS,
  { id: 'custom', label: 'Custom', swatch: 'repeating-linear-gradient(45deg, #d9d5c9 0 6px, #ebe7db 6px 12px)' },
];
const ICON_STYLES: { id: NonNullable<Settings['iconStyle']>; label: string }[] = [{ id: 'circle', label: 'Circle' }, { id: 'squircle', label: 'Rounded' }, { id: 'outline', label: 'Outline' }, { id: 'solid', label: 'Solid' }];
const STATUS_TEXT: Record<Status, string> = {
  idle: 'Changes save automatically.',
  saving: 'Saving…',
  saved: 'All changes saved.',
  error: 'Couldn’t save. Your changes are kept on screen.',
};

export function SettingsScreen() {
  const { data, device, updateData, setHasPin, run, busy, notify } = usePhone();
  const settings = data.settings;
  const [status, setStatus] = useState<Status>('idle');
  const timer = useRef<number | undefined>(undefined);
  const [currentPin, setCurrentPin] = useState(''); const [pin, setPin] = useState(''); const [confirm, setConfirm] = useState('');
  const [pinOpen, setPinOpen] = useState(false);
  const blocked = useLoad(() => api('blocked', {}), []);

  // Changes show on the phone straight away and are saved once they settle, so dragging a
  // slider is one request, not dozens. An incomplete change (empty name, custom wallpaper
  // with no image yet) stays on screen and is saved when it becomes valid.
  const change = (patch: Partial<Settings>) => {
    const next = { ...settings, ...patch };
    updateData({ ...data, settings: next });
    if (!next.name.trim() || (next.wallpaper === 'custom' && !next.wallpaperUrl) || (next.phoneCase === 'custom' && !next.phoneCaseUrl)) return;
    window.clearTimeout(timer.current);
    setStatus('saving');
    timer.current = window.setTimeout(() => {
      api('settings', next).then(() => setStatus('saved')).catch(error => {
        setStatus('error');
        notify(error instanceof Error ? error.message : 'Could not save settings');
      });
    }, 500);
  };

  const resetPin = () => { setCurrentPin(''); setPin(''); setConfirm(''); setPinOpen(false); };
  const submitPin = (event: FormEvent) => {
    event.preventDefault();
    if (pin !== confirm) { notify('Those PINs don’t match. Try again.'); return; }
    void run(async () => {
      const result = await api('pin', { pin, currentPin });
      setHasPin(result.hasPin); resetPin();
      notify(device.hasPin ? 'PIN updated' : 'PIN protection enabled');
    });
  };
  const removePin = () => {
    if (!currentPin) { notify('Enter your current PIN to remove it.'); return; }
    void run(async () => {
      const result = await api('pin', { pin: '', currentPin });
      setHasPin(result.hasPin); resetPin();
      notify('PIN removed');
    });
  };

  const pinInput = (label: string, value: string, set: (value: string) => void, required = true) =>
    <label>{label}<input required={required} type="password" inputMode="numeric" pattern="[0-9]{4,8}" maxLength={8} autoComplete="off" value={value} onChange={event => set(event.target.value)} /></label>;

  return <>
    <div className="device-about"><span className="mini-device">N<span>◯</span></span><h2>{settings.name}</h2><p>{device.number}</p><small>NOTHING OS / 0.1</small></div>
    <p className="settings-status" role="status" aria-live="polite" data-status={status}>{STATUS_TEXT[status]}</p>

    <form className="panel form" onSubmit={submitPin} aria-label="Device security">
      <h3 className="settings-heading"><ShieldCheck size={17} />Device security<span className="settings-state">{device.hasPin ? 'ON' : 'OFF'}</span></h3>
      <p className="muted">{device.hasPin ? 'Your phone locks whenever you close it.' : 'Anyone holding this phone can open it.'}</p>
      {pinOpen ? <>
        {device.hasPin && pinInput('Current PIN', currentPin, setCurrentPin)}
        {pinInput(device.hasPin ? 'New PIN (4–8 digits)' : 'Set a PIN (4–8 digits)', pin, setPin)}
        {pinInput('Confirm PIN', confirm, setConfirm)}
        <button className="primary" disabled={busy}>{device.hasPin ? 'Change PIN' : 'Turn on PIN'}</button>
        {device.hasPin && <button type="button" className="text-button danger" disabled={busy} onClick={removePin}>Remove PIN</button>}
        <button type="button" className="text-button" onClick={resetPin}>Cancel</button>
      </> : <button type="button" className="primary" aria-expanded="false" onClick={() => setPinOpen(true)}>{device.hasPin ? 'Change or remove PIN' : 'Set a PIN'}</button>}
    </form>

    <section className="panel form" aria-label="Blocked numbers">
      <h3 className="settings-heading">Blocked numbers<span className="settings-state">{asList(blocked.value).length}</span></h3>
      <LoadState {...blocked} retry={blocked.refresh} />
      {!blocked.loading && !blocked.error && !asList(blocked.value).length && <p className="muted">You haven't blocked anyone. Block a number from the top of a chat.</p>}
      {asList<string>(blocked.value).map(number => <div className="blocked-row" key={number}><span>{data.contacts.find(c => c.number === number)?.name || number}<small>{number}</small></span><button type="button" className="text-button" disabled={busy} onClick={() => run(async () => { await api('setBlocked', { number, blocked: false }); blocked.refresh(); notify('Unblocked'); })}>Unblock</button></div>)}
    </section>

    <section className="panel form" aria-label="Do not disturb">
      <h3 className="settings-heading"><Moon size={17} />Do not disturb<span className="settings-state">{isQuiet(settings) ? 'ON' : 'OFF'}</span></h3>
      <div className="segments" role="group" aria-label="Do not disturb">
        {[false, true].map(on => <button type="button" key={String(on)} className={!!settings.dnd === on ? 'selected' : ''} aria-pressed={!!settings.dnd === on} onClick={() => change({ dnd: on })}>{on ? 'On' : 'Off'}</button>)}
      </div>
      <div className="quiet-hours">
        <label>Quiet from<input type="time" value={settings.dndFrom ?? ''} onChange={event => change({ dndFrom: event.target.value })} /></label>
        <label>Until<input type="time" value={settings.dndTo ?? ''} onChange={event => change({ dndTo: event.target.value })} /></label>
      </div>
      {(settings.dndFrom || settings.dndTo) && <button type="button" className="text-button" onClick={() => change({ dndFrom: '', dndTo: '' })}>Clear schedule</button>}
      <small className="muted">Alerts and ringtones stay silent. Notifications still collect in the shade, and calls still reach you. Set both times for a daily quiet window.</small>
    </section>

    <section className="panel form" aria-label="Appearance">
      <h3 className="settings-heading">Appearance</h3>
      <fieldset className="theme-choices settings-choices"><legend>Color theme</legend>
        {themes.map(theme => <button type="button" className="theme-choice" key={theme.id} aria-pressed={(settings.theme || 'qbcore') === theme.id} onClick={() => change({ theme: theme.id as Theme })}><span className="theme-swatch" style={{ background: themeChip(theme) }} />{theme.label}</button>)}
      </fieldset>
      <fieldset className="theme-choices settings-choices"><legend>Wallpaper</legend>
        {WALLPAPER_CHOICES.map(item => <button type="button" className="theme-choice" key={item.id} aria-pressed={settings.wallpaper === item.id} onClick={() => change({ wallpaper: item.id })}><span className="theme-swatch" style={{ background: item.swatch }} />{item.label}</button>)}
      </fieldset>
      {settings.wallpaper === 'custom' && <ImagePicker label="Wallpaper" value={settings.wallpaperUrl || ''} onChange={wallpaperUrl => change({ wallpaperUrl })} photos={data.photos} />}
      <div><span className="settings-label">Icon style</span>
        <div className="segments" role="group" aria-label="Icon style">
          {ICON_STYLES.map(item => <button type="button" key={item.id} className={(settings.iconStyle ?? 'circle') === item.id ? 'selected' : ''} aria-pressed={(settings.iconStyle ?? 'circle') === item.id} onClick={() => change({ iconStyle: item.id })}>{item.label}</button>)}
        </div>
      </div>
      <div><span className="settings-label">Phone style</span>
        <div className="segments" role="group" aria-label="Phone style">
          {(['classic', 'flip'] as const).map(style => <button type="button" key={style} className={(settings.phoneStyle || 'classic') === style ? 'selected' : ''} aria-pressed={(settings.phoneStyle || 'classic') === style} onClick={() => change({ phoneStyle: style })}>{style === 'classic' ? 'Classic' : 'Flip'}</button>)}
        </div>
        <small className="muted">Flip is taller, folds closed and has a cover screen.</small>
      </div>
    </section>

    {settings.phoneStyle === 'flip' && <section className="panel form" aria-label="Phone case">
      <h3 className="settings-heading">Flip phone case</h3>
      <fieldset className="cover-choices"><legend>Case</legend>
        {PHONE_CASES.map(item => <button type="button" className="cover-choice" key={item.id} aria-pressed={(settings.phoneCase ?? 'default') === item.id} onClick={() => change({ phoneCase: item.id })}><span className="cover-thumb">{item.id === 'default' || item.id === 'custom' ? <i className={`cover-thumb-${item.id}`} /> : <CoverScene id={item.id} />}</span>{item.label}</button>)}
      </fieldset>
      {settings.phoneCase === 'custom' && <ImagePicker label="Case photo" value={settings.phoneCaseUrl || ''} onChange={phoneCaseUrl => change({ phoneCaseUrl })} photos={data.photos} />}
          <small className="muted">Decorates the back of the phone when it's folded closed.</small>
    </section>}

    <section className="panel form" aria-label="Device">
      <h3 className="settings-heading">Device</h3>
      <label>Device name<input required maxLength={32} value={settings.name} onChange={event => change({ name: event.target.value })} /></label>
      <label>Sound volume <span>{Math.round(settings.volume * 100)}%</span><input type="range" min="0" max="1" step="0.05" value={settings.volume} onChange={event => change({ volume: Number(event.target.value) })} /></label>
      <label>Phone size <span>{Math.round(settings.scale * 100)}%</span><input type="range" min="0.75" max="1.15" step="0.05" value={settings.scale} onChange={event => change({ scale: Number(event.target.value) })} /></label>
    </section>

    <p className="settings-footnote">Your number and personal content belong to this device. Phone style is the frame; theme is the color. Banking, property, and vehicles use your current character.</p>
  </>;
}
