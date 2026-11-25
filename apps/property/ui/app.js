import { phone, ready, h, render, states, load, toast, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Home', owned: 'Owned by your current character', go: 'Take me home', set: 'Home waypoint selected',
    emptyTitle: 'Find your place', emptyDetail: 'Properties you own will appear here.' } });
const root = document.getElementById('app');

const card = property => h('section', { class: 'kp-card property-card' },
    icon('home'),
    h('h2', { class: 'kp-row-title' }, property.label || property.name),
    h('p', { class: 'kp-row-sub' }, t('owned')),
    property.coords && h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
        try { await phone.client('waypoint', property.coords); toast(t('set')); } catch (error) { toast(error.message); }
    } }, t('go')));

async function show() {
    const body = h('div', { class: 'kp-content' });
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))), body);
    await load(body, () => phone.callback('list'), list => h('div', { class: 'kp-content kp-flush' }, list.map(card)),
        { empty: list => list.length === 0 && [t('emptyTitle'), t('emptyDetail')] });
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
