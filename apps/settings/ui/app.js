import { phone, ready, h, render, states, toast, icon, i18n } from '/sdk/runtime/kit.js';
import { WALLPAPERS, PHONE_CASES, ICON_STYLES, APPEARANCES, appearanceOf, IDENTITY, iconStyleOf, isQuiet } from './data.js';
import { mountHandset } from './handset.js';

const t = i18n({ en: { title: 'Settings', all: 'All settings', intro: 'Make it feel like yours.', appearance: 'Appearance', connections: 'Connections', cloud: 'Cloud account', privacy: 'Privacy & security',
    sound: 'Sound & alerts', about: 'About & resale', idle: 'Changes save automatically', saving: 'Saving changes…', saved: 'All changes saved', error: 'Could not save. Try your change again.' } });
const root = document.getElementById('app');
const STATUS = { idle: 'idle', saving: 'saving', saved: 'saved', error: 'error' };
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };

let me = { settings: {}, model: 'standard', hasPin: false, number: '' };
let area;
let status = STATUS.idle;
let queue = Promise.resolve();
let version = 0;
let contacts = [];
let photos = [];

const identity = () => IDENTITY[me.model] || IDENTITY.standard;
const statusNode = () => document.getElementById('save-state');
function paintStatus() { const node = statusNode(); if (node) { node.dataset.status = status; node.textContent = t(status); } }

/** Saves one change. Writes are queued one after another so a quick slider never overtakes an earlier save. */
function change(patch) {
    me.settings = { ...me.settings, ...patch };
    const next = me.settings;
    if (!String(next.name || '').trim() || (next.wallpaper === 'custom' && !next.wallpaperUrl) || (next.phoneCase === 'custom' && !next.phoneCaseUrl)) return;
    const mine = ++version;
    status = STATUS.saving; paintStatus();
    queue = queue.then(() => new Promise(resolve => setTimeout(resolve, 300))).then(async () => {
        try {
            const saved = await phone.system('settings.save', { patch });
            if (saved && typeof saved === 'object') me.settings = { ...me.settings, ...saved };
            if (mine === version) { status = STATUS.saved; paintStatus(); }
        } catch (error) {
            if (mine === version) { status = STATUS.error; paintStatus(); }
            toast(error.message);
        }
    });
}

const field = (label, control) => h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, label), control);
const section = (title, ...children) => h('section', { class: 'kp-card', 'aria-label': title }, h('h3', { class: 'kp-row-title' }, title), ...children);
const note = text => h('p', { class: 'kp-row-sub' }, text);

function range(label, value, min, max, step, format, onchange) {
    const out = h('output', null, format(value));
    const input = h('input', { type: 'range', min, max, step, value, 'aria-label': label });
    input.addEventListener('input', () => { out.textContent = format(Number(input.value)); onchange(Number(input.value)); });
    return h('label', { class: 'range' }, h('span', null, label, ' ', out), input);
}

function choices(list, current, onpick, wide) {
    return h('div', { class: wide ? 'swatches' : 'kp-segmented' }, list.map(([id, label, swatch]) => h('button', { 'aria-pressed': current === id, onclick: () => { onpick(id); repaintArea(); } },
        swatch ? h('span', { class: 'swatch', style: `background:${swatch}` }) : null, label)));
}

function photoPicker(label, current, onpick) {
    const url = h('input', { class: 'kp-input', 'aria-label': `${label} link`, placeholder: label, value: current || '' });
    url.addEventListener('change', () => onpick(url.value.trim()));
    return h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, label), url,
        photos.length ? h('div', { class: 'photo-grid' }, photos.map(photo => h('button', { 'aria-pressed': current === photo.url, 'aria-label': label, onclick: () => { onpick(photo.url); repaintArea(); } }, h('img', { src: photo.url, alt: '' })))) : null,
        current ? h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => { onpick(''); repaintArea(); } }, 'Remove image') : null);
}

