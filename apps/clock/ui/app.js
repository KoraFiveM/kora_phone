import { phone, ready, h, render, states, toast, confirm, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Clock', now: 'Right now', add: 'Add alarm', label: 'Label', time: 'Time', repeat: 'Repeat', save: 'Save alarm', all: 'All alarms', on: 'On', off: 'Off',
    once: 'Once', every: 'Every day', untitled: 'Untitled', repeatOnce: 'Leave every day unchecked to ring once, the next time this clock matches.', repeatDays: 'Repeats on the selected days.',
    emptyTitle: 'Set a reminder', emptyDetail: 'Alarms ring on your local clock, even with the phone closed. An alarm with no repeat days rings once.', deleteTitle: 'Delete this alarm?',
    deleteDetail: 'This cannot be undone.', del: 'Delete', edit: 'Edit alarm', ring: 'Alarm ringing', placeholder: 'Wake up' } });
const root = document.getElementById('app');
const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const newId = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };
const daysLabel = days => days.length === 7 ? t('every') : days.length ? [...days].sort().map(day => DAYS[day]).join(' ') : t('once');
const pad = value => String(value).padStart(2, '0');

let alarms = [];
let clockNode;
let ticker;

// The client script rings the alarms: tell it the list whenever it changes.
const push = () => phone.client('sync', alarms).catch(() => {});

async function save(alarm) {
    const stored = await attempt(() => phone.callback('save', alarm));
    if (!stored) return false;
    alarms = alarms.some(item => item.id === alarm.id) ? alarms.map(item => item.id === alarm.id ? alarm : item) : alarms.concat(alarm);
    await push();
    return true;
}

function row(alarm) {
    return h('li', null, h('div', { class: 'kp-row' }, icon('clock'),
        h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, alarm.time), h('span', { class: 'kp-row-sub' }, `${alarm.label || t('untitled')} · ${daysLabel(alarm.days)}`)),
        h('span', { class: 'alarm-actions' },
            h('button', { class: 'kp-btn', 'data-variant': alarm.enabled ? 'primary' : 'ghost', onclick: async () => { if (await save({ ...alarm, enabled: !alarm.enabled })) show(); } }, alarm.enabled ? t('on') : t('off')),
            h('button', { class: 'kp-icon-btn', 'aria-label': t('edit'), onclick: () => edit(alarm) }, icon('edit')),
            h('button', { class: 'kp-icon-btn', 'aria-label': t('del'), onclick: async () => {
                if (!(await confirm({ title: t('deleteTitle'), message: t('deleteDetail'), confirmLabel: t('del'), danger: true }))) return;
                if (await attempt(async () => { await phone.callback('remove', { id: alarm.id }); return true; })) { alarms = alarms.filter(item => item.id !== alarm.id); await push(); show(); }
            } }, icon('trash')))));
}

function edit(alarm) {
    const draft = { ...alarm, days: [...alarm.days] };
    const label = h('input', { class: 'kp-input', maxlength: 60, 'aria-label': t('label'), placeholder: t('placeholder'), value: draft.label });
    const time = h('input', { class: 'kp-input', type: 'time', required: true, 'aria-label': t('time'), value: draft.time });
    const days = h('div', { class: 'days' });
    const note = h('p', { class: 'kp-row-sub' });
    const paint = () => {
        render(days, DAYS.map((name, day) => h('button', { class: 'kp-btn', 'data-variant': draft.days.includes(day) ? 'primary' : 'ghost', 'aria-pressed': draft.days.includes(day),
            onclick: () => { draft.days = draft.days.includes(day) ? draft.days.filter(item => item !== day) : [...draft.days, day].sort(); paint(); } }, name)));
        note.textContent = draft.days.length ? t('repeatDays') : t('repeatOnce');
    };
    paint();
    render(root,
        h('header', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('all'), onclick: show }, icon('back')), h('h1', { class: 'kp-title' }, t('add'))),
        h('div', { class: 'kp-content' }, h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('label')), label), h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('time')), time),
            h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('repeat')), days), note),
        h('div', { class: 'kp-footer' }, h('button', { class: 'kp-btn kp-grow', 'data-variant': 'primary', onclick: async () => {
            if (!/^\d\d:\d\d$/.test(time.value)) return;
            if (await save({ ...draft, label: label.value.trim(), time: time.value })) show();
        } }, t('save'))));
}

async function show() {
    clearInterval(ticker);
    clockNode = h('p', { class: 'now' });
    const tick = () => { const now = new Date(); clockNode.textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}`; };
    tick(); ticker = setInterval(tick, 1000);
    const holder = h('div', { class: 'kp-content kp-flush' }, states.loading());
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title')), h('button', { class: 'kp-icon-btn', 'aria-label': t('add'), onclick: () => edit({ id: newId(), label: '', time: '08:00', days: [], enabled: true }) }, icon('plus'))),
        h('div', { class: 'kp-content' }, h('p', { class: 'kp-section-label' }, t('now')), clockNode), holder);
    try {
        alarms = await phone.callback('list');
        push();
        render(holder, alarms.length ? h('ul', { class: 'kp-list' }, alarms.map(row)) : states.empty(t('emptyTitle'), t('emptyDetail')));
    } catch (error) { render(holder, states.error('Something went wrong', error.message, show)); }
}

phone.on('ring', () => toast(t('ring')));

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
