import { ready, h, render, states, i18n } from '/sdk/runtime/kit.js';
import { calculate } from './calc.js';

const t = i18n({ en: { hint: 'A little clarity' }, nl: { hint: 'Even helderheid' } });
const KEYS = ['AC', '⌫', '÷', '×', '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '=', '0', '.'];
const root = document.getElementById('app');

function start() {
    let expression = '';
    let error = '';
    const hint = h('small', null, t('hint'));
    const output = h('output', { 'aria-live': 'polite' }, '0');
    const paint = () => { hint.textContent = error || t('hint'); output.textContent = expression || '0'; };
    const press = key => {
        error = '';
        if (key === 'AC') expression = '';
        else if (key === '⌫') expression = expression.slice(0, -1);
        else if (key === '=') { try { expression = calculate(expression); } catch (e) { error = e.message; } }
        else expression = (expression + key).slice(0, 60);
        paint();
    };
    render(root, h('div', { class: 'calc' },
        h('div', { class: 'calc-display' }, hint, output),
        h('div', { class: 'calc-keys' }, KEYS.map(key => h('button', {
            class: `kp-btn${key === '0' ? ' zero' : ''}${key === '=' ? ' equals' : ''}`,
            'data-variant': key === '=' ? 'primary' : undefined, onclick: () => press(key),
        }, key)))));
}

ready().then(start).catch(error => render(root, states.error('Could not start', error.message)));
