import { phone, ready, h, render, states, toast, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Maps', zoomIn: 'Zoom in', zoomOut: 'Zoom out', center: 'Center on me', here: 'You are here', pin: 'Waypoint', waypoint: 'Waypoint set on your map',
    places: 'Places to be', none: 'No saved places yet.', somewhere: 'Go somewhere new', x: 'X coordinate', y: 'Y coordinate', set: 'Set waypoint', close: 'Close blip details',
    mapHint: 'Map. Drag to move, scroll to zoom, tap to set a waypoint.' } });
const root = document.getElementById('app');

// World coordinates at the edges of map.jpg (road style, stitched from zoom-5 tiles, cropped square to the island).
// Swap the image for another render and these four numbers need re-fitting.
const BOUNDS = { left: -5879, right: 7243, top: 8567, bottom: -4555 };
const worldToMap = (x, y) => ({ u: (x - BOUNDS.left) / (BOUNDS.right - BOUNDS.left), v: (BOUNDS.top - y) / (BOUNDS.top - BOUNDS.bottom) });
const mapToWorld = (u, v) => ({ x: BOUNDS.left + u * (BOUNDS.right - BOUNDS.left), y: BOUNDS.top - v * (BOUNDS.top - BOUNDS.bottom) });
const clamp = (n, lo, hi) => Math.min(hi, Math.max(lo, n));
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };

const setWaypoint = async (x, y) => { if (await attempt(() => phone.client('waypoint', { x, y }))) toast(t('waypoint')); };

