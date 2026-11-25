import { phone, ready, h, render, states, toast, confirm, icon, i18n } from '/sdk/runtime/kit.js';
import { embedSource } from './player.js';

const t = i18n({ en: { title: 'Sound', add: 'Add station', now: 'Now playing', stop: 'Stop playback', name: 'Name', url: 'Stream URL', save: 'Save station', all: 'All stations',
    hint: 'YouTube links, SoundCloud links, and direct HTTPS audio stream URLs are all supported.', del: 'Delete', deleteTitle: 'Delete this station?', deleteDetail: 'This cannot be undone.',
    emptyTitle: 'Something to listen to', emptyDetail: 'Save a YouTube, SoundCloud, or direct stream link to play it here.' } });
const root = document.getElementById('app');
const newId = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };

let stations = [];
let playing;
let volume = 0.5;

const syncPhone = () => phone.refresh().catch(() => {});   // the phone's Flip cover shows these stations too

function player(station) {
    const src = embedSource(station);
    if (src) return h('iframe', { class: 'player-frame', src, title: station.label, allow: 'autoplay; encrypted-media' });
    const audio = h('audio', { class: 'player-audio', autoplay: true, controls: true, src: station.url });
    audio.volume = volume;
    return audio;
}

function edit(station) {
    const name = h('input', { class: 'kp-input', required: true, maxlength: 60, 'aria-label': t('name'), placeholder: t('name'), value: station.label });
    const url = h('input', { class: 'kp-input', type: 'url', required: true, 'aria-label': t('url'), placeholder: t('url'), value: station.url });
    render(root,
        h('header', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('all'), onclick: show }, icon('back')), h('h1', { class: 'kp-title' }, t('add'))),
        h('div', { class: 'kp-content' }, h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('name')), name), h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('url')), url), h('p', { class: 'kp-row-sub' }, t('hint'))),
        h('div', { class: 'kp-footer' }, h('button', { class: 'kp-btn kp-grow', 'data-variant': 'primary', onclick: async () => {
            const next = { id: station.id, label: name.value.trim(), url: url.value.trim() };
            if (!next.label || !/^https:\/\//.test(next.url)) return;
            if (await attempt(async () => { await phone.callback('save', next); return true; })) {
                stations = stations.some(item => item.id === next.id) ? stations.map(item => item.id === next.id ? next : item) : stations.concat(next);
                syncPhone(); show();
            }
        } }, t('save'))));
}

async function show() {
    const holder = h('div', { class: 'kp-content kp-flush' }, states.loading());
    const nowPlaying = h('div');
    const paintNow = () => render(nowPlaying, playing ? h('div', { class: 'kp-card' }, h('div', { class: 'kp-row-flex' }, h('div', { class: 'kp-grow' }, h('p', { class: 'kp-section-label' }, t('now')), h('h2', { class: 'kp-row-title' }, playing.label)),
        h('button', { class: 'kp-icon-btn', 'aria-label': t('stop'), onclick: () => { playing = undefined; paintNow(); } }, icon('pause'))), player(playing)) : null);
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title')), h('button', { class: 'kp-icon-btn', 'aria-label': t('add'), onclick: () => edit({ id: newId(), label: '', url: '' }) }, icon('plus'))),
        h('div', { class: 'kp-content' }, nowPlaying), holder);
    paintNow();
    try {
        stations = await phone.callback('list');
        render(holder, stations.length ? h('ul', { class: 'kp-list' }, stations.map(station => h('li', null, h('div', { class: 'kp-row' },
            h('button', { class: 'kp-row-main', style: 'all:unset;cursor:pointer;flex:1;min-width:0', onclick: () => { playing = station; paintNow(); } },
                h('span', { class: 'kp-row-title' }, station.label), h('span', { class: 'kp-row-sub' }, station.url)),
            h('button', { class: 'kp-icon-btn', 'aria-label': `${t('del')} ${station.label}`, onclick: async () => {
                if (!(await confirm({ title: t('deleteTitle'), message: t('deleteDetail'), confirmLabel: t('del'), danger: true }))) return;
                if (await attempt(async () => { await phone.callback('remove', { id: station.id }); return true; })) {
                    stations = stations.filter(item => item.id !== station.id); if (playing && playing.id === station.id) playing = undefined; syncPhone(); show();
                }
            } }, icon('trash')))))) : states.empty(t('emptyTitle'), t('emptyDetail')));
    } catch (error) { render(holder, states.error('Something went wrong', error.message, show)); }
}

ready().then(init => { if (typeof init.volume === 'number') volume = init.volume; return show(); }).catch(error => render(root, states.error('Could not start', error.message)));
