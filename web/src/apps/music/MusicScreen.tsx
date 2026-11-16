import { Music,Pause,Plus,Save,Trash2 } from 'lucide-react';
import { useEffect,useRef,useState } from 'react';
import { api,requestId } from '../../api';
import { Empty } from '../../components';
import { usePhone } from '../../core/PhoneContext';
import type { Station } from '../../types';


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
