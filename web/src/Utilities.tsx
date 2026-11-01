import { useEffect, useRef, useState } from 'react';
import { Camera, Car, CloudSun, Home, MapPin, Navigation, Plus, Save, ShieldCheck, StickyNote, Sun, Trash2 } from 'lucide-react';
import { api, isPreview, requestId } from './api';
import { PhotoImage } from './Images';
import type { Photo } from './types';
import { asList } from './types';
import type { MapBlip, Note, Property, Vehicle } from './types';
import { calculate, DotClock, Empty, Row } from './components';
import { LoadState, useLoad, usePhone } from './PhoneContext';

export function NotesScreen() {
  const { data, updateData, run, busy } = usePhone();
  const [draft, setDraft] = useState<Note>();
  return <>{draft ? <form className="form" onSubmit={e => { e.preventDefault(); run(async () => { updateData(await api('notes', draft)); setDraft(undefined); }); }}><button type="button" className="text-button" onClick={() => setDraft(undefined)}>← All notes</button><label>Title<input required maxLength={100} value={draft.title} onChange={e => setDraft({ ...draft, title: e.target.value })} /></label><textarea className="note-editor" aria-label="Note body" required maxLength={4000} value={draft.body} placeholder="A thought worth keeping…" onChange={e => setDraft({ ...draft, body: e.target.value })} /><button className="primary" disabled={busy}><Save size={17} />Save note</button></form> : <><button className="primary" onClick={() => setDraft({ id: requestId(), title: '', body: '' })}><Plus size={18} />New note</button>{data.notes.map(note => <article className="note-card" key={note.id}><button onClick={() => setDraft({ ...note })}><StickyNote size={18} /><h3>{note.title}</h3><p>{note.body}</p></button><button className="icon-button" aria-label={`Delete note ${note.title}`} disabled={busy} onClick={() => run(async () => updateData(await api('notes', { ...note, remove: true })))}><Trash2 size={16} /></button></article>)}{!data.notes.length && <Empty title="Space to think" detail="Keep your plans, ideas, and little reminders here." />}</>}</>;
}
function GalleryItem({ item, controls = false }: { item: Photo; controls?: boolean }) {
  return item.kind === 'video' ? <video src={item.url} controls={controls} muted={!controls} playsInline preload="metadata" aria-label={controls ? 'Saved phone video' : 'Video thumbnail'} /> : <PhotoImage src={item.url} alt={controls ? 'Saved phone photograph' : 'Gallery thumbnail'} />;
}
export function GalleryScreen() {
  const { data, updateData, run, busy, device, navigate } = usePhone();
  const [selected, setSelected] = useState<string>();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const photo = data.photos.find(item => item.id === selected);
  return <>{photo ? <div className="photo-view"><button className="text-button" onClick={() => { setSelected(undefined); setConfirmDelete(false); }}>← All photos</button><GalleryItem item={photo} controls /><button className="text-button danger" onClick={() => setConfirmDelete(true)}><Trash2 size={16} />Delete photo</button>{confirmDelete && <div className="panel"><p>Remove this item from the phone gallery?</p><button className="primary" disabled={busy} onClick={() => run(async () => { updateData(await api('deletePhoto', { id: photo.id })); setSelected(undefined); setConfirmDelete(false); })}>Delete from gallery</button><button className="text-button" onClick={() => setConfirmDelete(false)}>Cancel</button></div>}</div> : <><div className="section-heading"><span className="section-label">YOUR MOMENTS / {data.photos.length}</span>{device.capabilities.camera && <button className="icon-button" aria-label="Open camera" onClick={() => navigate('camera')}><Camera size={20} /></button>}</div><div className="gallery-grid">{data.photos.map(item => <button key={item.id} onClick={() => setSelected(item.id)} aria-label="View photo"><GalleryItem item={item} /></button>)}</div>{!data.photos.length && <Empty title="Collect a moment" detail={device.capabilities.camera ? 'Photos and videos you take will appear here.' : 'Camera uploads have not been configured on this server.'} />}</>}</>;
}
// Calibration knob: World coords at the edges of web/public/map.jpg (road style, stitched from
// zoom-5 tiles, cropped square to the island). Checked against the Del Perro pier
// and LSIA terminal. Swap the image for another render and these four numbers need re-fitting.
const MAP_BOUNDS = { left: -5879, right: 7243, top: 8567, bottom: -4555 };
export const worldToMap = (x: number, y: number) => ({ u: (x - MAP_BOUNDS.left) / (MAP_BOUNDS.right - MAP_BOUNDS.left), v: (MAP_BOUNDS.top - y) / (MAP_BOUNDS.top - MAP_BOUNDS.bottom) });
export const mapToWorld = (u: number, v: number) => ({ x: MAP_BOUNDS.left + u * (MAP_BOUNDS.right - MAP_BOUNDS.left), y: MAP_BOUNDS.top - v * (MAP_BOUNDS.top - MAP_BOUNDS.bottom) });
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

