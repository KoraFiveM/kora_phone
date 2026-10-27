import { useEffect, useRef, useState } from 'react';
import { ArrowLeft, ArrowRight, Check, ShieldCheck, Signal } from 'lucide-react';
import { handsetIdentity, resolveHandsetTheme, themeOptions } from './themes';
import type { Theme } from './themes';
import { api } from './api';
import { recall, remember } from './lastScreen';
import { usePhone } from './PhoneContext';
import './setup.css';

type Step = 'number' | 'name' | 'theme' | 'wallpaper' | 'security' | 'done';
const STEPS: Step[] = ['number', 'name', 'theme', 'wallpaper', 'security', 'done'];
const COPY: Record<Step, [string, string, string]> = {
  number: ['01 / CONNECTION', 'Hello.\nStart here.', 'A new phone. Your own little corner of the world.'],
  name: ['02 / IDENTITY', 'Make a\nname for it.', 'Something familiar. Something that feels like yours.'],
  theme: ['03 / COLOUR', 'Find your\nkind of colour.', 'Set the mood. See your choice come to life.'],
  wallpaper: ['04 / BACKDROP', 'A change\nof scenery.', 'Choose the view you’ll come back to.'],
  security: ['05 / PRIVACY', 'Just\nfor you.', 'A little protection for your personal world.'],
  done: ['06 / READY', 'Nothing else.\nYou’re ready.', 'Your phone, with your own point of view.'],
};
export const WALLPAPERS = [
  { id: 'qbcore', label: 'Signature', swatch: '#30363c' },
  { id: 'orbit', label: 'Orbit', swatch: 'radial-gradient(circle at 28% 35%, #8b96a8 0 14%, transparent 14.5%), radial-gradient(circle at 76% 70%, #ac7150 0 22%, transparent 22.5%), #dfd9cc' },
  { id: 'plain', label: 'Plain', swatch: '#e3e0d6' },
  { id: 'midnight', label: 'Midnight', swatch: 'linear-gradient(155deg, #293e66, #090e1c)' },
  { id: 'slate', label: 'Slate', swatch: 'linear-gradient(145deg, #e0e3e8, #87919f)' },
  { id: 'ember', label: 'Ember', swatch: 'radial-gradient(ellipse at bottom right, #a95731, #241914 75%)' },
] as const;
type Wallpaper = typeof WALLPAPERS[number]['id'];

