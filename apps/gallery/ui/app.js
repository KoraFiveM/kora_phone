import { phone, ready, h, render, states, toast, confirm, viewMedia, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Gallery', moments: 'Your moments', camera: 'Open camera', all: 'All photos', full: 'Full screen', del: 'Delete', deleteTitle: 'Remove this item from the phone gallery?',
    deleteDetail: 'It is deleted from this phone.', emptyTitle: 'Nothing here yet', emptyDetail: 'Photos and clips you take appear here.', older: 'Load older', photo: 'Saved phone photograph', video: 'Saved phone video' } });
const root = document.getElementById('app');
let items = [];
let next;

const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };
const thumb = item => item.kind === 'video'
    ? h('video', { src: item.url, muted: true, playsinline: true, preload: 'metadata', 'aria-label': t('video') })
    : h('img', { src: item.url, alt: t('photo') });

function view(item) {
    const back = h('button', { class: 'kp-icon-btn', 'aria-label': t('all'), onclick: show }, icon('back'));
    render(root, h('header', { class: 'kp-header' }, back, h('h1', { class: 'kp-title' }, t('title'))),
        h('div', { class: 'kp-content gallery-view' }, thumb(item),
            h('button', { class: 'kp-btn', onclick: () => viewMedia({ src: item.url, kind: item.kind }) }, t('full')),
            h('button', { class: 'kp-btn', 'data-variant': 'danger', onclick: async () => {
                if (!(await confirm({ title: t('deleteTitle'), message: t('deleteDetail'), confirmLabel: t('del'), danger: true }))) return;
                if (await attempt(async () => { await phone.callback('delete', { id: item.id }); return true; })) { items = items.filter(known => known.id !== item.id); phone.refresh().catch(() => {}); await show(); }
            } }, t('del'))));
}

function grid() {
    return h('div', { class: 'kp-content' },
        h('p', { class: 'kp-section-label' }, `${t('moments')} / ${items.length}`),
        h('div', { class: 'gallery-grid' }, items.map(item => h('button', { 'aria-label': item.kind === 'video' ? t('video') : t('photo'), onclick: () => view(item) }, thumb(item)))),
        next && h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: async () => {
            await attempt(async () => { const more = await phone.callback('list', { before: next }); items = items.concat(more.items); next = more.next; await show(true); });
        } }, t('older')));
}

async function show(keep) {
    const camera = h('button', { class: 'kp-icon-btn', 'aria-label': t('camera'), onclick: () => phone.open('camera') }, icon('camera'));
    const holder = h('div', { class: 'kp-app' }, states.loading());
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title')), camera), holder);
    try {
        if (!keep) { const first = await phone.callback('list', {}); items = first.items; next = first.next; }
        render(holder, items.length ? grid() : states.empty(t('emptyTitle'), t('emptyDetail')));
    } catch (error) {
        render(holder, states.error('Something went wrong', error.message, () => show()));
    }
}

ready().then(() => show()).catch(error => render(root, states.error('Could not start', error.message)));
