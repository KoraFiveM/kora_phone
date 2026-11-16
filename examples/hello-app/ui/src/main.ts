import { createPhoneClient } from '@kora/phone-sdk';
import '@kora/phone-sdk/theme.css';

const phone = createPhoneClient();
const root = document.getElementById('root');
if (!root) throw new Error('missing root');

const button = document.createElement('button');
button.className = 'kora-button';
root.append(button);

async function increment(): Promise<void> {
    const result = await phone.callback('increment', { step: 1 });
    button.textContent = 'Count: ' + JSON.stringify(result);
}

button.addEventListener('click', () => void increment());
void phone.ready().then(() => { button.textContent = 'Tap me'; });
