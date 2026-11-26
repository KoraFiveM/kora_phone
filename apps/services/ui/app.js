import { phone, ready, h, render, states, load, toast, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Work', role: 'Current role', on: 'On duty', off: 'Off duty', goOn: 'Go on duty', goOff: 'Go off duty',
    nowOn: 'You are on duty', nowOff: 'You are off duty', done: '{label} completed', grade: 'Grade {level}', actions: 'Actions' } });
const root = document.getElementById('app');
const text = value => (typeof value === 'string' && value ? value : '');

/** kora_core grades are one-based and carry a name; older payloads send a number plus gradeLabel. */
function gradeText(job) {
    const grade = job.grade;
    if (grade && typeof grade === 'object') return text(grade.label) || text(grade.name) || t('grade', { level: typeof grade.level === 'number' ? grade.level : '' }).trim();
    return job.gradeLabel || t('grade', { level: grade });
}

function view(work, reload) {
    const job = work.job;
    const run = async (call, message) => {
        try { await call(); if (message) toast(message); await reload(); } catch (error) { toast(error.message); }
    };
    return h('div', { class: 'kp-content' },
        h('section', { class: 'kp-card' },
            h('p', { class: 'kp-section-label' }, t('role')),
            h('h2', { class: 'kp-row-title' }, job.label || job.name),
            h('p', { class: 'kp-row-sub' }, `${gradeText(job)} · ${job.onDuty ? t('on') : t('off')}`),
            h('button', { class: 'kp-btn', 'data-variant': 'primary', disabled: job.dutyLocked === true,
                onclick: () => run(() => phone.callback('setDuty', { onDuty: !job.onDuty }), job.onDuty ? t('nowOff') : t('nowOn')) },
                job.onDuty ? t('goOff') : t('goOn'))),
        work.actions && work.actions.length > 0 && h('div', { class: 'work-actions' },
            h('p', { class: 'kp-section-label' }, t('actions')),
            work.actions.map(action => h('button', { class: 'kp-btn',
                onclick: () => run(() => phone.callback('runAction', { action: action.id }), t('done', { label: action.label })) }, action.label))));
}

async function show() {
    const body = h('div', { class: 'kp-app' });
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))), body);
    await load(body, () => phone.callback('get'), work => view(work, show), { empty: () => false });
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
