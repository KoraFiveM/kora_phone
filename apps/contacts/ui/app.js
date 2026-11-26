import { phone, ready, h, render, states, toast, confirm, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: 'Contacts', search: 'Find your people', add: 'Add contact', circle: 'Your circle', name: 'Name', number: 'Number', photo: 'Contact photo', save: 'Save contact',
    call: 'Call', message: 'Message', edit: 'Edit', del: 'Delete', fav: 'Favourite', unfav: 'Remove from favourites', deleteTitle: 'Delete this contact?', deleteDetail: 'This cannot be undone.',
    emptyTitle: 'Make a connection', emptyDetail: 'Add a number to start building your circle.', none: 'No photo', saved: 'Contact saved', back: 'Back' } });
const root = document.getElementById('app');
let contacts = [];
let search = '';

const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };
const reload = async () => { contacts = await phone.callback('list'); };
const changed = async () => { await reload(); phone.refresh().catch(() => {}); };

function avatar(contact) {
    return contact.photo ? h('img', { class: 'contact-photo', src: contact.photo, alt: '' }) : h('span', { class: 'contact-photo' });
}

function row(contact) {
    const fav = contact.isFavorite === 1 || contact.isFavorite === true;
    const save = overrides => attempt(async () => {
        await phone.callback('save', { id: contact.id, name: contact.displayName, number: contact.phoneNumber, favorite: fav, avatarMediaId: contact.avatarMediaId || undefined, ...overrides });
        await changed(); paint();
    });
    return h('li', null,
        h('div', { class: 'kp-row' }, avatar(contact), h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, contact.displayName), h('span', { class: 'kp-row-sub' }, contact.phoneNumber))),
        h('div', { class: 'contact-actions' },
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', 'aria-pressed': fav, 'aria-label': fav ? t('unfav') : t('fav'), onclick: () => save({ favorite: !fav }) }, fav ? '★' : '☆'),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => phone.open('phone', contact.phoneNumber) }, t('call')),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => phone.open('messages', contact.phoneNumber) }, t('message')),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => edit(contact) }, t('edit')),
            h('button', { class: 'kp-btn', 'data-variant': 'danger', 'aria-label': t('del'), onclick: async () => {
                if (!(await confirm({ title: t('deleteTitle'), message: t('deleteDetail'), confirmLabel: t('del'), danger: true }))) return;
                await attempt(async () => { await phone.callback('delete', { id: contact.id }); await changed(); paint(); });
            } }, icon('trash'))));
}

const matches = contact => `${contact.displayName} ${contact.phoneNumber}`.toLowerCase().includes(search.toLowerCase());
const ordered = () => contacts.filter(matches).sort((a, b) => Number(!!b.isFavorite) - Number(!!a.isFavorite) || a.displayName.localeCompare(b.displayName));

async function edit(contact) {
    let photos = [];
    try { photos = await phone.callback('photos'); } catch { /* no gallery: the contact just has no photo */ }
    let mediaId = contact && contact.avatarMediaId ? Number(contact.avatarMediaId) : undefined;
    const name = h('input', { class: 'kp-input', maxlength: 60, 'aria-label': t('name'), placeholder: t('name'), value: contact ? contact.displayName : '' });
    const number = h('input', { class: 'kp-input', inputmode: 'tel', maxlength: 16, 'aria-label': t('number'), placeholder: t('number'), value: contact ? contact.phoneNumber : '' });
    const grid = h('div', { class: 'photo-grid' });
    const paintPhotos = () => render(grid, photos.map(photo => h('button', { 'aria-pressed': mediaId === Number(photo.id), 'aria-label': t('photo'),
        onclick: () => { mediaId = mediaId === Number(photo.id) ? undefined : Number(photo.id); paintPhotos(); } }, h('img', { src: photo.url, alt: '' }))));
    paintPhotos();
    render(root,
        h('header', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('back'), onclick: show }, icon('back')), h('h1', { class: 'kp-title' }, contact ? t('edit') : t('add'))),
        h('div', { class: 'kp-content' }, h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('name')), name), h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('number')), number),
            photos.length > 0 && h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('photo')), grid)),
        h('div', { class: 'kp-footer' }, h('button', { class: 'kp-btn kp-grow', 'data-variant': 'primary', onclick: async () => {
            const ok = await attempt(async () => {
                await phone.callback('save', { id: contact && contact.id, name: name.value.trim(), number: number.value.replace(/\D/g, ''), favorite: contact ? !!contact.isFavorite : false, avatarMediaId: mediaId });
                await changed(); return true;
            });
            if (ok) { toast(t('saved')); show(); }
        } }, t('save'))));
}

function paint() {
    const list = document.getElementById('list');
    if (!list) return;
    const shown = ordered();
    render(list, shown.length ? h('ul', { class: 'kp-list' }, shown.map(row)) : states.empty(t('emptyTitle'), t('emptyDetail')));
}

async function show() {
    const input = h('input', { class: 'kp-input', 'aria-label': t('search'), placeholder: t('search'), value: search });
    input.addEventListener('input', () => { search = input.value; paint(); });
    const add = h('button', { class: 'kp-icon-btn', 'aria-label': t('add'), onclick: () => edit(undefined) }, icon('plus'));
    const list = h('div', { id: 'list', class: 'kp-content kp-flush' }, states.loading());
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title')), add), h('div', { class: 'kp-content' }, input, h('p', { class: 'kp-section-label' }, t('circle'))), list);
    try { await reload(); paint(); } catch (error) { render(list, states.error('Something went wrong', error.message, show)); }
}

ready().then(show).catch(error => render(root, states.error('Could not start', error.message)));
