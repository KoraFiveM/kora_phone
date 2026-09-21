import { useEffect, useRef, useState } from 'react';
import { AlarmClock, Music, Pause, Pencil, Plus, Save, Trash2 } from 'lucide-react';
import { api, requestId } from './api';
import { DotClock, Empty, Row } from './components';
import { usePhone } from './PhoneContext';
import type { Alarm, Station } from './types';

const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
type Player = { kind: 'youtube'; id: string } | { kind: 'soundcloud' } | { kind: 'audio' };
function parseStation(url: string): Player {
  const youtube = url.match(/(?:youtube\.com\/(?:watch\?v=|shorts\/|embed\/)|youtu\.be\/)([\w-]{11})/);
  if (youtube) return { kind: 'youtube', id: youtube[1] };
  if (/soundcloud\.com\//.test(url)) return { kind: 'soundcloud' };
  return { kind: 'audio' };
}
export function MusicScreen() {
  const { data, updateData, run, busy } = usePhone();
  const [draft, setDraft] = useState<Station>();
  const [playing, setPlaying] = useState<Station>();
  const audioRef = useRef<HTMLAudioElement>(null);
  useEffect(() => { if (audioRef.current) audioRef.current.volume = data.settings.volume; }, [data.settings.volume, playing]);
  const remove = (station: Station) => run(async () => { updateData(await api('stations', { ...station, remove: true })); if (playing?.id === station.id) setPlaying(undefined); });
  if (draft) return <form className="form" onSubmit={e => { e.preventDefault(); run(async () => { updateData(await api('stations', draft)); setDraft(undefined); }); }}>
    <button type="button" className="text-button" onClick={() => setDraft(undefined)}>← All stations</button>
    <label>Name<input required maxLength={60} value={draft.label} onChange={e => setDraft({ ...draft, label: e.target.value })} /></label>
    <label>Stream URL<input required type="url" placeholder="https://…" value={draft.url} onChange={e => setDraft({ ...draft, url: e.target.value })} /></label>
    <p className="muted">YouTube links, SoundCloud links, and direct HTTPS audio stream URLs are all supported.</p>
    <button className="primary" disabled={busy}><Save size={17} />Save station</button>
  </form>;
  const player = playing && parseStation(playing.url);
  return <>
    {playing && player && <div className="panel now-playing">
      <div className="section-heading"><span className="section-label">NOW PLAYING</span><button className="icon-button" aria-label="Stop playback" onClick={() => setPlaying(undefined)}><Pause size={18} /></button></div>
      <h3>{playing.label}</h3>
      {player.kind === 'youtube' && <iframe className="media-embed" src={`https://www.youtube-nocookie.com/embed/${player.id}?autoplay=1&rel=0`} title={playing.label} allow="autoplay; encrypted-media" />}
      {player.kind === 'soundcloud' && <iframe className="media-embed" src={`https://w.soundcloud.com/player/?url=${encodeURIComponent(playing.url)}&auto_play=true&color=%23d53c2f&visual=false`} title={playing.label} allow="autoplay" />}
      {player.kind === 'audio' && <audio ref={audioRef} className="media-embed" autoPlay controls src={playing.url} />}
    </div>}
    <button className="primary" onClick={() => setDraft({ id: requestId(), label: '', url: '' })}><Plus size={18} />Add station</button>
    {data.stations.map(station => <article className="note-card" key={station.id}>
      <button onClick={() => setPlaying(station)}><Music size={18} /><h3>{station.label}</h3><p>{station.url}</p></button>
      <button className="icon-button" aria-label={`Delete ${station.label}`} disabled={busy} onClick={() => remove(station)}><Trash2 size={16} /></button>
    </article>)}
    {!data.stations.length && <Empty title="Something to listen to" detail="Save a YouTube, SoundCloud, or direct stream link to play it here." />}
  </>;
}
/** Three quick beeps. Silent (and harmless) if the browser has not been allowed to play audio yet. */
export function alarmTone() {
  try {
    const context = new AudioContext();
    void context.resume();
    [0, 350, 700].forEach(delay => setTimeout(() => {
      const oscillator = context.createOscillator(); const gain = context.createGain();
      oscillator.type = 'sine'; oscillator.frequency.value = 880;
      gain.gain.setValueAtTime(0, context.currentTime); gain.gain.linearRampToValueAtTime(0.12, context.currentTime + 0.02); gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.3);
      oscillator.connect(gain); gain.connect(context.destination); oscillator.start(); oscillator.stop(context.currentTime + 0.32);
    }, delay));
    setTimeout(() => context.close(), 1200);
  } catch { /* Audio unavailable in this context. */ }
}
const daysLabel = (days: number[]) => days.length === 7 ? 'Every day' : days.length ? [...days].sort().map(d => DAY_LABELS[d]).join(' ') : 'Once';
export function ClockScreen() {
  const { data, updateData, run, busy } = usePhone();
  const [now, setNow] = useState(new Date());
  const [draft, setDraft] = useState<Alarm>();
  useEffect(() => { const timer = setInterval(() => setNow(new Date()), 1000); return () => clearInterval(timer); }, []);
  const toggleDay = (day: number) => setDraft(d => d && { ...d, days: d.days.includes(day) ? d.days.filter(x => x !== day) : [...d.days, day].sort() });
  const save = (alarm: Alarm) => run(async () => { updateData(await api('alarms', alarm)); setDraft(undefined); });
  const remove = (alarm: Alarm) => run(async () => updateData(await api('alarms', { ...alarm, remove: true })));
  if (draft) return <form className="form" onSubmit={e => { e.preventDefault(); save(draft); }}>
    <button type="button" className="text-button" onClick={() => setDraft(undefined)}>← All alarms</button>
    <label>Label<input maxLength={60} placeholder="Wake up" value={draft.label} onChange={e => setDraft({ ...draft, label: e.target.value })} /></label>
    <label>Time<input required type="time" value={draft.time} onChange={e => setDraft({ ...draft, time: e.target.value })} /></label>
    <fieldset className="theme-choices"><legend>Repeat</legend>{DAY_LABELS.map((label, day) => <button type="button" key={day} className="theme-choice" aria-pressed={draft.days.includes(day)} onClick={() => toggleDay(day)}>{label}</button>)}</fieldset>
    <p className="muted">{draft.days.length ? 'Repeats on the selected days.' : 'Leave every day unchecked to ring once, the next time this clock matches.'}</p>
    <button className="primary" disabled={busy}><Save size={17} />Save alarm</button>
  </form>;
  return <>
    <div className="weather-screen"><p className="section-label">RIGHT NOW</p><DotClock value={`${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`} /></div>
    <button className="primary" onClick={() => setDraft({ id: requestId(), label: '', time: '08:00', days: [], enabled: true })}><Plus size={18} />Add alarm</button>
    {data.alarms.map(alarm => <Row key={alarm.id} title={alarm.time} detail={`${alarm.label || 'Untitled'} · ${daysLabel(alarm.days)}`} icon={<AlarmClock size={18} />}
      end={<span className="alarm-row-actions">
        <button className={alarm.enabled ? 'primary' : 'text-button'} disabled={busy} onClick={() => save({ ...alarm, enabled: !alarm.enabled })}>{alarm.enabled ? 'On' : 'Off'}</button>
        <button className="icon-button" aria-label={`Edit alarm ${alarm.label}`} disabled={busy} onClick={() => setDraft({ ...alarm })}><Pencil size={16} /></button>
        <button className="icon-button" aria-label={`Delete alarm ${alarm.label}`} disabled={busy} onClick={() => remove(alarm)}><Trash2 size={16} /></button>
      </span>} />)}
    {!data.alarms.length && <Empty title="Set a reminder" detail="Alarms ring on your local clock, even with the phone closed. An alarm with no repeat days rings once." />}
  </>;
}
