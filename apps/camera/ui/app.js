import { phone, ready, h, render, states, toast, icon, i18n } from '/sdk/runtime/kit.js';
import { createGameView, recordGameClip, openMicrophone } from '/sdk/runtime/game.js';

const t = i18n({ en: { title: 'Camera', photo: 'Photo', video: 'Video', flip: 'Switch camera', shutter: 'Take photo', record: 'Record video', stop: 'Stop recording', gallery: 'Open gallery',
    retry: 'Try again', rear: 'Rear camera', selfie: 'Selfie camera', noVideo: 'Video recording requires video storage to be configured.', silent: 'Silent clips',
    voice: 'Records your voice while you talk', mic: 'Records your microphone', upTo: 'up to', unavailable: 'The game camera is unavailable.', stopped: 'The game camera stopped. Please reopen Camera.',
    micOff: 'Microphone unavailable. Recording without sound.', stopFirst: 'Stop recording first.' } });
const root = document.getElementById('app');

let cfg = { media: true, flash: false };
let front = false;
let mode = 'photo';
let view;
let frame = 0;
let canvas;
let zoom = false;
let hint = '';
let mic = { enabled: false, followVoice: true };
let capturing = false;
let recording;
let seconds = 0;
let timer;
let opened = false;
let closing = Promise.resolve();

// The game texture is as large as the whole phone page, not this frame.
const pageSize = () => { const top = window.top || window; return [top.innerWidth, top.innerHeight]; };

async function openCamera() {
    await closing;
    const reply = await phone.client('open', { front });
    if (!reply.ok) throw new Error(reply.error || t('unavailable'));
    opened = true; zoom = reply.zoom === true; hint = reply.hint || ''; mic = { enabled: reply.mic && reply.mic.enabled === true, followVoice: !reply.mic || reply.mic.followVoice !== false };
}

function closeCamera() {
    cancelAnimationFrame(frame);
    if (recording) { recording.cancel(); recording = undefined; }
    if (view) { view.dispose(); view = undefined; }
    if (opened) { opened = false; closing = phone.client('close').catch(() => undefined); }
}

function draw() {
    let previous = 0;
    const loop = now => { frame = requestAnimationFrame(loop); if (view && now - previous >= 50) { view.render(); previous = now; } };
    frame = requestAnimationFrame(loop);
}

async function start() {
    closeCamera();
    show('loading');
    try {
        await openCamera();
        show('live');
        view = createGameView(canvas, { preserveDrawingBuffer: true, onContextLost: () => { if (recording) recording.cancel(t('stopped')); show('error', t('stopped')); } });
        const [w, hh] = pageSize();
        view.resize(540, 960, w, hh);
        view.render(); draw();
        setButtons();
    } catch (error) { closeCamera(); show('error', error.message); }
}

function setButtons() {
    const shutter = document.getElementById('shutter');
    if (!shutter) return;
    shutter.disabled = !view;
    shutter.dataset.video = String(mode === 'video');
    shutter.setAttribute('aria-label', capturing ? t('stop') : mode === 'video' ? t('record') : t('shutter'));
}

function caption() {
    if (mode === 'video') return `${mic.enabled ? (mic.followVoice ? t('voice') : t('mic')) : t('silent')} · ${t('upTo')} ${cfg.flash ? cfg.flash.maxSeconds : 15}s`;
    return front ? t('selfie') : t('rear');
}

async function takePhoto() {
    const shot = await phone.camera.capture({ front }).catch(error => { toast(error.message); return undefined; });
    if (shot) { phone.refresh().catch(() => {}); phone.open('gallery').catch(() => {}); return; }
    start();   // the phone hid the viewfinder for the shot: bring it back
}