export function SetupScreen() {
  const { data, updateData, run, busy, device, setHasPin } = usePhone();
  const [step, setStep] = useState<Step>(() => STEPS.find(item => item === recall('setupStep')) ?? 'number');
  const [name, setName] = useState(data.settings.name || '');
  const [theme, setTheme] = useState<Theme>(resolveHandsetTheme(device.model || 'standard',data.settings.theme).id);
  const phoneStyle = device.model || 'standard';
  const [wallpaper, setWallpaper] = useState<Wallpaper>(data.settings.wallpaper === 'custom' ? 'qbcore' : data.settings.wallpaper || 'qbcore');
  const [pin, setPin] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState('');
  const heading = useRef<HTMLHeadingElement>(null);
  const index = STEPS.indexOf(step);
  const palette = resolveHandsetTheme(device.model || 'standard',theme);
  const backdrop = WALLPAPERS.find(item => item.id === wallpaper)!;
  useEffect(() => { heading.current?.focus(); remember('setupStep', step); }, [step]);
  const go = (next: Step) => { if (!busy) { setError(''); setStep(next); } };
  const save = (protect: boolean, complete: boolean) => run(async () => {
    setError('');
    if (protect && !device.hasPin) {
      if (!/^[0-9]{4,8}$/.test(pin)) { setError('Use 4–8 digits for your PIN.'); return; }
      if (pin !== confirm) { setError('Those PINs don’t match. Try again.'); return; }
    }
    try {
      if (protect && !device.hasPin) {
        const result = await api('pin', { currentPin: '', pin });
        setHasPin(result.hasPin); setPin(''); setConfirm('');
      }
      updateData(await api('settings', { ...data.settings, name: name.trim(), theme, phoneStyle, wallpaper, setupComplete: complete }));
      if (!complete) setStep('done');
    } catch (cause) { setError(cause instanceof Error ? cause.message : 'Couldn’t save your setup. Please try again.'); }
  });
  const submit = () => {
    if (busy) return;
    if (step === 'name' && !name.trim()) return;
    if (step === 'security') { void save(true, false); return; }
    if (step === 'done') { void save(false, true); return; }
    go(STEPS[index + 1]);
  };
  const preview = (scene: boolean) => <div className={`onboard-preview ${scene ? 'scene' : ''}`} style={{ background: scene ? wallpaper === 'qbcore' ? palette.wallpaper : wallpaper === 'plain' ? palette.bg : backdrop.swatch : palette.bg, color: scene ? (wallpaper === 'midnight' || wallpaper === 'ember' || wallpaper === 'qbcore' ? '#fff' : '#242424') : palette.dark ? '#fff' : '#242424' }} aria-label={`${scene ? backdrop.label : palette.label} preview`}>
    <span className="onboard-preview-label">{scene ? 'YOUR DAILY VIEW' : handsetIdentity(device.model || 'standard').os}</span>
    <span className="onboard-clock">09:41<span>Tuesday, 8 September</span></span>
    {scene ? <span className="onboard-preview-pill">A little room to breathe.</span> : <div className="onboard-preview-widgets"><span><Signal size={18} />Connected</span><span className="onboard-app-dots"><i /><i /><i /><i /></span></div>}
  </div>;

  return <section className="onboard" aria-label="Phone setup">
    <header className="onboard-top"><span>{device.model === 'flip' ? 'CIRCUIT FLIP' : device.model === 'fold' ? 'ATLAS FOLD' : 'ORCHARD ONE'}</span><span>PHONE / SETUP</span></header>
    <div className="onboard-progress" role="progressbar" aria-label="Setup progress" aria-valuemin={1} aria-valuemax={STEPS.length} aria-valuenow={index + 1}>{STEPS.map((id, i) => <i key={id} className={i <= index ? 'filled' : ''} />)}</div>
    <form className="onboard-form" onSubmit={event => { event.preventDefault(); submit(); }}>
      <div className="onboard-body" key={step}>
        <div className="onboard-heading"><span className="onboard-kicker"><i />{COPY[step][0]}</span><h1 ref={heading} tabIndex={-1}>{COPY[step][1]}</h1><p>{COPY[step][2]}</p></div>
        {step === 'number' && <>
          <div className="onboard-orbit" aria-hidden="true"><div /><span>n<span>●</span></span><i /></div>
          <div className="onboard-number"><span>YOUR PHONE NUMBER<Signal size={15} /></span><strong>{device.number || 'No SIM inserted'}</strong><small>{device.number ? 'Ready for your first hello.' : 'You can insert a SIM after setup.'}</small></div>
        </>}
        {step === 'name' && <>
          <div className="onboard-identity" aria-hidden="true"><span>HELLO, MY NAME IS</span><strong>{name.trim() || 'Your Nothing.'}</strong><small>ONE OF A KIND / 001</small></div>
          <label className="onboard-field">Phone name<input required maxLength={32} value={name} onChange={event => setName(event.target.value)} placeholder="My Nothing Phone" autoComplete="off" /></label>
          <div className="onboard-field-note"><span>You can change this later.</span><span>{name.length}/32</span></div>
        </>}
        {step === 'theme' && <>{preview(false)}<fieldset className="onboard-colours"><legend>Choose a colour</legend>{themeOptions(device.model || 'standard').map(item => <button type="button" key={item.id} disabled={busy} aria-pressed={theme === item.id} onClick={() => setTheme(item.id)}><span style={{ background: item.color, color: item.dark ? '#fff' : '#222' }}>{theme === item.id && <Check size={18} />}</span>{item.label}</button>)}</fieldset></>}
        {step === 'wallpaper' && <>{preview(true)}<fieldset className="onboard-wallpapers"><legend>Choose a wallpaper</legend>{WALLPAPERS.map(item => <button type="button" key={item.id} disabled={busy} aria-pressed={wallpaper === item.id} onClick={() => setWallpaper(item.id)}><span style={{ background: item.id === 'qbcore' ? palette.wallpaper : item.id === 'plain' ? palette.bg : item.swatch }}>{wallpaper === item.id && <i><Check size={13} /></i>}</span>{item.label}</button>)}</fieldset></>}
        {step === 'security' && <>
          <div className="onboard-security"><ShieldCheck size={32} strokeWidth={1.3} /><div><strong>{device.hasPin ? 'You’re protected.' : 'A PIN. Peace of mind.'}</strong><span>{device.hasPin ? 'Your existing PIN is ready to use.' : 'Only you should have the key.'}</span></div></div>
          {!device.hasPin && <><label className="onboard-field">Create a PIN<input type="password" inputMode="numeric" pattern="[0-9]{4,8}" minLength={4} maxLength={8} required autoComplete="new-password" placeholder="4–8 digits" value={pin} onChange={event => { setPin(event.target.value); setError(''); }} /></label><label className="onboard-field">Confirm your PIN<input type="password" inputMode="numeric" pattern="[0-9]{4,8}" minLength={4} maxLength={8} required autoComplete="new-password" placeholder="One more time" value={confirm} onChange={event => { setConfirm(event.target.value); setError(''); }} /></label><p className="onboard-note">Keep it memorable. Keep it to yourself.</p></>}
        </>}
        {step === 'done' && <>
          <div className="onboard-ready" aria-hidden="true"><Check size={52} strokeWidth={1.2} /><span>ALL SYSTEMS GO</span></div>
          <dl className="onboard-summary"><div><dt>Phone</dt><dd>{name.trim()}</dd></div><div><dt>Number</dt><dd>{device.number || 'No SIM'}</dd></div><div><dt>Model</dt><dd>{phoneStyle === 'flip' ? 'Circuit Flip' : phoneStyle === 'fold' ? 'Atlas Fold' : 'Orchard One'}</dd></div><div><dt>Appearance</dt><dd>{palette.label} / {backdrop.label}</dd></div><div><dt>Security</dt><dd>{device.hasPin ? 'PIN protected' : 'No PIN set'}</dd></div></dl>
        </>}
      </div>
      <footer className="onboard-footer">
        {error && <p className="onboard-error" role="alert">{error}</p>}
        <div className="onboard-actions">{index > 0 && <button className="onboard-back" type="button" disabled={busy} aria-label="Previous step" onClick={() => go(STEPS[index - 1])}><ArrowLeft size={19} /></button>}<button className="onboard-next" type="submit" disabled={busy || (step === 'name' && !name.trim())}>{busy ? 'Saving…' : step === 'done' ? 'Meet your phone' : step === 'number' ? 'Let’s begin' : step === 'security' && !device.hasPin ? 'Save PIN' : 'Continue'}<ArrowRight size={19} /></button></div>
        {step === 'security' && !device.hasPin ? <button type="button" className="onboard-skip" disabled={busy} onClick={() => void save(false, false)}>Set up later</button> : <span className="onboard-footer-note">{step === 'done' ? 'MADE YOURS.' : 'A FEW SMALL STEPS. ALL YOURS.'}</span>}
      </footer>
    </form>
  </section>;
}
