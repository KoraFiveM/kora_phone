import { useEffect } from 'react';
import { api, isDemo, isEmbed, demoModel, isPreview, nui } from '../api';
import { alarmTone } from '../apps/clock/ClockScreen';
import { recall, remember } from '../lastScreen';
import { currentAppId } from './phoneState';
import type { Alarm } from '../types';
import type { PhoneStore } from './storeContext';

/** Timers and persistence that must keep running whether or not a screen is mounted. */
export function useBackgroundEffects({ state, dispatch, refs, video, actions, view }: PhoneStore) {
  const { device, call, alert, toast, notifications, earlier, shown } = state;
  const app = currentAppId(state.app, state.target);
  const { data, quiet, date, flip } = view;
  const { stopVideo, gameVideo, localVideoRef, remoteVideoRef, localStream, remoteStream } = video;
  const { markRead, updateData, choosePreviewModel } = actions;
  const { dnd, dndFrom, dndTo } = data.settings;

  // The phone screen is unmounted while closed, so the last-known Do Not Disturb setting lives in a ref (and storage).
  useEffect(() => {
    if (!device) return;
    refs.quietConfig.current = { dnd, dndFrom, dndTo };
    remember('quiet', JSON.stringify(refs.quietConfig.current));
  }, [device, dnd, dndFrom, dndTo, refs]);
  useEffect(() => { void nui('quiet', { quiet }); }, [quiet]);
  useEffect(() => { remember('notifications', JSON.stringify({ a: notifications, e: earlier })); }, [notifications, earlier]);
  useEffect(() => { remember('app', app); }, [app]);

  // A different handset never inherits the previous one's notifications.
  useEffect(() => {
    if (!device?.id) return;
    const id = device.id;
    dispatch({ type: 'patch', patch: {
      notifications: notifications.filter(item => item.deviceId === id),
      earlier: earlier.filter(item => item.deviceId === id),
      alert: alert?.deviceId === id ? alert : undefined,
    } });
    // Only a handset swap re-filters; the lists themselves change through their own actions.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [device?.id]);

  useEffect(() => { if (device) refs.contactNames.current = new Map(data.contacts.map(c => [c.number, c.name])); }, [device, data.contacts, refs]);

  // Alarms are checked here, not inside the Clock screen, so they still ring with the phone closed.
  useEffect(() => { if (!device) return; refs.alarms.current = data.alarms; remember('alarms', JSON.stringify(data.alarms)); }, [device, data.alarms, refs]);
  useEffect(() => {
    const at = `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
    for (const alarm of refs.alarms.current) {
      if (!alarm.enabled || alarm.time !== at || (alarm.days.length && !alarm.days.includes(date.getDay()))) continue;
      const key = `${alarm.id}-${date.toDateString()}-${at}`;
      if (refs.firedAlarms.current.has(key)) continue;
      refs.firedAlarms.current.add(key);
      window.dispatchEvent(new MessageEvent('message', { data: { type: 'notification', data: { title: 'Alarm', body: alarm.label || 'Untitled', app: 'clock', urgent: true } } }));
      alarmTone(); void nui('alarm', { label: alarm.label });
      if (!alarm.days.length) {
        // A one-time alarm turns itself off after ringing.
        refs.alarms.current = refs.alarms.current.map(a => a.id === alarm.id ? { ...a, enabled: false } : a);
        void api('alarms', { ...alarm, enabled: false }).then(value => { if (device) updateData(value); }).catch(() => undefined);
      }
    }
    // Runs once a second with the clock; the handlers read everything else through refs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [date]);

  // Being in an app means you've seen its notifications.
  useEffect(() => {
    if (!shown || app === 'home') return;
    const seen = notifications.filter(n => (n.app as string) === app || (app === 'social' && (n.app as string) === 'messages'));
    if (seen.length) markRead(seen);
  }, [app, shown, notifications, markRead]);

  // Call video follows the call.
  useEffect(() => { if (call?.status !== 'active') stopVideo(); }, [call?.id, call?.status, stopVideo]);
  useEffect(() => { gameVideo.current?.setPaused(flip && state.folded); }, [flip, state.folded, state.video.on, gameVideo]);
  useEffect(() => {
    if (localVideoRef.current) localVideoRef.current.srcObject = localStream.current || null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = remoteStream.current || null;
  }, [state.video.on, state.video.remote, state.folded, localVideoRef, remoteVideoRef, localStream, remoteStream]);
  useEffect(() => () => { gameVideo.current?.stop(); refs.coverAudio.current?.pause(); }, [gameVideo, refs]);

  // Self-clearing banners and the call-ended screen.
  useEffect(() => { if (!alert) return; const timer = setTimeout(() => dispatch({ type: 'patch', patch: { alert: undefined } }), 4000); return () => clearTimeout(timer); }, [alert, dispatch]);
  useEffect(() => { if (!toast) return; const timer = setTimeout(() => dispatch({ type: 'patch', patch: { toast: '' } }), 5000); return () => clearTimeout(timer); }, [toast, dispatch]);
  useEffect(() => {
    if (!call || call.status === 'active' || call.status === 'ringing') return;
    const timer = setTimeout(() => dispatch({ type: 'patch', patch: { call: undefined } }), 3000);
    return () => clearTimeout(timer);
  }, [call, dispatch]);

  // Incoming ring: a short tone every 1.8 seconds.
  useEffect(() => {
    const volume = call?.volume ?? data.settings.volume;
    const beep = () => {
      const context = refs.audio.current;
      if (!context || context.state !== 'running' || quiet || volume === 0) return;
      const oscillator = context.createOscillator(); const gain = context.createGain();
      oscillator.type = 'sine'; oscillator.frequency.value = 740;
      gain.gain.setValueAtTime(0, context.currentTime); gain.gain.linearRampToValueAtTime(volume * 0.09, context.currentTime + 0.02); gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.35);
      oscillator.connect(gain); gain.connect(context.destination); oscillator.start(); oscillator.stop(context.currentTime + 0.4);
    };
    if (call?.status !== 'ringing' || call.direction !== 'incoming') return;
    beep(); const timer = setInterval(beep, 1800); return () => clearInterval(timer);
  }, [call?.status, call?.direction, call?.volume, data.settings.volume, quiet, refs]);

  // The NUI page loads immediately at resource start, but the client script can still be
  // mid-registration at that exact moment, so retry the handshake instead of failing once.
  useEffect(() => {
    if (isPreview) return;
    let cancelled = false;
    void (async () => {
      let lastError: unknown;
      for (let attempt = 0; attempt < 20 && !cancelled; attempt++) {
        try { await nui('phone:ready'); return; } catch (error) { lastError = error; await new Promise(resolve => setTimeout(resolve, 500)); }
      }
      if (!cancelled) console.error('[kora_phone] UI handshake failed after multiple attempts', lastError);
    })();
    return () => { cancelled = true; };
  }, []);

  // Browser demo: start on the handset named in the URL.
  useEffect(() => {
    if (!isDemo) return;
    choosePreviewModel(isEmbed ? 'fold' : demoModel);
    dispatch({ type: 'patch', patch: { folded: false } });
  }, [choosePreviewModel, dispatch]);
}

/** Last-known alarms, restored before the first render so a closed phone can still ring. */
export function storedAlarms(): Alarm[] {
  try { const value = JSON.parse(recall('alarms') ?? '[]'); return Array.isArray(value) ? value : []; } catch { return []; }
}
