import { h } from '/sdk/runtime/kit.js';

/** Asks the moderator for the note that is saved with the decision. Resolves with the text (3 to 1000 characters) or undefined. */
export function popupNote({ title }) {
    return new Promise(resolve => {
        const area = h('textarea', { class: 'kp-input', 'aria-label': 'Moderator note', minlength: 3, maxlength: 1000, placeholder: 'Why are you doing this?' });
        const confirm = h('button', { class: 'kp-btn', 'data-variant': 'primary', disabled: true }, 'Confirm');
        const shell = h('div', { class: 'kp-overlay' }, h('div', { class: 'kp-dialog', role: 'dialog', 'aria-modal': 'true' },
            h('h2', null, title), h('p', null, 'Your note is saved with the moderation record.'), area,
            h('div', { class: 'kp-dialog-actions' }, confirm, h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => { shell.remove(); resolve(undefined); } }, 'Cancel'))));
        area.addEventListener('input', () => { confirm.disabled = area.value.trim().length < 3; });
        confirm.addEventListener('click', () => { shell.remove(); resolve(area.value.trim()); });
        document.body.append(shell);
        area.focus();
    });
}
