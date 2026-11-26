import { phone, ready, h, render, states, load, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({
    en: { title: 'Weather', now: 'Los Santos / right now', clock: 'In-game time', rain: 'Rain intensity', world: 'Current world conditions', refresh: 'Refresh conditions',
        EXTRASUNNY: 'Extra sunny', CLEAR: 'Clear skies', CLOUDS: 'Cloudy', OVERCAST: 'Overcast', RAIN: 'Rain', THUNDER: 'Thunderstorms', SMOG: 'Smog', FOGGY: 'Fog',
        CLEARING: 'Clearing up', NEUTRAL: 'Calm', SNOW: 'Snow', BLIZZARD: 'Blizzard', SNOWLIGHT: 'Light snow', XMAS: 'Snow', HALLOWEEN: 'Eerie' },
});
const root = document.getElementById('app');
const pad = value => String(value).padStart(2, '0');

function view(weather, reload) {
    return h('div', { class: 'kp-content weather' },
        h('p', { class: 'kp-section-label' }, t('now')),
        icon('sun'),
        h('h2', { class: 'weather-condition' }, t(weather.condition) === weather.condition ? weather.condition.toLowerCase() : t(weather.condition)),
        h('small', { class: 'kp-label' }, t('clock')),
        h('div', { class: 'weather-time' }, `${pad(weather.hour)}:${pad(weather.minute)}`),
        h('div', { class: 'kp-card' }, h('div', { class: 'kp-row-flex' },
            h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, t('rain')), h('span', { class: 'kp-row-sub' }, t('world'))),
            h('strong', null, `${Math.round(weather.rain * 100)}%`))),
        h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: reload }, t('refresh')));
}

async function show() {
    const body = h('div', { class: 'kp-app' });
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))), body);
    await load(body, () => phone.client('get'), weather => view(weather, show), { empty: () => false });
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
