import { phone, ready, h, render, states, toast, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Phone', keypad: 'Keypad', recent: 'Recent', placeholder: 'Enter number', hint: 'A little closer. One call away.', call: 'Call number',
    emptyTitle: 'Your first hello', emptyDetail: 'Your recent calls will appear here.', erase: 'Delete digit' } });
const root = document.getElementById('app');
const LETTERS = ['', 'ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ', '', '+', ''];
const day = seconds => { const date = new Date(Number(seconds) * 1000); return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };

let tab = 'keypad';
let number = '';
let names = {};

const nameOf = value => names[value] || '';

function keypad() {
    const input = h('input', { class: 'kp-input dial-number', inputmode: 'tel', maxlength: 16, 'aria-label': t('placeholder'), placeholder: t('placeholder'), value: number });
    const label = h('p', { class: 'kp-row-sub' }, nameOf(number) || t('hint'));
    const call = h('button', { class: 'kp-btn call-button', 'data-variant': 'primary', 'aria-label': t('call'), disabled: !/^\d{7,16}$/.test(number),
        onclick: () => phone.call(number).catch(error => toast(error.message)) }, icon('play'));
    const sync = () => { input.value = number; label.textContent = nameOf(number) || t('hint'); call.disabled = !/^\d{7,16}$/.test(number); };
    input.addEventListener('input', () => { number = input.value.replace(/\D/g, ''); sync(); });
    const keys = '123456789*0#'.split('').map((digit, index) => h('button', { class: 'kp-btn', onclick: () => { number = (number + digit).slice(0, 16); sync(); } },
        h('span', null, digit), h('small', null, LETTERS[index])));
    return h('div', { class: 'kp-content dialer' }, input, label, h('div', { class: 'keypad' }, keys),
        h('div', { class: 'kp-row-flex' }, call, h('button', { class: 'kp-icon-btn', 'aria-label': t('erase'), onclick: () => { number = number.slice(0, -1); sync(); } }, icon('x'))));
}

async function recent(holder) {
    render(holder, states.loading());
    try {
        const result = await phone.callback('recent');
        if (!result.items.length) return render(holder, states.empty(t('emptyTitle'), t('emptyDetail')));
        render(holder, h('ul', { class: 'kp-list' }, result.items.map(call => {
            const incoming = call.calleeNumber === result.number;
            const peer = incoming ? call.callerNumber : call.calleeNumber;
            return h('li', null, h('button', { class: 'kp-row', onclick: () => { number = peer; tab = 'keypad'; show(); } },
                icon(incoming ? 'back' : 'forward'),
                h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, nameOf(peer) || peer), h('span', { class: 'kp-row-sub' }, `${call.status} · ${day(call.startedAt)}`))));
        })));
    } catch (error) {
        render(holder, states.error('Something went wrong', error.message, () => recent(holder)));
    }
}

async function show() {
    const tabs = h('div', { class: 'kp-segmented', role: 'group', 'aria-label': t('title') },
        [['keypad', t('keypad')], ['recent', t('recent')]].map(([id, label]) => h('button', { 'aria-pressed': tab === id, onclick: () => { tab = id; show(); } }, label)));
    const holder = h('div', { class: 'kp-content kp-flush' });
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))), h('div', { class: 'kp-content' }, tabs), holder);
    if (tab === 'keypad') render(holder, keypad()); else await recent(holder);
}

ready().then(async init => {
    if (init.target && /^\d{1,16}$/.test(init.target)) number = init.target;
    names = Object.fromEntries((await phone.contacts.list().catch(() => [])).map(contact => [contact.number, contact.name]));
    await show();
}).catch(error => render(root, states.error('Could not start', error.message)));
