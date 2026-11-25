import { phone, ready, h, render, states, toast, confirm, menu, prompt, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Market', add: 'List an item', titleField: 'Title', descriptionField: 'Description', priceField: 'Asking price ($)', list: 'List item',
    you: 'You', contact: 'Contact seller', report: 'Report', sold: 'Mark sold', remove: 'Remove', removeTitle: 'Remove this listing?', removeDetail: 'It leaves the marketplace for everyone.',
    emptyTitle: 'Room for something new', emptyDetail: 'List an item to get the marketplace started.', older: 'Load older listings', hi: 'Hi, is this still available?',
    contactTitle: 'Message the seller', sent: 'Message sent', reportTitle: 'Report this listing', reported: 'Report sent. Thank you.', marked: 'Marked as sold', listed: 'Listed',
    scam: 'Scam', spam: 'Spam', harassment: 'Harassment', illegal: 'Illegal', other: 'Other' } });
const root = document.getElementById('app');
const PAGE = 30;
const REASONS = ['scam', 'spam', 'harassment', 'illegal', 'other'];
const ref = () => `m-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
const money = value => new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(value);
const day = seconds => { const date = new Date(Number(seconds) * 1000); return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };

let listings = [];
let me = { number: '', moderator: false };

async function load(before) {
    const result = await phone.callback('list', before ? { before } : {});
    me = { number: result.number, moderator: result.moderator };
    return result.items;
}

function card(item) {
    const mine = item.isOwner === true || item.isOwner === 1;
    const actions = mine
        ? [h('button', { class: 'kp-btn', onclick: () => attempt(async () => { await phone.callback('sold', { id: item.id }); toast(t('marked')); await show(); }) }, t('sold'))]
        : [h('button', { class: 'kp-btn', onclick: () => contactSeller(item) }, t('contact')), h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => reportListing(item) }, t('report'))];
    return h('section', { class: 'kp-card' },
        h('div', { class: 'kp-row-flex' },
            h('div', { class: 'kp-grow' }, h('h2', { class: 'kp-row-title' }, item.title), h('small', { class: 'kp-row-sub' }, `${mine ? t('you') : item.sellerHandle || item.sellerName || ''} · ${day(item.createdAt)}`)),
            (mine || me.moderator) && h('button', { class: 'kp-icon-btn', 'aria-label': t('remove'), onclick: async () => {
                if (await confirm({ title: t('removeTitle'), message: t('removeDetail'), confirmLabel: t('remove'), danger: true })) await attempt(async () => { await phone.callback('remove', { id: item.id }); await show(); });
            } }, icon('trash'))),
        item.description && h('p', { class: 'listing-body' }, item.description),
        h('strong', { class: 'listing-price' }, money(item.price)),
        h('div', { class: 'listing-actions' }, actions));
}

async function contactSeller(item) {
    const message = await prompt({ title: t('contactTitle'), value: t('hi'), confirmLabel: t('contact') });
    if (!message || !message.trim()) return;
    if (await attempt(async () => { await phone.callback('contact', { id: item.id, message, clientRequestId: ref() }); return true; })) {
        toast(t('sent'));
        phone.open('messages').catch(() => {});
    }
}

async function reportListing(item) {
    const reason = await menu({ title: t('reportTitle'), items: REASONS.map(value => ({ label: t(value), value })) });
    if (!reason) return;
    const details = (await prompt({ title: t('reportTitle'), label: 'Details', confirmLabel: t('report') })) || '';
    await attempt(async () => { await phone.callback('report', { id: item.id, reason, details }); toast(t('reported')); });
}

function composer() {
    const title = h('input', { class: 'kp-input', maxlength: 80, 'aria-label': t('titleField'), placeholder: t('titleField') });
    const description = h('textarea', { class: 'kp-input', maxlength: 1900, 'aria-label': t('descriptionField'), placeholder: t('descriptionField') });
    const price = h('input', { class: 'kp-input', type: 'number', min: 0, max: 100000000, step: 1, 'aria-label': t('priceField'), placeholder: t('priceField') });
    return h('div', { class: 'kp-card' }, h('h2', { class: 'kp-row-title' }, t('add')), title, description, price,
        h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: () => {
            if (!title.value.trim()) return;
            attempt(async () => { await phone.callback('create', { title: title.value.trim(), description: description.value, price: Number(price.value) || 0, clientRequestId: ref() }); toast(t('listed')); await show(); });
        } }, t('list')));
}

async function show() {
    const holder = h('div', { class: 'kp-content' });
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))), holder);
    render(holder, states.loading());
    try {
        listings = await load();
    } catch (error) {
        render(holder, states.error('Something went wrong', error.message, show));
        return;
    }
    const paint = () => render(holder, composer(),
        listings.length ? listings.map(card) : states.empty(t('emptyTitle'), t('emptyDetail')),
        listings.length >= PAGE && h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => attempt(async () => {
            const older = await load(Math.min(...listings.map(item => item.id)));
            listings = listings.concat(older.filter(item => !listings.some(known => known.id === item.id)));
            paint();
        }) }, t('older')));
    paint();
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
