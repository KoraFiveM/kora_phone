import { useEffect, useRef, useState } from 'react';
import { Camera, Car, CloudSun, Home, MapPin, Navigation, Plus, Save, ShieldCheck, StickyNote, Sun, Trash2 } from 'lucide-react';
import { api, isPreview, nui, requestId } from './api';
import { PhotoImage } from './Images';
import { asList } from './types';
import type { Note, Property, Vehicle } from './types';
import { calculate, DotClock, Empty, Row } from './components';
import { LoadState, useLoad, usePhone } from './PhoneContext';

export function NotesScreen() {
  const { data, updateData, run, busy } = usePhone();
  const [draft, setDraft] = useState<Note>();
  return <>{draft ? <form className="form" onSubmit={e => { e.preventDefault(); run(async () => { updateData(await api('notes', draft)); setDraft(undefined); }); }}><button type="button" className="text-button" onClick={() => setDraft(undefined)}>← All notes</button><label>Title<input required maxLength={100} value={draft.title} onChange={e => setDraft({ ...draft, title: e.target.value })} /></label><textarea className="note-editor" aria-label="Note body" required maxLength={4000} value={draft.body} placeholder="A thought worth keeping…" onChange={e => setDraft({ ...draft, body: e.target.value })} /><button className="primary" disabled={busy}><Save size={17} />Save note</button></form> : <><button className="primary" onClick={() => setDraft({ id: requestId(), title: '', body: '' })}><Plus size={18} />New note</button>{data.notes.map(note => <article className="note-card" key={note.id}><button onClick={() => setDraft({ ...note })}><StickyNote size={18} /><h3>{note.title}</h3><p>{note.body}</p></button><button className="icon-button" aria-label={`Delete note ${note.title}`} disabled={busy} onClick={() => run(async () => updateData(await api('notes', { ...note, remove: true })))}><Trash2 size={16} /></button></article>)}{!data.notes.length && <Empty title="Space to think" detail="Keep your plans, ideas, and little reminders here." />}</>}</>;
}
export function GalleryScreen({ camera = false }: { camera?: boolean }) {
  const { data, updateData, run, busy, device, navigate } = usePhone();
  const [selected, setSelected] = useState<string>();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const photo = data.photos.find(item => item.id === selected);
  return <>{camera ? <><div className="camera-viewfinder"><div className="viewfinder-grid" /><Camera size={42} strokeWidth={1} /><p>{isPreview ? 'Preview camera' : 'Capture your view'}</p><small>{isPreview ? 'Creates a sample illustration' : 'The phone hides while the photo is taken'}</small></div><p className="muted camera-caption">A moment. Made yours.</p><button className="shutter" aria-label="Take photo" disabled={busy} onClick={() => run(async () => { try { updateData(await api('capture', {})); navigate('gallery'); } finally { await nui('captureDone'); } })}><span /></button><button className="text-button centered" onClick={() => navigate('gallery')}>Open gallery · {data.photos.length}</button></> : photo ? <div className="photo-view"><button className="text-button" onClick={() => { setSelected(undefined); setConfirmDelete(false); }}>← All photos</button><PhotoImage src={photo.url} alt="Saved phone photograph" /><button className="text-button danger" onClick={() => setConfirmDelete(true)}><Trash2 size={16} />Delete photo</button>{confirmDelete && <div className="panel"><p>Remove this photo from the phone gallery?</p><button className="primary" disabled={busy} onClick={() => run(async () => { updateData(await api('deletePhoto', { id: photo.id })); setSelected(undefined); setConfirmDelete(false); })}>Delete from gallery</button><button className="text-button" onClick={() => setConfirmDelete(false)}>Cancel</button></div>}</div> : <><div className="section-heading"><span className="section-label">YOUR MOMENTS / {data.photos.length}</span>{device.capabilities.camera && <button className="icon-button" aria-label="Open camera" onClick={() => navigate('camera')}><Camera size={20} /></button>}</div><div className="gallery-grid">{data.photos.map(item => <button key={item.id} onClick={() => setSelected(item.id)} aria-label="View photo"><PhotoImage src={item.url} alt="Gallery thumbnail" /></button>)}</div>{!data.photos.length && <Empty title="Collect a moment" detail={device.capabilities.camera ? 'Photos you take will appear here.' : 'Camera uploads have not been configured on this server.'} />}</>}</>;
}
export function GPSScreen() {
  const { device, run, notify, busy } = usePhone();
  const [x, setX] = useState(''); const [y, setY] = useState('');
  const mapRef = useRef<HTMLDivElement>(null);
  const lastRect = useRef('');
  const waypoint = (x: number, y: number) => run(async () => { await api('waypoint', { x, y }); notify(isPreview ? 'Waypoint selected in preview' : 'Waypoint set on your map'); });
  // Reports the map slot's on-screen box so the client can reposition the game's live minimap to sit exactly behind it.
  useEffect(() => {
    if (isPreview) return;
    const report = () => {
      const box = mapRef.current?.getBoundingClientRect();
      if (!box || !box.width || !box.height) return;
      const rect = { x: box.left / window.innerWidth, y: box.top / window.innerHeight, w: box.width / window.innerWidth, h: box.height / window.innerHeight };
      const key = `${rect.x.toFixed(4)}:${rect.y.toFixed(4)}:${rect.w.toFixed(4)}:${rect.h.toFixed(4)}`;
      if (key === lastRect.current) return;
      lastRect.current = key;
      void api('openMap', rect);
    };
    report();
    // Polls instead of hooking the phone's drag/resize handlers directly, so the live map follows if you drag or resize the phone while on this screen. Ceiling: up to 300ms of lag behind the phone frame. Upgrade path: call report() straight from the drag/scale handlers in App.tsx.
    const interval = window.setInterval(report, 300);
    window.addEventListener('resize', report);
    return () => { window.clearInterval(interval); window.removeEventListener('resize', report); lastRect.current = ''; void api('closeMap', {}); };
  }, []);
  return <>
    <div ref={mapRef} className="map-graphic">{isPreview && <span className="map-live-note">The live map renders here in-game.</span>}</div>
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
