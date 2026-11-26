import { phone, ready, h, render, states, load, toast, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({
    en: { title: 'Wallet', money: 'Money', id: 'ID & licences', available: 'Available balance', send: 'Send money', recipient: 'Recipient phone number',
        amount: 'Amount', review: 'Review transfer', confirm: 'Confirm transfer', retry: 'Check / retry same transfer', edit: 'Edit details',
        off: 'Transfers are turned off on this server. Your balance and history are still here.', online: 'The recipient must be online.',
        sameRef: 'This request keeps the same reference. Check its status before making another transfer.', activity: 'Recent activity',
        to: 'To', from: 'From', emptyTitle: 'A clean slate', emptyDetail: 'Your phone transfers will appear here.',
        done: 'Transfer completed', other: 'Transfer {status}. {next}', pendingNext: 'Contact an administrator before sending again.', noAction: 'No further action was taken.',
        dob: 'Date of birth', citizen: 'Citizen ID', nation: 'Nationality', job: 'Occupation', licences: 'Licences', valid: 'Valid', notHeld: 'Not held',
        show: 'Show my ID to the person next to me', shown: 'Shown to the person next to you', close: 'Only someone standing close by will see it.' },
});
const root = document.getElementById('app');
const money = value => new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(value);
const day = value => { const date = new Date(value); return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
const requestId = () => `w-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

let tab = 'money';
let names = {};

function shell(body) {
    const tabs = h('div', { class: 'kp-segmented', role: 'group', 'aria-label': t('title') },
        [['money', t('money')], ['id', t('id')]].map(([id, label]) => h('button', { 'aria-pressed': tab === id, onclick: () => { tab = id; show(); } }, label)));
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))), h('div', { class: 'kp-content', id: 'body' }, tabs, body));
    return document.getElementById('body');
}

function transferForm(bank, reload) {
    let recipient = '', amount = '', reviewing = false, attempted = false, reference = requestId();
    const form = h('div', { class: 'kp-card' });
    const paint = () => {
        const to = h('input', { class: 'kp-input', inputmode: 'numeric', maxlength: 16, 'aria-label': t('recipient'), placeholder: '555…', value: recipient, disabled: reviewing });
        const sum = h('input', { class: 'kp-input', inputmode: 'numeric', type: 'number', min: 1, step: 1, 'aria-label': t('amount'), placeholder: '$ 0', value: amount, disabled: reviewing });
        to.addEventListener('input', () => { recipient = to.value.replace(/\D/g, ''); });
        sum.addEventListener('input', () => { amount = sum.value; });
        const send = async () => {
            try {
                const result = await phone.callback('transfer', { to: recipient, amount: Number(amount), clientRequestId: reference });
                attempted = true;
                toast(result.status === 'completed' ? t('done') : t('other', { status: result.status, next: result.status === 'pending' ? t('pendingNext') : t('noAction') }));
                if (result.status !== 'pending') { reviewing = false; attempted = false; amount = ''; reference = requestId(); }
                await reload();
            } catch (error) { attempted = true; toast(error.message); paint(); }
        };
        form.replaceChildren(
            h('h2', { class: 'kp-row-title' }, t('send')),
            h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('recipient')), to),
            h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('amount')), sum),
            reviewing
                ? h('div', { class: 'kp-field' }, h('p', null, `${money(Number(amount))} → ${recipient}`), h('small', { class: 'kp-label' }, t('online')),
                    h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: send }, attempted ? t('retry') : t('confirm')),
                    !attempted && h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => { reviewing = false; paint(); } }, t('edit')),
                    attempted && h('p', { class: 'kp-row-sub' }, t('sameRef')))
                : h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: () => { if (recipient && Number(amount) > 0) { reviewing = true; paint(); } } }, t('review')));
    };
    paint();
    return form;
}

function moneyView(bank, reload) {
    return [
        h('div', { class: 'kp-card' }, h('small', { class: 'kp-label' }, t('available')), h('p', { class: 'wallet-balance' }, money(bank.balance)),
            h('span', { class: 'wallet-account' }, `${bank.holder} · •• ${String(bank.account).slice(-4)}`)),
        bank.transfers ? transferForm(bank, reload) : h('div', { class: 'kp-card' }, h('h2', { class: 'kp-row-title' }, t('send')), h('p', { class: 'kp-row-sub' }, t('off'))),
        h('p', { class: 'kp-section-label' }, t('activity')),
        bank.history.length
            ? h('ul', { class: 'kp-list' }, bank.history.map(item => {
                const incoming = item.direction === 'incoming';
                return h('li', null, h('div', { class: 'kp-row' },
                    icon(incoming ? 'back' : 'forward'),
                    h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, `${incoming ? t('from') : t('to')} ${names[item.peer] || item.peer}`),
                        h('span', { class: 'kp-row-sub' }, `${item.status} · ${day(item.createdAt * 1000)}`)),
                    h('strong', { class: 'wallet-amount', 'data-direction': incoming ? 'in' : 'out' }, `${incoming ? '+' : '−'}${money(item.amount)}`)));
            }))
            : states.empty(t('emptyTitle'), t('emptyDetail')),
    ];
}

function idView(card) {
    const field = (label, value) => h('div', null, h('dt', null, label), h('dd', null, value || '—'));
    return [
        h('div', { class: 'kp-card wallet-id' }, h('h2', { class: 'kp-row-title' }, card.name),
            h('dl', null, field(t('dob'), card.birthdate), field(t('citizen'), card.citizenId), field(t('nation'), card.nationality), field(t('job'), card.job))),
        h('p', { class: 'kp-section-label' }, t('licences')),
        h('ul', { class: 'kp-list' }, (card.licences || []).map(licence => h('li', null, h('div', { class: 'kp-row' },
            icon(licence.valid ? 'check' : 'x'),
            h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, licence.label), h('span', { class: 'kp-row-sub' }, licence.valid ? t('valid') : t('notHeld'))))))),
        h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
            try { await phone.callback('showId'); toast(t('shown')); } catch (error) { toast(error.message); }
        } }, t('show')),
        h('small', { class: 'kp-label' }, t('close')),
    ];
}

async function show() {
    const body = shell(h('div'));
    const holder = h('div', { class: 'kp-content kp-flush' });
    body.lastChild.replaceWith(holder);
    if (tab === 'money') {
        names = Object.fromEntries((await phone.contacts.list().catch(() => [])).map(contact => [contact.number, contact.name]));
        await load(holder, () => phone.callback('overview'), bank => h('div', { class: 'kp-content' }, moneyView(bank, show)), { empty: () => false });
    } else {
        await load(holder, () => phone.callback('idCard'), card => h('div', { class: 'kp-content' }, idView(card)), { empty: () => false });
    }
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
