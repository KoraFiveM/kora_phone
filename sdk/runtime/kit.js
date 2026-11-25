// Kora phone UI kit for build-less apps. Import it from an app page:
//
//   <link rel="stylesheet" href="/sdk/runtime/kora-ui.css">
//   <script type="module">
//     import { phone, h, ready, states, toast, confirm, menu, prompt, icon, i18n } from '/sdk/runtime/kit.js';
//   </script>
//
// Nothing here writes a colour: it only builds elements that carry the .kp-* classes of kora-ui.css.
import { createPhoneClient } from './phone.js';

export const phone = createPhoneClient();

/** Resolves with the host `init` payload once the theme is applied. Await it before the first render. */
export const ready = () => phone.ready();

const SVG = 'http://www.w3.org/2000/svg';
const ICONS = {
    plus: 'M5 12h14M12 5v14',
    x: 'M18 6 6 18M6 6l12 12',
    back: 'm15 18-6-6 6-6',
    forward: 'm9 18 6-6-6-6',
    check: 'M20 6 9 17l-5-5',
    trash: 'M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2',
    search: 'M21 21l-4.3-4.3M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z',
    edit: 'M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z',
    more: 'M12 12h.01M19 12h.01M5 12h.01',
    bell: 'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.9 1.9 0 0 0 3.4 0',
    clock: 'M12 6v6l4 2M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z',
    camera: 'M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3zM12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
    home: 'M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8M3 10a2 2 0 0 1 .7-1.5l7-6a2 2 0 0 1 2.6 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
    sun: 'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41',
    play: 'M6 4l14 8-14 8z',
    pause: 'M6 4h4v16H6zM14 4h4v16h-4z',
};

/** A kit icon as an SVG element. `name` is one of the built-in set; unknown names render nothing. */
export function icon(name) {
    const svg = document.createElementNS(SVG, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('class', 'kp-icon');
    svg.setAttribute('aria-hidden', 'true');
    if (ICONS[name]) {
        const path = document.createElementNS(SVG, 'path');
        path.setAttribute('d', ICONS[name]);
        svg.append(path);
    }
    return svg;
}

/**
 * Builds an element without innerHTML: h('button', { class: 'kp-btn', onclick: fn }, 'Save').
 * Props: `class`, `dataset`, `on<event>` handlers, `aria-*` / `data-*` / plain attributes, `value`, `checked`.
 */
export function h(tag, props, ...children) {
    const node = document.createElement(tag);
    for (const [key, value] of Object.entries(props || {})) {
        if (value === undefined || value === null || value === false) continue;
        if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2), value);
        else if (key === 'value' || key === 'checked' || key === 'disabled') node[key] = value;
        else if (key === 'dataset') Object.assign(node.dataset, value);
        else node.setAttribute(key, value === true ? '' : String(value));
    }
    for (const child of children.flat()) {
        if (child === undefined || child === null || child === false) continue;
        node.append(child instanceof Node ? child : document.createTextNode(String(child)));
    }
    return node;
}

/** Replaces everything inside `root` with `children`. */
export function render(root, ...children) {
    root.replaceChildren(...children.flat().filter(Boolean));
}

/** The three states every app must handle instead of showing a blank screen. */
export const states = {
    loading: (label = '') => h('div', { class: 'kp-state', role: 'status' }, h('div', { class: 'kp-spinner' }), label && h('p', null, label)),
    empty: (title, detail = '') => h('div', { class: 'kp-state' }, h('h2', null, title), detail && h('p', null, detail)),
    error: (title, detail = '', retry) => h('div', { class: 'kp-state', 'data-tone': 'error', role: 'alert' },
        h('h2', null, title), detail && h('p', null, detail),
        retry && h('button', { class: 'kp-btn', onclick: retry }, 'Try again')),
};