async function takeVideo() {
    if (!cfg.flash || !view) return;
    let audio;
    if (mic.enabled) { audio = await openMicrophone(); if (!audio) toast(t('micOff')); }
    const tracks = audio ? audio.getAudioTracks() : [];
    const follow = tracks.length > 0 && mic.followVoice;
    const onTalking = payload => { tracks.forEach(track => { track.enabled = payload && payload.talking === true; }); };
    if (follow) { tracks.forEach(track => { track.enabled = false; }); phone.on('talking', onTalking); phone.client('recording', { active: true }).catch(() => {}); }
    const release = () => { if (follow) phone.client('recording', { active: false }).catch(() => {}); };
    try { recording = recordGameClip(canvas, cfg.flash.maxSeconds, cfg.flash.maxBytes || 24 * 1024 * 1024, audio); }
    catch (error) { release(); toast(error.message); return; }
    capturing = true; seconds = 0; setButtons(); paintRec();
    timer = setInterval(() => { seconds += 1; paintRec(); }, 1000);
    try {
        const blob = await recording.result;
        release(); clearInterval(timer); capturing = false; recording = undefined;
        await phone.media.upload(blob);
        phone.refresh().catch(() => {}); phone.open('gallery').catch(() => {});
    } catch (error) { toast(error.message); }
    finally { release(); clearInterval(timer); capturing = false; recording = undefined; setButtons(); paintRec(); }
}

function paintRec() { const node = document.getElementById('rec'); if (node) node.textContent = capturing ? `● REC ${seconds}s` : ''; }

function show(state, message) {
    canvas = h('canvas', { 'aria-label': front ? t('selfie') : t('rear') });
    const stage = h('div', { class: 'viewfinder' }, state === 'loading' ? states.loading() : state === 'error' ? states.error(t('unavailable'), message || '', start) : canvas, h('span', { class: 'rec', id: 'rec' }));
    if (zoom) stage.addEventListener('wheel', event => { event.preventDefault(); if (event.deltaY) phone.client('zoom', { dir: event.deltaY < 0 ? 1 : -1 }).catch(() => {}); }, { passive: false });
    const modeButton = (id, label, disabled) => h('button', { class: 'kp-btn', 'data-variant': 'ghost', 'data-mode': id, 'aria-pressed': mode === id, disabled: disabled || capturing, onclick: () => {
        mode = id;
        document.querySelectorAll('[data-mode]').forEach(node => node.setAttribute('aria-pressed', String(node.dataset.mode === mode)));
        document.getElementById('caption').textContent = caption(); setButtons();
    } }, label);
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))),
        h('div', { class: 'kp-content', style: 'display:flex;flex-direction:column;gap:8px;height:100%' }, stage,
            h('div', { class: 'controls' }, modeButton('photo', t('photo')), modeButton('video', t('video'), !cfg.flash),
                h('button', { class: 'kp-icon-btn', 'aria-label': t('flip'), disabled: capturing || state !== 'live', onclick: async () => {
                    const reply = await phone.client('facing', { front: !front }).catch(() => ({ ok: false }));
                    if (reply.ok) { front = !front; canvas.setAttribute('aria-label', front ? t('selfie') : t('rear')); document.getElementById('caption').textContent = caption(); }
                } }, icon('camera'))),
            h('p', { class: 'kp-row-sub', id: 'caption' }, caption()), hint ? h('p', { class: 'kp-row-sub', id: 'hint' }, hint) : h('p', { id: 'hint' }),
            h('button', { class: 'shutter', id: 'shutter', onclick: () => { if (capturing) recording && recording.stop(); else if (mode === 'video') takeVideo(); else takePhoto(); } }, h('span')),
            !cfg.flash ? h('p', { class: 'kp-row-sub' }, t('noVideo')) : null,
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => { if (capturing) toast(t('stopFirst')); else phone.open('gallery'); } }, t('gallery'))));
    setButtons();
}

phone.on('hint', payload => { hint = payload && payload.text || ''; const node = document.getElementById('hint'); if (node) node.textContent = hint; });
window.addEventListener('pagehide', closeCamera);

ready().then(async () => { cfg = await phone.callback('config'); await start(); }).catch(error => render(root, states.error('Could not start', error.message)));
