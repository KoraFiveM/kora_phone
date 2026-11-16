import { ArrowRight, Fingerprint, LockKeyhole, PhoneIncoming, Smartphone } from 'lucide-react';
import type { FormEvent } from 'react';
import { api, nui } from '../api';
import { DotClock } from '../components';
import { usePhoneStore } from './storeContext';

type Reply = { ok: boolean; error?: string | { message?: string } };

export function LockScreen() {
  const { state, dispatch, actions, view } = usePhoneStore();
  const { device, call, busy, pin, lockError } = state;
  const { model, time, date, brand } = view;
  if (!device) return null;
  const ringing = call && ['ringing', 'active'].includes(call.status) ? call : undefined;
  const patch = (value: Partial<typeof state>) => dispatch({ type: 'patch', patch: value });

  const unlock = (event: FormEvent) => {
    event.preventDefault();
    void actions.run(async () => {
      try { const value = await api('unlock', { pin }); patch({ device: value, pin: '', lockError: '' }); }
      catch (e) { patch({ lockError: (e as Error).message, pin: '' }); }
    });
  };
  const faceUnlock = () => void actions.run(async () => {
    const response = await nui<Reply>('handset:action', { op: 'faceUnlock' });
    if (!response.ok) throw new Error(typeof response.error === 'string' ? response.error : response.error?.message || 'Face ID did not recognise you');
    await actions.reloadHandset();
  });

  return <div className="lock-screen"><LockKeyhole size={19} /><p>{date.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })}</p><div className={`handset-clock ${model === 'standard' ? 'nothing-clock' : ''}`} aria-label={model === 'standard' ? undefined : time}>{model === 'standard' ? <DotClock value={time} /> : time}</div><div className="handset-lock-brand"><Smartphone size={34} strokeWidth={1} /><span>{brand}</span></div>{ringing && <div className="locked-call"><PhoneIncoming size={19} /><div><strong>Incoming call</strong><small>{ringing.number} · Unlock to answer</small></div></div>}<form onSubmit={unlock} className="unlock-form">{device.hasPin && <input autoFocus type="password" aria-label="Phone PIN" inputMode="numeric" pattern="[0-9]{4,8}" maxLength={8} required placeholder="Enter PIN" autoComplete="off" value={pin} onChange={e => patch({ pin: e.target.value })} />}{lockError && <p className="pin-error" role="alert">{lockError}</p>}<button className="unlock-button" disabled={busy}><Fingerprint size={28} /><span>{device.hasPin ? 'Unlock phone' : 'Make yourself at home'}</span><ArrowRight size={17} /></button></form><button type="button" className="face-unlock" disabled={busy} onClick={faceUnlock}><Fingerprint size={18} />Use Face ID</button><small className="lock-bottom">{brand} / YOUR WORLD, CONNECTED</small></div>;
}