/** Wraps an async loader so the screen shows loading, then content, empty or error. */
export async function load(root, loader, view, { empty } = {}) {
    render(root, states.loading());
    try {
        const data = await loader();
        const isEmpty = empty ? empty(data) : Array.isArray(data) && data.length === 0;
        render(root, isEmpty ? states.empty(...(typeof isEmpty === 'object' ? isEmpty : ['Nothing here yet'])) : view(data));
    } catch (error) {
        render(root, states.error('Something went wrong', error && error.message, () => load(root, loader, view, { empty })));
    }
}

// Overlays ---------------------------------------------------------------------------------------
function overlay(build, { centered = false, dismissible = true } = {}) {
    return new Promise(resolve => {
        const dialog = h('div', { class: 'kp-dialog', role: 'dialog', 'aria-modal': 'true', ...(centered ? { 'data-centered': '' } : {}) });
        const shell = h('div', { class: 'kp-overlay' }, dialog);
        const close = value => { shell.remove(); resolve(value); };
        if (dismissible) shell.addEventListener('click', event => { if (event.target === shell) close(undefined); });
        build(dialog, close);
        document.body.append(shell);
        const first = dialog.querySelector('input, textarea, button');
        if (first) first.focus();
    });
}

/** Shows a short message at the bottom of the app. */
export function toast(message, ms = 2400) {
    const node = h('div', { class: 'kp-toast', role: 'status' }, message);
    document.body.append(node);
    setTimeout(() => node.remove(), ms);
}

/** Yes/no sheet. Resolves true when confirmed. */
export function confirm({ title, message = '', confirmLabel = 'Confirm', cancelLabel = 'Cancel', danger = false }) {
    return overlay((dialog, close) => dialog.append(
        h('h2', null, title), message && h('p', null, message),
        h('div', { class: 'kp-dialog-actions' },
            h('button', { class: 'kp-btn', 'data-variant': danger ? 'danger' : 'primary', onclick: () => close(true) }, confirmLabel),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => close(false) }, cancelLabel)),
    ), { centered: true }).then(value => value === true);
}

/** Action list. `items` are { label, danger?, value }. Resolves with the chosen value or undefined. */
export function menu({ title = '', items }) {
    return overlay((dialog, close) => dialog.append(
        title && h('h2', null, title),
        h('div', { class: 'kp-dialog-actions' },
            items.map(item => h('button', { class: 'kp-btn', 'data-variant': item.danger ? 'danger' : undefined, onclick: () => close(item.value ?? item.label) }, item.label)),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => close(undefined) }, 'Cancel')),
    ));
}

/** Single text question. Resolves with the string, or undefined when cancelled. */
export function prompt({ title, label = '', value = '', confirmLabel = 'OK' }) {
    return overlay((dialog, close) => {
        const input = h('input', { class: 'kp-input', value, 'aria-label': label || title });
        input.addEventListener('keydown', event => { if (event.key === 'Enter') close(input.value); });
        dialog.append(h('h2', null, title), input, h('div', { class: 'kp-dialog-actions' },
            h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: () => close(input.value) }, confirmLabel),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => close(undefined) }, 'Cancel')));
    }, { centered: true });
}

/**
 * Tiny translator. `i18n({ en: { save: 'Save' }, nl: { save: 'Opslaan' } })` returns t(key, vars).
 * The language comes from the host (init.locale); English is the fallback.
 */
export function i18n(tables) {
    const lang = () => String((phone.init && phone.init.locale) || document.documentElement.lang || 'en').toLowerCase().split('-')[0];
    return (key, vars) => {
        const text = (tables[lang()] && tables[lang()][key]) || (tables.en && tables.en[key]) || key;
        return vars ? text.replace(/\{(\w+)\}/g, (_, name) => (name in vars ? vars[name] : '')) : text;
    };
}

// Richer dialogs. The lb-phone compatibility layer (web/public/lb-shim.js) renders its `components.*` through these, and
// native apps can use them too. Button colours are semantic, never CSS colours: 'blue' is the primary action, 'red' the
// destructive one, anything else a plain button.
const variantOf = color => (color === 'red' ? 'danger' : color === 'blue' ? 'primary' : undefined);