// Drag to pan, scroll or +/- to zoom, tap to drop a waypoint. The image is sized to the box width at zoom 1.
function LiveMap({ onPick }: { onPick: (x: number, y: number) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const drag = useRef<{ sx: number; sy: number; vx: number; vy: number; moved: boolean }>(undefined);
  const [view, setView] = useState({ x: 0, y: 0, z: 1 });
  const [me, setMe] = useState<{ x: number; y: number; heading?: number }>();
  // Mirrors the game's own waypoint, so it survives leaving the app and shows ones set from the pause map.
  const [pin, setPin] = useState<{ x: number; y: number }>();
  const [blips, setBlips] = useState<MapBlip[]>([]);
  const [missing, setMissing] = useState(false);
  const fit = (x: number, y: number, z: number) => {
    const el = box.current; if (!el) return { x, y, z };
    const size = el.clientWidth * z;
    return { x: clamp(x, Math.min(0, el.clientWidth - size), 0), y: clamp(y, Math.min(0, el.clientHeight - size), 0), z };
  };
  const zoomAt = (factor: number, cx: number, cy: number) => setView(v => { const z = clamp(v.z * factor, 1, 24); return fit(cx - (cx - v.x) * z / v.z, cy - (cy - v.y) * z / v.z, z); });
  const center = (at: { x: number; y: number }, z: number) => { const el = box.current; if (!el) return; const { u, v } = worldToMap(at.x, at.y); const size = el.clientWidth * z; setView(fit(el.clientWidth / 2 - u * size, el.clientHeight / 2 - v * size, z)); };
  useEffect(() => {
    let stopped = false;
    let pending = false;
    const pollBlips = async () => {
      if (pending) return;
      pending = true;
      try { const next = await api('mapBlips', {}); if (!stopped) setBlips(asList<MapBlip>(next)); }
      catch { if (!stopped) setBlips([]); }
      finally { pending = false; }
    };
    void pollBlips();
    const blipTimer = window.setInterval(pollBlips, 1000);
    let first = true;
    const poll = () => api('myLocation', {}).then(at => { setMe(at); if (!isPreview) setPin(at.waypoint); if (first) { first = false; center(at, 6); } }).catch(() => {});
    void poll();
    const timer = window.setInterval(poll, 1000);
    return () => { stopped = true; window.clearInterval(timer); window.clearInterval(blipTimer); };
  }, []);
  // The phone is CSS-scaled, so screen px are converted back to the map box's own px.
  const ratio = () => box.current!.getBoundingClientRect().width / box.current!.clientWidth || 1;
  const local = (e: { clientX: number; clientY: number }) => { const r = box.current!.getBoundingClientRect(), k = ratio(); return { cx: (e.clientX - r.left) / k, cy: (e.clientY - r.top) / k }; };
  // Native listener: React's onWheel is passive, so it can't stop the app screen scrolling while you zoom.
  useEffect(() => {
    const el = box.current; if (!el) return;
    const wheel = (e: WheelEvent) => { e.preventDefault(); const { cx, cy } = local(e); zoomAt(e.deltaY < 0 ? 1.25 : 0.8, cx, cy); };
    el.addEventListener('wheel', wheel, { passive: false });
    return () => el.removeEventListener('wheel', wheel);
  }, []);
  const marker = (at: { x: number; y: number; heading?: number }, className: string, label: string) => { const { u, v } = worldToMap(at.x, at.y); return <span className={className} aria-label={label} style={{ left: `${u * 100}%`, top: `${v * 100}%`, ['--h' as string]: `${-(at.heading ?? 0)}deg` }} />; };
  return <div ref={box} className="map-graphic" role="application" aria-label="Map. Drag to move, scroll to zoom, tap to set a waypoint."
    onPointerDown={e => { e.currentTarget.setPointerCapture(e.pointerId); drag.current = { sx: e.clientX, sy: e.clientY, vx: view.x, vy: view.y, moved: false }; }}
    onPointerMove={e => { const d = drag.current; if (!d) return; const k = ratio(), dx = (e.clientX - d.sx) / k, dy = (e.clientY - d.sy) / k; if (Math.abs(dx) + Math.abs(dy) > 5) d.moved = true; if (d.moved) setView(v => fit(d.vx + dx, d.vy + dy, v.z)); }}
    onPointerUp={e => { const d = drag.current; drag.current = undefined; if (!d || d.moved || !box.current) return; const { cx, cy } = local(e); const size = box.current.clientWidth * view.z; const at = mapToWorld((cx - view.x) / size, (cy - view.y) / size); const x = Math.round(at.x), y = Math.round(at.y); setPin({ x, y }); onPick(x, y); }}>
    <div className="map-layer" style={{ transform: `translate(${view.x}px, ${view.y}px) scale(${view.z})`, ['--z' as string]: view.z }}>
      <img src="./map.jpg" alt="" draggable={false} onError={() => setMissing(true)} />
      {blips.map(blip => { const { u, v } = worldToMap(blip.x, blip.y); return <button key={blip.id} type="button" className="map-blip" title={blip.label} aria-label={`Set waypoint: ${blip.label}`} style={{ left: `${u * 100}%`, top: `${v * 100}%`, background: blip.colour }} onPointerDown={e => e.stopPropagation()} onPointerUp={e => e.stopPropagation()} onClick={() => { setPin(blip); onPick(blip.x, blip.y); }}><MapPin size={13} /></button>; })}
      {pin && marker(pin, 'map-pin', 'Waypoint')}
      {me && marker(me, 'map-me', 'You are here')}
    </div>
    {missing && <span className="map-live-note">Add a map image at web/public/map.jpg and rebuild.</span>}
    <div className="map-controls" onPointerDown={e => e.stopPropagation()} onPointerUp={e => e.stopPropagation()}>
      <button className="icon-button" aria-label="Zoom in" onClick={() => zoomAt(1.5, box.current!.clientWidth / 2, box.current!.clientHeight / 2)}><Plus size={16} /></button>
      <button className="icon-button" aria-label="Zoom out" onClick={() => zoomAt(1 / 1.5, box.current!.clientWidth / 2, box.current!.clientHeight / 2)}>−</button>
      <button className="icon-button" aria-label="Center on me" disabled={!me} onClick={() => me && center(me, Math.max(view.z, 6))}><Navigation size={16} /></button>
    </div>
  </div>;
}

export function GPSScreen() {
  const { device, run, notify, busy } = usePhone();
  const [x, setX] = useState(''); const [y, setY] = useState('');
  const waypoint = (x: number, y: number) => run(async () => { await api('waypoint', { x, y }); notify(isPreview ? 'Waypoint selected in preview' : 'Waypoint set on your map'); });
  return <>
    <LiveMap onPick={waypoint} />
    <p className="section-label">PLACES TO BE</p>
    <div className="panel">{device.locations.map(place => <Row key={place.label} title={place.label} detail={`${place.x.toFixed(0)}, ${place.y.toFixed(0)}`} icon={<MapPin size={20} />} onClick={() => waypoint(place.x, place.y)} />)}{!device.locations.length && <p className="muted">No saved places yet.</p>}</div>
    <form className="panel form" onSubmit={e => { e.preventDefault(); waypoint(Number(x), Number(y)); }}><h3>Go somewhere new</h3><div className="two-fields"><label>X coordinate<input required type="number" step="any" min="-20000" max="20000" value={x} onChange={e => setX(e.target.value)} /></label><label>Y coordinate<input required type="number" step="any" min="-20000" max="20000" value={y} onChange={e => setY(e.target.value)} /></label></div><button className="primary" disabled={busy}><Navigation size={17} />Set waypoint</button></form>
  </>;
}
export function ServicesScreen() {
  const { run, busy, notify } = usePhone();
  const work = useLoad(() => api('job', {}), []);
  const job = work.value?.job;
  return <><div className="intro-card"><ShieldCheck size={28} /><h2>Your work.<br />In one place.</h2><p>QBCore job status and approved actions.</p></div><LoadState {...work} retry={work.refresh} />{job && <section className="panel"><span className="section-label">CURRENT ROLE</span><h2>{job.label || job.name}</h2><p className="muted">{job.gradeLabel || `Grade ${job.grade}`} · {job.onDuty ? 'On duty' : 'Off duty'}</p><button className="primary" disabled={busy} onClick={() => run(async()=>{await api('setDuty',{onDuty:!job.onDuty});notify(!job.onDuty?'You are on duty':'You are off duty');work.refresh();})}>{job.onDuty?'Go off duty':'Go on duty'}</button></section>}{work.value?.actions?.map(action=><button className="panel" style={{width:'100%',textAlign:'left'}} key={action.id} disabled={busy} onClick={()=>run(async()=>{await api('jobAction',{action:action.id});notify(`${action.label} completed`);})}><strong>{action.label}</strong></button>)}</>;
}
export function PropertyScreen() {
  const { run, notify } = usePhone();
  const properties = useLoad(() => api('property', {}), []);
  return <><LoadState {...properties} retry={properties.refresh} />{asList<Property>(properties.value).map(property => <section className="property-card" key={property.name}><div className="property-art"><Home size={58} strokeWidth={1} /><span>HOME / YOUR SPACE</span></div><h3>{property.label || property.name}</h3><p>Owned by your current character</p>{property.coords && <button className="primary" onClick={() => run(async () => { await api('waypoint', property.coords!); notify('Home waypoint selected'); })}><Navigation size={16} />Take me home</button>}</section>)}{!properties.loading && !asList(properties.value).length && <Empty title="Find your place" detail="Properties you own will appear here." />}</>;
}
export function VehiclesScreen() {
  const vehicles = useLoad(() => api('vehicles', {}), []);
  return <><LoadState {...vehicles} retry={vehicles.refresh} />{asList<Vehicle>(vehicles.value).map(vehicle => <section className="vehicle-card" key={vehicle.plate}><Car size={72} strokeWidth={1} /><div className="vehicle-heading"><h3>{vehicle.vehicle}</h3><span className="plate">{vehicle.plate}</span></div><div className="vehicle-stats"><div><small>STATUS</small><strong>{vehicle.state === 1 ? 'Garaged' : vehicle.state === 2 ? 'Impounded' : 'Out'}</strong></div><div><small>FUEL</small><strong>{Math.round(vehicle.fuel)}%</strong></div></div><Row title={vehicle.garage || 'Unknown garage'} detail="Last registered garage" icon={<MapPin size={18} />} /></section>)}{!vehicles.loading && !asList(vehicles.value).length && <Empty title="The road is waiting" detail="Your character’s owned vehicles will appear here." />}</>;
}
export function WeatherScreen() {
  const weather = useLoad(() => api('weather', {}), []);
  return <><LoadState {...weather} retry={weather.refresh} />{weather.value && <div className="weather-screen"><p className="section-label">LOS SANTOS / RIGHT NOW</p>{weather.value.rain > 0 ? <CloudSun size={105} strokeWidth={0.8} /> : <Sun size={105} strokeWidth={0.8} />}<h2>{({ EXTRASUNNY: 'Extra sunny', CLEAR: 'Clear skies', CLOUDS: 'Cloudy', OVERCAST: 'Overcast', RAIN: 'Rain', THUNDER: 'Thunderstorms', SMOG: 'Smog', FOGGY: 'Fog', CLEARING: 'Clearing up', NEUTRAL: 'Calm', SNOW: 'Snow', BLIZZARD: 'Blizzard', SNOWLIGHT: 'Light snow', XMAS: 'Snow', HALLOWEEN: 'Eerie' } as Record<string, string>)[weather.value.condition] || weather.value.condition.toLowerCase()}</h2><p>A little perspective on your day.</p><div className="weather-time"><small>IN-GAME TIME</small><DotClock value={`${String(weather.value.hour).padStart(2, '0')}:${String(weather.value.minute).padStart(2, '0')}`} /></div><Row title="Rain intensity" detail="Current world conditions" end={<strong>{Math.round(weather.value.rain * 100)}%</strong>} /><button className="text-button" onClick={weather.refresh}>Refresh conditions</button></div>}</>;
}
export function CalculatorScreen() {
  const [expression, setExpression] = useState(''); const [error, setError] = useState('');
  const press = (key: string) => { setError(''); if (key === 'AC') setExpression(''); else if (key === '⌫') setExpression(v => v.slice(0, -1)); else if (key === '=') { try { setExpression(calculate(expression)); } catch (e) { setError((e as Error).message); } } else setExpression(v => (v + key).slice(0, 60)); };
  return <div className="calculator"><div className="calc-display"><small>{error || 'A LITTLE CLARITY'}</small><output aria-live="polite">{expression || '0'}</output></div><div className="calc-keys">{['AC', '⌫', '÷', '×', '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '=', '0', '.'].map(key => <button key={key} className={`${key === '=' ? 'equals' : ''} ${key === '0' ? 'zero' : ''}`} onClick={() => press(key)}>{key}</button>)}</div></div>;
}
