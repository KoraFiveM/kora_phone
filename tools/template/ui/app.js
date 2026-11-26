import { phone, ready, h, render, states, load, toast, i18n } from '/sdk/runtime/kit.js';

const t = i18n({ en: { title: '__NAME__', add: 'Add one', empty: 'Nothing yet' } });
const root = document.getElementById('app');

async function main() {
    await ready();
    const screen = h('div', { class: 'kp-content' });
    render(root,
        h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title'))),
        screen);
    await load(screen, () => phone.storage.get('count'), count => {
        let value = Number(count) || 0;
        const label = h('p', { class: 'hello-count' }, value);
        return h('div', { class: 'kp-card' }, label, h('button', {
            class: 'kp-btn', 'data-variant': 'primary',
            onclick: async () => { value += 1; label.textContent = value; await phone.storage.set('count', value); toast(String(value)); },
        }, t('add')));
    }, { empty: () => false });
}

main().catch(error => render(root, states.error('Could not start', error.message)));