function liveMap() {
  const box = h('div', { class: 'map-box', role: 'application', 'aria-label': t('mapHint') });
  const layer = h('div', { class: 'map-layer' }, h('img', { class: 'map-image', src: 'map.jpg', alt: '', draggable: false }));
  const place = h('div');
  box.append(layer, place);
  let view = { x: 0, y: 0, z: 1 };
  let me; let pin; let blips = []; let selected; let drag;

  const fit = (x, y, z) => { const size = box.clientWidth * z; return { x: clamp(x, Math.min(0, box.clientWidth - size), 0), y: clamp(y, Math.min(0, box.clientHeight - size), 0), z }; };
  const apply = () => { layer.style.transform = `translate(${view.x}px, ${view.y}px) scale(${view.z})`; layer.style.setProperty('--z', view.z); };
  const zoomAt = (factor, cx, cy) => { const z = clamp(view.z * factor, 1, 24); view = fit(cx - (cx - view.x) * z / view.z, cy - (cy - view.y) * z / view.z, z); apply(); };
  const center = (at, z) => { const { u, v } = worldToMap(at.x, at.y); const size = box.clientWidth * z; view = fit(box.clientWidth / 2 - u * size, box.clientHeight / 2 - v * size, z); apply(); };

  const marker = (at, className, label) => { const { u, v } = worldToMap(at.x, at.y); return h('span', { class: className, 'aria-label': label, style: `left:${u * 100}%;top:${v * 100}%` }); };
  const paintMarkers = () => {
    layer.querySelectorAll('.map-blip, .map-me, .map-pin').forEach(node => node.remove());
    for (const blip of blips) {
      const { u, v } = worldToMap(blip.x, blip.y);
      const button = h('button', { class: 'map-blip', title: blip.label, 'aria-label': blip.label, 'aria-pressed': selected && selected.id === blip.id, style: `left:${u * 100}%;top:${v * 100}%;color:${blip.colour}`,
        onpointerdown: event => { event.stopPropagation(); selected = blip; paintMarkers(); paintPlace(); } });
      layer.append(button);
    }
    if (pin) layer.append(marker(pin, 'map-pin', t('pin')));
    if (me) layer.append(marker(me, 'map-me', t('here')));
  };
  const paintPlace = () => render(place, selected ? h('div', { class: 'map-place', role: 'status' },
    h('div', null, h('strong', null, selected.label), h('small', { class: 'kp-row-sub' }, [selected.street, selected.zone].filter(Boolean).join(' · ') || `${selected.x.toFixed(0)}, ${selected.y.toFixed(0)}`)),
    h('button', { class: 'kp-icon-btn', 'aria-label': t('pin'), onclick: () => { pin = { x: selected.x, y: selected.y }; setWaypoint(selected.x, selected.y); paintMarkers(); } }, icon('forward')),
    h('button', { class: 'kp-icon-btn', 'aria-label': t('close'), onclick: () => { selected = undefined; paintMarkers(); paintPlace(); } }, icon('x'))) : null);

  box.append(h('div', { class: 'map-controls' },
    h('button', { class: 'kp-icon-btn', 'aria-label': t('zoomIn'), onclick: () => zoomAt(1.5, box.clientWidth / 2, box.clientHeight / 2) }, icon('plus')),
    h('button', { class: 'kp-icon-btn', 'aria-label': t('zoomOut'), onclick: () => zoomAt(1 / 1.5, box.clientWidth / 2, box.clientHeight / 2) }, '−'),
    h('button', { class: 'kp-icon-btn', 'aria-label': t('center'), onclick: () => me && center(me, Math.max(view.z, 6)) }, icon('home'))));

  const local = event => { const r = box.getBoundingClientRect(); const k = r.width / box.clientWidth || 1; return { cx: (event.clientX - r.left) / k, cy: (event.clientY - r.top) / k, k }; };
  box.addEventListener('wheel', event => { event.preventDefault(); const { cx, cy } = local(event); zoomAt(event.deltaY < 0 ? 1.25 : 0.8, cx, cy); }, { passive: false });
  box.addEventListener('pointerdown', event => { if (event.target.closest('button')) return; box.setPointerCapture(event.pointerId); drag = { sx: event.clientX, sy: event.clientY, vx: view.x, vy: view.y, moved: false }; });
  box.addEventListener('pointermove', event => {
    if (!drag) return;
    const { k } = local(event); const dx = (event.clientX - drag.sx) / k; const dy = (event.clientY - drag.sy) / k;
    if (Math.abs(dx) + Math.abs(dy) > 5) drag.moved = true;
    if (drag.moved) { view = fit(drag.vx + dx, drag.vy + dy, view.z); apply(); }
  });
  box.addEventListener('pointerup', event => {
    const d = drag; drag = undefined;
    if (!d || d.moved) return;
    const { cx, cy } = local(event); const size = box.clientWidth * view.z;
    const at = mapToWorld((cx - view.x) / size, (cy - view.y) / size);
    const x = Math.round(at.x); const y = Math.round(at.y);
    selected = undefined; pin = { x, y }; paintMarkers(); paintPlace(); setWaypoint(x, y);
  });

  let stopped = false; let first = true;
  const refreshBlips = async () => { try { blips = await phone.client('blips'); } catch { blips = []; } if (!stopped) paintMarkers(); };
  const poll = async () => {
    try { const at = await phone.client('here'); me = at; pin = at.waypoint; if (first) { first = false; center(at, 6); } if (!stopped) paintMarkers(); } catch { /* the position is optional */ }
  };
  phone.on('mapBlipsChanged', refreshBlips);
  refreshBlips(); poll();
  const timer = setInterval(poll, 1000);
  window.addEventListener('pagehide', () => { stopped = true; clearInterval(timer); });
  apply();
  return box;
}

async function show() {
  const x = h('input', { class: 'kp-input', type: 'number', step: 'any', min: -20000, max: 20000, 'aria-label': t('x'), placeholder: t('x') });
  const y = h('input', { class: 'kp-input', type: 'number', step: 'any', min: -20000, max: 20000, 'aria-label': t('y'), placeholder: t('y') });
  const placesHolder = h('div', { class: 'kp-card' }, states.loading());
  render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))),
    h('div', { class: 'kp-content' }, liveMap(), h('p', { class: 'kp-section-label' }, t('places')), placesHolder,
      h('div', { class: 'kp-card' }, h('h2', { class: 'kp-row-title' }, t('somewhere')), h('div', { class: 'coords' }, x, y),
        h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: () => { const px = Number(x.value); const py = Number(y.value); if (x.value !== '' && y.value !== '') setWaypoint(px, py); } }, t('set')))));
  try {
    const places = await phone.callback('places');
    render(placesHolder, places.length ? h('ul', { class: 'kp-list' }, places.map(place => h('li', null, h('button', { class: 'kp-row', onclick: () => setWaypoint(place.x, place.y) },
      h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, place.label), h('span', { class: 'kp-row-sub' }, `${place.x.toFixed(0)}, ${place.y.toFixed(0)}`)))))) : h('p', { class: 'kp-row-sub' }, t('none')));
  } catch (error) { render(placesHolder, states.error('Something went wrong', error.message)); }
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