// Areas ------------------------------------------------------------------------------------------------------
function appearanceArea() {
    const s = me.settings;
    const appearance = appearanceOf(s.theme);
    const nodes = [
        section('Appearance', choices(APPEARANCES, appearance, id => change({ theme: id })), note('The accent colour comes from the server theme. Use /theme to pick your own.'),
            h('p', { class: 'kp-section-label' }, 'Wallpaper'),
            choices(WALLPAPERS.map(item => [item.id, item.label, item.swatch]), s.wallpaper, id => { if (id !== 'custom' || s.wallpaperUrl) change({ wallpaper: id }); else me.settings = { ...s, wallpaper: 'custom' }; }, true),
            s.wallpaper === 'custom' ? photoPicker('Wallpaper photo', s.wallpaperUrl, url => change({ wallpaper: url ? 'custom' : 'plain', wallpaperUrl: url })) : null,
            me.model === 'standard' ? note('The monochrome icon pack is part of this handset’s identity.')
                : h('div', { class: 'kp-field' }, h('p', { class: 'kp-section-label' }, 'Icon style'), choices(ICON_STYLES, iconStyleOf(me.model, s.iconStyle), id => change({ iconStyle: id }))),
            range('Display size', s.scale, 0.75, 1.15, 0.05, value => `${Math.round(value * 100)}%`, value => change({ scale: value }))),
    ];
    if (me.model === 'flip') {
        nodes.push(section('Cover screen case', choices(PHONE_CASES, s.phoneCase || 'default', id => { if (id !== 'custom' || s.phoneCaseUrl) change({ phoneCase: id }); else me.settings = { ...s, phoneCase: 'custom' }; }, true),
            (s.phoneCase === 'custom') ? photoPicker('Case photo', s.phoneCaseUrl, url => change({ phoneCase: url ? 'custom' : 'default', phoneCaseUrl: url })) : null));
    }
    return nodes;
}

function pinArea() {
    const holder = h('div');
    let open = false;
    const paintPin = () => {
        if (!open) { render(holder, h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: () => { open = true; paintPin(); } }, me.hasPin ? 'Change or remove PIN' : 'Set a PIN')); return; }
        const input = label => h('input', { class: 'kp-input', type: 'password', inputmode: 'numeric', pattern: '[0-9]{4,8}', maxlength: 8, autocomplete: 'off', 'aria-label': label, placeholder: label });
        const current = input('Current PIN'), pin = input(me.hasPin ? 'New PIN (4–8 digits)' : 'Set a PIN (4–8 digits)'), confirmPin = input('Confirm PIN');
        render(holder, me.hasPin ? field('Current PIN', current) : null, field('New PIN', pin), field('Confirm PIN', confirmPin),
            h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
                if (!/^\d{4,8}$/.test(pin.value)) { toast('Use 4–8 digits for your PIN.'); return; }
                if (pin.value !== confirmPin.value) { toast('Those PINs don’t match. Try again.'); return; }
                const result = await attempt(() => phone.system('pin.set', { pin: pin.value, currentPin: current.value }));
                if (result) { me.hasPin = result.hasPin; toast(me.hasPin ? 'PIN protection enabled' : 'PIN updated'); open = false; show(); }
            } }, me.hasPin ? 'Change PIN' : 'Turn on PIN'),
            me.hasPin ? h('button', { class: 'kp-btn', 'data-variant': 'danger', onclick: async () => {
                if (!current.value) { toast('Enter your current PIN to remove it.'); return; }
                const result = await attempt(() => phone.system('pin.set', { pin: '', currentPin: current.value }));
                if (result) { me.hasPin = result.hasPin; toast('PIN removed'); open = false; show(); }
            } }, 'Remove PIN') : null,
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => { open = false; paintPin(); } }, 'Cancel'));
    };
    paintPin();
    return section('Screen lock', note(me.hasPin ? 'Your PIN protects this handset whenever you close it.' : 'Anyone holding this handset can open it until you set a PIN.'), holder);
}

function blockedSection() {
    const holder = h('div', null, states.loading());
    const names = Object.fromEntries(contacts.map(contact => [contact.number, contact.name]));
    const load = async () => {
        try {
            const numbers = await phone.system('blocks.list');
            render(holder, numbers.length ? numbers.map(number => h('div', { class: 'blocked-row' }, h('span', { class: 'kp-grow' }, names[number] || number, h('small', { class: 'kp-row-sub' }, ` ${number}`)),
                h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: async () => { if (await attempt(() => phone.system('blocks.set', { number, blocked: false }))) { toast('Unblocked'); load(); } } }, 'Unblock')))
                : note('No blocked numbers. You can block a number from its conversation.'));
        } catch (error) { render(holder, states.error('Something went wrong', error.message, load)); }
    };
    load();
    return section('Blocked numbers', holder);
}

function soundArea() {
    const s = me.settings;
    const quiet = isQuiet(s);
    const time = (label, key) => { const input = h('input', { class: 'kp-input', type: 'time', 'aria-label': label, value: s[key] || '' }); input.addEventListener('change', () => change({ [key]: input.value })); return field(label, input); };
    return [
        section('Volume', range('Phone volume', s.volume, 0, 1, 0.05, value => `${Math.round(value * 100)}%`, value => change({ volume: value }))),
        section(`Do not disturb · ${quiet ? 'ON' : 'OFF'}`, choices([['off', 'Off'], ['on', 'On']], s.dnd ? 'on' : 'off', id => change({ dnd: id === 'on' })),
            h('div', { class: 'quiet-hours' }, time('Quiet from', 'dndFrom'), time('Until', 'dndTo')),
            (s.dndFrom || s.dndTo) ? h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => { change({ dndFrom: '', dndTo: '' }); repaintArea(); } }, 'Clear schedule') : null,
            note('Silences alerts and ringtones. Calls still arrive, and notifications stay in your shade. Set both times for a daily schedule.')),
    ];
}

