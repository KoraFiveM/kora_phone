import { phone, ready, h, render, states, load, i18n } from '/sdk/runtime/kit.js';

const t = i18n({
    en: { title: 'Garage', status: 'Status', fuel: 'Fuel', garaged: 'Garaged', impounded: 'Impounded', out: 'Out', unknown: 'Unknown garage',
        last: 'Last registered garage', emptyTitle: 'The road is waiting', emptyDetail: 'Your character’s owned vehicles will appear here.', error: 'Garage is unavailable' },
});
const root = document.getElementById('app');
const STATUS = { 1: 'garaged', 2: 'impounded' };

const card = vehicle => h('section', { class: 'kp-card' },
    h('div', { class: 'kp-row-flex' },
        h('h2', { class: 'kp-row-title kp-grow' }, vehicle.vehicle),
        h('span', { class: 'kp-badge vehicle-plate' }, vehicle.plate)),
    h('div', { class: 'vehicle-stats' },
        h('div', null, h('small', { class: 'kp-label' }, t('status')), h('strong', null, t(STATUS[vehicle.state] || 'out'))),
        h('div', null, h('small', { class: 'kp-label' }, t('fuel')), h('strong', null, `${Math.round(vehicle.fuel)}%`))),
    h('p', { class: 'kp-row-sub' }, `${vehicle.garage || t('unknown')} · ${t('last')}`));

async function show() {
    const body = h('div', { class: 'kp-content' });
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))), body);
    await load(body, () => phone.callback('list'), vehicles => h('div', { class: 'kp-content kp-flush' }, vehicles.map(card)),
        { empty: vehicles => vehicles.length === 0 && [t('emptyTitle'), t('emptyDetail')] });
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
