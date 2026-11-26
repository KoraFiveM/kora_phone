import { phone, ready, h, render, states, toast, confirm, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Mail', inbox: 'Inbox', activity: 'Activity', note: 'System mail follows your character across handsets.',
    activityNote: 'Informational activity. These notes do not change your balance.', from: 'From', accept: 'Accept', del: 'Delete', older: 'Older mail', olderActivity: 'Older activity',
    emptyTitle: 'Nothing new', emptyDetail: 'Job offers, invoices and updates arrive here.', noActivity: 'No activity yet', noActivityDetail: 'Transaction notes from city services appear here.',
    deleteTitle: 'Delete this mail?', deleteDetail: 'This cannot be undone.', unread: 'Unread' } });
const root = document.getElementById('app');
const PAGE = 50;
const day = seconds => { const date = new Date(Number(seconds) * 1000); return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
let tab = 'inbox';

function shell(title, leading, body) {
    render(root, h('header', { class: 'kp-header' }, leading, h('h1', { class: 'kp-title' }, title)), body);
}

/** A list that shows loading, empty and error states and appends older pages when the last page was full. */
async function pagedList(holder, callbackName, row, emptyText, olderLabel) {
    render(holder, states.loading());
    let items;
    try {
        items = await phone.callback(callbackName, {});
    } catch (error) {
        render(holder, states.error('Something went wrong', error.message, () => pagedList(holder, callbackName, row, emptyText, olderLabel)));
        return;
    }
    if (!items.length) { render(holder, states.empty(...emptyText)); return; }
    const paint = () => render(holder, h('ul', { class: 'kp-list' }, items.map(row)),
        items.length % PAGE === 0 && h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: async () => {
            try { items = items.concat(await phone.callback(callbackName, { before: items[items.length - 1].id })); paint(); } catch (error) { toast(error.message); }
        } }, olderLabel));
    paint();
}

function openMail(item) {
    const back = h('button', { class: 'kp-icon-btn', 'aria-label': t('inbox'), onclick: showList }, icon('back'));
    const accept = item.hasAction && h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
        try { await phone.callback('accept', { id: item.id }); item.hasAction = false; openMail(item); } catch (error) { toast(error.message); }
    } }, t('accept'));
    const remove = h('button', { class: 'kp-btn', 'data-variant': 'danger', onclick: async () => {
        if (!(await confirm({ title: t('deleteTitle'), message: t('deleteDetail'), confirmLabel: t('del'), danger: true }))) return;
        try { await phone.callback('delete', { id: item.id }); await showList(); } catch (error) { toast(error.message); }
    } }, t('del'));
    shell(item.subject, back, h('div', { class: 'kp-content' },
        h('p', { class: 'kp-row-sub' }, `${t('from')} ${item.peer} · ${day(item.createdAt)}`),
        h('p', { class: 'mail-body' }, item.body), accept, remove));
    if (item.unread) { item.unread = false; phone.callback('read', { id: item.id }).catch(() => {}); }
}

async function showList() {
    const tabs = h('div', { class: 'kp-segmented', role: 'group', 'aria-label': t('title') },
        [['inbox', t('inbox')], ['activity', t('activity')]].map(([id, label]) => h('button', { 'aria-pressed': tab === id, onclick: () => { tab = id; showList(); } }, label)));
    const holder = h('div', { class: 'kp-content kp-flush' });
    shell(t('title'), null, h('div', { class: 'kp-app' }, h('div', { class: 'kp-content' }, tabs, h('p', { class: 'kp-row-sub' }, tab === 'inbox' ? t('note') : t('activityNote'))), holder));
    if (tab === 'inbox') {
        await pagedList(holder, 'inbox', item => h('li', null, h('button', { class: 'kp-row', onclick: () => openMail(item) },
            h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, item.subject), h('span', { class: 'kp-row-sub' }, `${t('from')} ${item.peer} · ${day(item.createdAt)}`)),
            item.unread && h('i', { class: 'mail-dot', 'aria-label': t('unread') }))), [t('emptyTitle'), t('emptyDetail')], t('older'));
    } else {
        await pagedList(holder, 'activity', item => h('li', null, h('div', { class: 'kp-row' },
            h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, item.title), h('span', { class: 'mail-body kp-row-sub' }, item.message), h('small', { class: 'kp-row-sub' }, day(item.createdAt))))),
            [t('noActivity'), t('noActivityDetail')], t('olderActivity'));
    }
}

ready().then(showList).catch(error => render(root, states.error('Could not start', error.message)));