/** Message with buttons. `buttons` are { title, color?, cb? }; a missing list shows a single OK. */
export function popup({ title = '', description = '', attachment, buttons }) {
    const list = Array.isArray(buttons) && buttons.length ? buttons : [{ title: 'OK', color: 'blue' }];
    return overlay((dialog, close) => dialog.append(
        title && h('h2', null, title), description && h('p', null, description),
        attachment && attachment.src && h('img', { src: attachment.src, alt: '', style: 'max-width:100%' }),
        h('div', { class: 'kp-dialog-actions' }, list.map(button => h('button', {
            class: 'kp-btn', 'data-variant': variantOf(button.color),
            onclick: () => { close(button.title); if (typeof button.cb === 'function') button.cb(); },
        }, button.title)))), { centered: true });
}

/** Bottom action sheet with callbacks: contextMenu({ title, buttons: [{ title, color?, cb? }] }). */
export function contextMenu({ title = '', buttons = [] }) {
    return overlay((dialog, close) => dialog.append(
        title && h('h2', null, title),
        h('div', { class: 'kp-dialog-actions' },
            buttons.map(button => h('button', {
                class: 'kp-btn', 'data-variant': variantOf(button.color),
                onclick: () => { close(button.title); if (typeof button.cb === 'function') button.cb(); },
            }, button.title)),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => close(undefined) }, 'Cancel'))));
}

/** Choose one of `items` ({ key, title, detail? }). Resolves with the chosen item or undefined. */
export function pick({ title, items, empty = 'Nothing to choose from' }) {
    return overlay((dialog, close) => dialog.append(
        h('h2', null, title),
        items.length
            ? h('ul', { class: 'kp-list' }, items.map(item => h('li', null, h('button', { class: 'kp-row', onclick: () => close(item) },
                h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, item.title), item.detail && h('span', { class: 'kp-row-sub' }, item.detail))))))
            : h('p', null, empty),
        h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => close(undefined) }, 'Cancel')));
}

/** Native colour input in a sheet. Resolves with "#rrggbb" or undefined. */
export function colorPicker({ value = '#000000' } = {}) {
    return overlay((dialog, close) => {
        const input = h('input', { type: 'color', class: 'kp-input', value, 'aria-label': 'Colour' });
        dialog.append(h('h2', null, 'Choose a colour'), input, h('div', { class: 'kp-dialog-actions' },
            h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: () => close(input.value) }, 'Select'),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => close(undefined) }, 'Cancel')));
    }, { centered: true });
}

/** Full-screen view of one image. */
export function fullscreenImage(src) {
    return overlay((dialog, close) => dialog.append(
        h('img', { src, alt: '', style: 'max-width:100%;max-height:70vh;object-fit:contain' }),
        h('button', { class: 'kp-btn', onclick: () => close(undefined) }, 'Close')), { centered: true });
}

const EMOJI = '😀 😂 😍 😎 🤔 😢 😡 👍 👎 🙏 👏 🔥 ❤️ 💯 🎉 🚗 🏠 💰 📍 ⭐ ✅ ❌ 🍕 ☕'.split(' ');

/** A small emoji grid. Resolves with { emoji } or undefined. */
export function emojiPicker() {
    return overlay((dialog, close) => dialog.append(
        h('h2', null, 'Emoji'),
        h('div', { style: 'display:grid;grid-template-columns:repeat(6,1fr);gap:8px;font-size:1.6rem' },
            EMOJI.map(emoji => h('button', { class: 'kp-icon-btn', 'aria-label': emoji, onclick: () => close({ emoji }) }, emoji))),
        h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => close(undefined) }, 'Cancel')));
}

/** Full-screen photo or video. `kind` is 'video' for a clip. */
export function viewMedia({ src, kind = 'photo' }) {
    return overlay((dialog, close) => dialog.append(
        kind === 'video'
            ? h('video', { src, controls: true, autoplay: true, playsinline: true, style: 'max-width:100%;max-height:70vh' })
            : h('img', { src, alt: '', style: 'max-width:100%;max-height:70vh;object-fit:contain' }),
        h('button', { class: 'kp-btn', onclick: () => close(undefined) }, 'Close')), { centered: true });
}
