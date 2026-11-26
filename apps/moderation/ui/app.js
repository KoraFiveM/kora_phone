import { phone, ready, h, render, states, load, toast, i18n } from '/sdk/runtime/kit.js';
import { popupNote } from './note.js';

const t = i18n({ en: { title: 'Moderation', open: 'Open', reviewing: 'Reviewing', reports: 'Reports', refresh: 'Refresh', dismiss: 'Dismiss', removeContent: 'Remove content',
    suspend: 'Suspend profile', gone: 'The reported content is no longer available.', emptyTitle: 'All clear', emptyDetail: 'No reports need review right now.', handled: 'Report handled' } });
const root = document.getElementById('app');
let status = 'open';

const words = value => String(value).replace(/_/g, ' ');
const day = seconds => { const date = new Date(Number(seconds) * 1000); return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
const actionsFor = report => [{ id: 'dismiss', label: t('dismiss') },
    report.targetType === 'profile' ? { id: 'suspend_profile', label: t('suspend') } : { id: 'remove_content', label: t('removeContent') }];

// The server snapshots whatever was reported at report time, so a moderator sees it even if it was edited later.
function preview(report) {
    const shot = report.snapshot || {};
    const text = key => (typeof shot[key] === 'string' ? shot[key] : '');
    if (report.targetType === 'listing') return [text('title'), typeof shot.price === 'number' ? `$${shot.price}` : '', text('description')].filter(Boolean).join('\n');
    if (report.targetType === 'profile') return [text('displayName'), text('handle') && `@${text('handle')}`, text('bio')].filter(Boolean).join('\n');
    return text('body');
}

function card(report) {
    return h('section', { class: 'kp-card' },
        h('h2', { class: 'kp-row-title' }, `${words(report.targetType)} · ${words(report.reason)}`),
        h('small', { class: 'kp-row-sub' }, `${day(report.createdAt)} · #${report.id}`),
        h('p', { class: 'report-body' }, preview(report) || t('gone')),
        report.details && h('p', { class: 'kp-row-sub' }, `“${report.details}”`),
        h('div', { class: 'report-actions' }, actionsFor(report).map(action => h('button', { class: 'kp-btn', 'data-variant': action.id === 'dismiss' ? undefined : 'danger', onclick: async () => {
            const note = await popupNote({ title: `${action.label}?` });
            if (!note) return;
            try { await phone.callback('resolve', { reportId: report.id, action: action.id, note }); toast(t('handled')); await show(); } catch (error) { toast(error.message); }
        } }, action.label))));
}

async function show() {
    const tabs = h('div', { class: 'kp-segmented' }, [['open', t('open')], ['reviewing', t('reviewing')]].map(([id, label]) =>
        h('button', { 'aria-pressed': status === id, onclick: () => { status = id; show(); } }, label)));
    const holder = h('div', { class: 'kp-content kp-flush' });
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))),
        h('div', { class: 'kp-content' }, tabs), holder);
    await load(holder, () => phone.callback('queue', { status }), reports => h('div', { class: 'kp-content' }, reports.map(card)),
        { empty: reports => reports.length === 0 && [t('emptyTitle'), t('emptyDetail')] });
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
