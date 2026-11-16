import { MapPin,Navigation,Plus,X } from 'lucide-react';
import { useEffect,useRef,useState } from 'react';
import { api,isPreview } from '../../api';
import blipSprites from '../../blipSprites.json';
import { Row } from '../../components';
import { usePhone } from '../../core/PhoneContext';
import { isHostMessage } from '../../nuiEvents';
import type { MapBlip } from '../../types';
import { asList } from '../../types';

// Calibration knob: World coords at the edges of web/public/map.jpg (road style, stitched from
// zoom-5 tiles, cropped square to the island). Checked against the Del Perro pier
// and LSIA terminal. Swap the image for another render and these four numbers need re-fitting.
const MAP_BOUNDS = { left: -5879, right: 7243, top: 8567, bottom: -4555 };
export const worldToMap = (x: number, y: number) => ({ u: (x - MAP_BOUNDS.left) / (MAP_BOUNDS.right - MAP_BOUNDS.left), v: (MAP_BOUNDS.top - y) / (MAP_BOUNDS.top - MAP_BOUNDS.bottom) });
export const mapToWorld = (u: number, v: number) => ({ x: MAP_BOUNDS.left + u * (MAP_BOUNDS.right - MAP_BOUNDS.left), y: MAP_BOUNDS.top - v * (MAP_BOUNDS.top - MAP_BOUNDS.bottom) });
const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n));

// Sprite IDs and artwork from the Cfx.re blip catalog.
const spriteNames: Readonly<Partial<Record<number, string>>> = blipSprites;
const blipType = (sprite: number) => spriteNames[sprite]?.replace(/^radar_/, '').replace(/_/g, ' ').replace(/^./, letter => letter.toUpperCase());

// Drag to pan, scroll or +/- to zoom, tap to drop a waypoint. The image is sized to the box width at zoom 1.
function LiveMap({ onPick }: { onPick: (x: number, y: number) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const drag = useRef<{ sx: number; sy: number; vx: number; vy: number; moved: boolean }>(undefined);
  const [view, setView] = useState({ x: 0, y: 0, z: 1 });
  const [me, setMe] = useState<{ x: number; y: number; heading?: number }>();
  // Mirrors the game's own waypoint, so it survives leaving the app and shows ones set from the pause map.
  const [pin, setPin] = useState<{ x: number; y: number }>();
  const [blips, setBlips] = useState<MapBlip[]>([]);
  const [selectedId, setSelectedId] = useState<number>();
  const selected = blips.find(blip => blip.id === selectedId);
  const address = selected && [...new Set([blipType(selected.sprite), selected.street, selected.zone])].filter(part => part && part !== selected.label).join(' · ');
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
    let dirty = false;
    const refreshBlips = async () => {
      if (pending) { dirty = true; return; }
      dirty = false;
      pending = true;
      try { const next = await api('mapBlips', {}); if (!stopped) setBlips(asList<MapBlip>(next)); }
      catch { if (!stopped) setBlips([]); }
      finally {
        pending = false;
        if (dirty && !stopped) void refreshBlips();
      }
    };
    const onMessage = (event: MessageEvent) => {
      if (isHostMessage(event.source, window, window.parent) && event.data?.type === 'mapBlipsChanged') void refreshBlips();
    };
    window.addEventListener('message', onMessage);
    void refreshBlips();
    let first = true;
    const poll = () => api('myLocation', {}).then(at => { setMe(at); if (!isPreview) setPin(at.waypoint); if (first) { first = false; center(at, 6); } }).catch(() => {});
    void poll();
    const timer = window.setInterval(poll, 1000);
    return () => { stopped = true; window.clearInterval(timer); window.removeEventListener('message', onMessage); };
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
    onPointerDown={e => { if ((e.target as HTMLElement).closest('button')) return; e.currentTarget.setPointerCapture(e.pointerId); drag.current = { sx: e.clientX, sy: e.clientY, vx: view.x, vy: view.y, moved: false }; }}
    onPointerMove={e => { const d = drag.current; if (!d) return; const k = ratio(), dx = (e.clientX - d.sx) / k, dy = (e.clientY - d.sy) / k; if (Math.abs(dx) + Math.abs(dy) > 5) d.moved = true; if (d.moved) setView(v => fit(d.vx + dx, d.vy + dy, v.z)); }}
    onPointerUp={e => { const d = drag.current; drag.current = undefined; if (!d || d.moved || !box.current) return; const { cx, cy } = local(e); const size = box.current.clientWidth * view.z; const at = mapToWorld((cx - view.x) / size, (cy - view.y) / size); const x = Math.round(at.x), y = Math.round(at.y); setSelectedId(undefined); setPin({ x, y }); onPick(x, y); }}>
    <div className="map-layer" style={{ transform: `translate(${view.x}px, ${view.y}px) scale(${view.z})`, ['--z' as string]: view.z }}>
      <img src="./map.jpg" alt="" draggable={false} onError={() => setMissing(true)} />
      {blips.map(blip => { const { u, v } = worldToMap(blip.x, blip.y); const sprite = spriteNames[blip.sprite]; return <button key={blip.id} type="button" className="map-blip" title={blip.label} aria-label={blip.label} aria-pressed={selectedId === blip.id} style={{ left: `${u * 100}%`, top: `${v * 100}%`, color: blip.colour }} draggable={false} onDragStart={e => e.preventDefault()} onPointerDown={e => { e.stopPropagation(); if (e.button === 0) setSelectedId(blip.id); }} onPointerUp={e => e.stopPropagation()} onClick={() => setSelectedId(blip.id)}>{sprite && <img draggable={false} key={sprite} src={`https://docs-backend.fivem.net/blips/${sprite}.png`} alt="" loading="lazy" onError={e => { e.currentTarget.hidden = true; }} />}</button>; })}
      {pin && marker(pin, 'map-pin', 'Waypoint')}
      {me && marker(me, 'map-me', 'You are here')}
    </div>
    {missing && <span className="map-live-note">Add a map image at web/public/map.jpg and rebuild.</span>}
    <div className="map-controls" onPointerDown={e => e.stopPropagation()} onPointerUp={e => e.stopPropagation()}>
      <button className="icon-button" aria-label="Zoom in" onClick={() => zoomAt(1.5, box.current!.clientWidth / 2, box.current!.clientHeight / 2)}><Plus size={16} /></button>
      <button className="icon-button" aria-label="Zoom out" onClick={() => zoomAt(1 / 1.5, box.current!.clientWidth / 2, box.current!.clientHeight / 2)}>−</button>
      <button className="icon-button" aria-label="Center on me" disabled={!me} onClick={() => me && center(me, Math.max(view.z, 6))}><Navigation size={16} /></button>
    </div>
    {selected && <div className="map-place" aria-live="polite" onPointerDown={e => e.stopPropagation()} onPointerUp={e => e.stopPropagation()}>
      <div><strong>{selected.label}</strong><small>{address || `${selected.x.toFixed(0)}, ${selected.y.toFixed(0)}`}</small></div>
      <button className="icon-button" aria-label={`Set waypoint to ${selected.label}`} onClick={() => { setPin(selected); onPick(selected.x, selected.y); }}><Navigation size={17} /></button>
      <button className="icon-button" aria-label="Close blip details" onClick={() => setSelectedId(undefined)}><X size={16} /></button>
    </div>}
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