function aboutArea() {
    const s = me.settings;
    const name = h('input', { class: 'kp-input', required: true, maxlength: 32, 'aria-label': 'Device name', value: s.name || '' });
    name.addEventListener('input', () => change({ name: name.value }));
    const panel = h('div');
    mountHandset(panel, 'device', { onChanged });
    return [
        section(identity().name, note(identity().os), field('Device name', name), h('dl', { class: 'hs-facts' },
            h('div', null, h('dt', null, 'Phone number'), h('dd', null, me.number || 'No active SIM')),
            h('div', null, h('dt', null, 'Handset type'), h('dd', null, me.model === 'fold' ? 'Foldable' : me.model === 'flip' ? 'Flip' : 'Standard')),
            h('div', null, h('dt', null, 'Screen lock'), h('dd', null, me.hasPin ? 'PIN protected' : 'Not set')))),
        panel,
        note('The handset keeps local content. Your SIM holds your number. Your cloud account keeps your backup.'),
    ];
}

function panelArea(view) {
    const panel = h('div');
    mountHandset(panel, view, { onChanged });
    return view === 'connections'
        ? [note('Your SIM carries your number. Wi-Fi keeps cloud services available without mobile service.'), panel]
        : [note('Keep contacts, messages, photos and preferences ready for your next handset.'), panel];
}

const AREAS = {
    appearance: appearanceArea,
    connections: () => panelArea('connections'),
    cloud: () => panelArea('cloud'),
    privacy: () => [pinArea(), h('div', { id: 'security-panel' }), blockedSection()],
    sound: soundArea,
    about: aboutArea,
};

// Anything a handset operation changed (the selected phone, its SIM, a restore) needs the phone to reload that handset.
async function onChanged() {
    await phone.refresh();
    const next = await phone.system('settings.get');
    me = { ...me, ...next };
}

function repaintArea() { if (area) showArea(); }

async function showArea() {
    const body = h('div', { class: 'kp-content' });
    const nodes = AREAS[area]();
    render(body, nodes);
    if (area === 'privacy') { const mount = body.querySelector('#security-panel'); if (mount) mountHandset(mount, 'security', { onChanged }); }
    render(root,
        h('header', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('all'), onclick: () => { area = undefined; show(); } }, icon('back')), h('h1', { class: 'kp-title' }, t(area))),
        body, h('p', { class: 'save-state', id: 'save-state', role: 'status', 'aria-live': 'polite', 'data-status': status }, t(status)));
}

function show() {
    const s = me.settings;
    if (area) { showArea(); return; }
    const categories = [
        ['appearance', 'Wallpaper, icons & display', appearanceOf(s.theme) === 'light' ? 'Light' : 'Dark'],
        ['connections', 'SIM, Wi-Fi & phone number', me.number ? 'Mobile' : 'No SIM'],
        ['cloud', 'Back up & restore your content', ''],
        ['privacy', 'PIN, Face ID & blocked numbers', me.hasPin ? 'Protected' : 'No PIN'],
        ['sound', 'Volume & quiet hours', isQuiet(s) ? 'Quiet' : `${Math.round((s.volume ?? 0.5) * 100)}%`],
        ['about', 'Handset, name & prepare for resale', ''],
    ];
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))),
        h('div', { class: 'kp-content' },
            h('section', { class: 'identity' }, h('span', { class: 'overline' }, identity().os), h('h2', null, s.name || identity().name), h('p', { class: 'kp-row-sub' }, me.number || 'No active SIM', ` · ${identity().name}`)),
            note(t('intro')),
            h('ul', { class: 'kp-list categories' }, categories.map(([id, text, value]) => h('li', null, h('button', { class: 'kp-row', disabled: status === STATUS.saving, onclick: () => { area = id; showArea(); } },
                h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, t(id)), h('span', { class: 'kp-row-sub' }, text)), value ? h('span', { class: 'category-value' }, value) : null, icon('forward'))))),
            note(identity().subtitle)),
        h('p', { class: 'save-state', id: 'save-state', role: 'status', 'aria-live': 'polite', 'data-status': status }, t(status)));
}

ready().then(async () => {
    me = await phone.system('settings.get');
    contacts = await phone.contacts.list().catch(() => []);
    photos = await phone.callback('photos').catch(() => []);
    show();
}).catch(error => render(root, states.error('Could not start', error.message)));
