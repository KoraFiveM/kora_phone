// The handset, SIM and cloud controls. Every operation is one handset request the server checks (who may run it, what it costs),
// sent through phone.system('handset', ...). After anything that changes the handset the phone reloads it.
import { phone, h, render, toast, confirm, popup, icon } from '/sdk/runtime/kit.js';
import { HANDSET_NAMES, ITEM_NAMES } from './data.js';

const money = value => new Intl.NumberFormat(undefined, { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(value);

/** Unwraps the `{ ok, data }` the server answers a handset operation with. */
async function operation(payload) {
    const response = await phone.system('handset', payload);
    if (response && typeof response === 'object' && 'ok' in response && response.ok === false) {
        const problem = response.error;
        throw new Error(typeof problem === 'string' ? problem : (problem && (problem.message || problem.code)) || 'Phone operation failed');
    }
    return response && typeof response === 'object' && 'ok' in response ? response.data : response;
}

/** Draws the panel into `root`. `view` limits it to one group of cards: connections, cloud, security or device. */
export function mountHandset(root, view, { onChanged }) {
    const state = { status: undefined, busy: false, shopId: '', target: '', targetSlot: '', swapAtShop: false, hotspot: '', password: '', accountId: '', note: '', simNumber: '' };

    async function refresh() {
        try { state.status = await operation({ op: 'status' }); state.note = ''; } catch (error) { state.note = error.message; }
        paint();
    }

    async function run(payload, success) {
        if (state.busy) return;
        state.busy = true; paint();
        try {
            const result = await operation(payload);
            if (result && typeof result === 'object' && 'recoveryCode' in result && 'accountId' in result) await showSecret(result);
            toast(success);
            state.password = '';
            await refresh();
            if (payload.op !== 'status') await onChanged();
        } catch (error) {
            toast(error.message);
        } finally {
            state.busy = false; paint();
        }
    }

    const ask = (title, detail, payload, success) => confirm({ title, message: detail, confirmLabel: 'Confirm' }).then(yes => yes && run(payload, success));

    function showSecret(secret) {
        return popup({ title: 'Keep this somewhere safe.', description: `This recovery code is shown once. It gives access to your cloud backup.\n\nCloud account: ${secret.accountId}\nRecovery code: ${secret.recoveryCode}`,
            buttons: [{ title: 'Copy details', color: 'blue', cb: () => navigator.clipboard.writeText(`Cloud account: ${secret.accountId}\nRecovery code: ${secret.recoveryCode}`).then(() => toast('Recovery details copied. Save them somewhere safe.')).catch(() => toast('Copy is unavailable here. Save the recovery details manually.')) }, { title: 'I saved it' }] });
    }

    const card = (section, heading, ...children) => h('section', { class: 'kp-card hs-card', 'data-section': section }, h('h3', { class: 'kp-row-title' }, heading), ...children);
    const button = (label, onclick, disabled, variant) => h('button', { class: 'kp-btn', 'data-variant': variant, disabled: disabled || state.busy, onclick }, label);
    const row = (title, detail, onclick, end) => h('li', null, h('button', { class: 'kp-row', disabled: state.busy, onclick },
        h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, title), detail ? h('span', { class: 'kp-row-sub' }, detail) : null), end));
    const note = text => h('p', { class: 'kp-row-sub' }, text);
    const field = (props, key) => { const el = h('input', { class: 'kp-input', ...props }); el.addEventListener('input', () => { state[key] = el.value; }); return el; };
    const select = (options, value, key, onchange) => {
        const el = h('select', { class: 'kp-input', disabled: state.busy }, options.map(([id, label]) => h('option', { value: id, selected: id === value }, label)));
        el.addEventListener('change', () => { state[key] = el.value; if (onchange) onchange(); paint(); });
        return el;
    };

    function deviceCard(s) {
        const phones = s.phones.map(item => row(HANDSET_NAMES[item.model] || item.model, `Inventory slot ${item.slot}`,
            () => ask('Switch handset?', 'Any active call will end. The selected handset keeps its own SIM, lock and cloud login.', { op: 'select', slot: item.slot }, 'Handset selected'),
            item.id === s.handset.id ? icon('check') : icon('forward')));
        return card('device', HANDSET_NAMES[s.handset.model] || s.handset.model,
            h('span', { class: 'kp-badge' }, s.online ? 'Online' : 'Offline'),
            h('p', { class: 'hs-number' }, s.number || 'No mobile service'),
            h('dl', { class: 'hs-facts' },
                h('div', null, h('dt', null, 'Handset'), h('dd', null, s.handset.id)),
                h('div', null, h('dt', null, 'SIM'), h('dd', null, s.sim ? s.sim.status : 'Not inserted')),
                h('div', null, h('dt', null, 'Cloud'), h('dd', null, s.accountId || 'Not signed in'))),
            h('ul', { class: 'kp-list' }, phones));
    }

    function faceCard(s) {
        return card('security', 'Face ID', h('span', { class: 'kp-badge' }, s.faceId ? 'Enrolled' : 'Not set'),
            note('Recognises your character on this handset. Set a backup PIN in Device security first.'),
            button(s.faceId ? 'Enrol this character again' : 'Set up Face ID', () => run({ op: 'faceEnroll' }, 'Face ID enrolled for this character')));
    }

    function simCard(s, shop, shopSwap, swapContext) {
        const swap = s.simSwap !== 'player' ? h('label', { class: 'kp-row-flex' },
            h('input', { type: 'checkbox', checked: s.simSwap === 'shop' || state.swapAtShop, disabled: s.simSwap === 'shop' || state.busy, onchange: event => { state.swapAtShop = event.target.checked; paint(); } }),
            'Use selected shop counter') : null;
        let body;
        if (s.sim) body = button('Remove inserted SIM', () => run({ op: 'removeSim', ...swapContext }, 'SIM returned to your inventory'), shopSwap && !shop);
        else if (s.sims.length) body = h('ul', { class: 'kp-list' }, s.sims.map(sim => row('Insert SIM', `Slot ${sim.slot} · ${sim.id || 'New SIM'}`, () => run({ op: 'insertSim', slot: sim.slot, ...swapContext }, 'SIM inserted'), icon('forward'))));
        else body = note('No loose SIM in your inventory.');
        return card('connections', 'Mobile SIM', note('Your number follows the SIM. Your cloud history stays with your account.'), swap,
            shopSwap ? note(`Counter: ${(shop && shop.label) || 'No authorised shop nearby'}`) : null, body);
    }

    function wifiCard(s, hotspot) {
        const connected = s.wifi ? note(`Connected: ${(s.hotspots.find(item => item.id === s.wifi) || {}).label || s.wifi}`) : null;
        let body;
        if (s.hotspots.length) {
            body = h('div', { class: 'kp-field' },
                select(s.hotspots.map(network => [network.id, network.label + (network.private ? ' · Private' : '')]), hotspot && hotspot.id, 'hotspot', () => { state.password = ''; }),
                hotspot && hotspot.private ? field({ type: 'password', autocomplete: 'off', maxlength: 128, 'aria-label': 'Network password', placeholder: 'Network password', value: state.password }, 'password') : null,
                button('Connect', () => run({ op: 'wifi', id: hotspot && hotspot.id, password: state.password }, 'Wi-Fi connected')));
        } else body = note('No Wi-Fi networks in range.');
        return card('connections', 'Wi-Fi', note('Back up and restore without a SIM. Calls still need mobile service.'), connected, body);
    }

    function cloudCard(s) {
        const account = field({ maxlength: 128, autocomplete: 'off', 'aria-label': 'Cloud account ID', placeholder: 'Cloud account ID (optional for one registered account)', value: state.accountId }, 'accountId');
        const code = h('input', { class: 'kp-input', type: 'password', maxlength: 128, autocomplete: 'off', 'aria-label': 'Recovery code', placeholder: 'Recovery code' });
        const main = s.accountId ? button('Back up now', () => run({ op: 'backup' }, 'Cloud backup saved'), !s.online, 'primary')
            : button('Create cloud account', () => run({ op: 'registerCloud' }, 'Cloud account created. Save your recovery code.'), !s.online, 'primary');
        const restore = button('Restore account', () => {
            if (!code.value.trim()) return;
            ask('Replace local content?', 'Contacts, messages, photos and preferences on this handset will be replaced by this cloud backup. Back up anything you want to keep first.',
                { op: 'restoreCloud', accountId: state.accountId.trim(), code: code.value.trim() }, 'Cloud backup restored');
        }, !s.online);
        return card('cloud', 'Cloud backup', note('Save contacts, messages, photos and preferences. Restoring replaces this handset’s local content.'), main,
            !s.online ? note('Connect to Wi-Fi or insert an active SIM first.') : null,
            h('details', null, h('summary', null, 'Restore a cloud account'), h('div', { class: 'kp-field' }, account, code, restore)));
    }

    function servicesCard(s, shop, services) {
        if (!s.shops.length) return card('device', 'Mobile services', note('Visit a mobile shop to buy a handset or SIM, recover your account, or sell a reset phone.'));
        const counters = select(s.shops.map(counter => [counter.id, counter.label + (counter.business ? ' · Player business' : '')]), shop && shop.id, 'shopId', () => { state.target = ''; });
        const customerField = shop && shop.business ? field({ type: 'number', min: 1, step: 1, 'aria-label': 'Customer server ID', placeholder: 'Customer server ID (optional)', value: state.target }, 'target') : null;
        const prices = Object.entries((shop && shop.prices) || {}).map(([item, amount]) => row(ITEM_NAMES[item] || item, null,
            () => ask(`Buy ${ITEM_NAMES[item] || item}?`, `${money(amount)} will be charged by ${shop.label}. Stock, payment and inventory space must be available.`, { op: 'buy', item, ...services }, 'Purchase completed'), h('strong', null, money(amount))));
        const simNumber = field({ inputmode: 'tel', maxlength: 24, 'aria-label': 'Registered phone number', placeholder: 'Registered phone number', value: state.simNumber }, 'simNumber');
        const replace = h('details', null, h('summary', null, 'Replace a lost or stolen SIM'), h('div', { class: 'kp-field' }, simNumber,
            button('Request replacement', () => {
                if (!state.simNumber.trim()) return;
                ask('Replace this SIM?', 'The number stays the same. Its old SIM will be permanently disabled, including any hacked copy. The configured service fee applies.', { op: 'replaceSim', number: state.simNumber.trim(), ...services }, 'Replacement SIM issued');
            })));
        const recover = h('details', null, h('summary', null, 'Recover a cloud account'), h('div', { class: 'kp-field' },
            button('Verify identity & recover', () => ask('Recover this account?', 'The service checks the registering character, charges its configured fee, replaces the recovery code and signs out previous cloud sessions.', { op: 'recoverCloud', accountId: state.accountId.trim(), ...services }, 'Account recovered. Save the new recovery code.'))));
        let resale;
        if (shop && shop.business && state.target.trim()) {
            const slot = field({ type: 'number', min: 1, step: 1, 'aria-label': 'Customer handset slot', placeholder: 'Customer handset slot', value: state.targetSlot }, 'targetSlot');
            resale = h('div', { class: 'kp-field' }, slot, button('Sell customer handset', () => {
                if (!state.targetSlot) return;
                ask('Sell customer handset?', `The reset handset in customer inventory slot ${state.targetSlot} will be sold. The configured resale payout applies.`, { op: 'resell', slot: Number(state.targetSlot), ...services }, 'Handset sold');
            }));
        } else {
            resale = h('ul', { class: 'kp-list' }, s.phones.map(item => row(HANDSET_NAMES[item.model] || item.model, `Slot ${item.slot}`,
                () => ask(`Sell ${HANDSET_NAMES[item.model] || item.model}?`, `The handset in slot ${item.slot} will leave the selected customer's inventory. The configured resale payout applies.`, { op: 'resell', slot: item.slot, ...services }, 'Handset sold'), icon('forward'))));
        }
        const sell = h('details', null, h('summary', null, 'Sell a reset handset'), note('Remove its SIM and factory-reset it first. The shop checks that it is ready for resale.'), resale);
        return card('device', 'Mobile services', counters, customerField, h('ul', { class: 'kp-list' }, prices), replace, recover, sell);
    }

    function resetCard(s) {
        return card('device', 'Prepare for resale', note('Factory reset removes this handset’s PIN, Face ID, cloud login and local content. Your existing cloud backup stays safe.'),
            button('Erase handset', () => ask('Factory-reset this handset?', 'Local contacts, messages, photos and settings will be cleared. Save a cloud backup first. This cannot be undone on the handset.', { op: 'reset' }, 'Handset reset'), Boolean(s.sim), 'danger'),
            s.sim ? note('Remove the SIM before resetting.') : null);
    }

    function paint() {
        const s = state.status;
        if (!s) { render(root, state.note ? h('p', { class: 'kp-row-sub', role: 'alert' }, state.note) : note('Loading your handset…')); return; }
        const shop = s.shops.find(item => item.id === state.shopId) || s.shops[0];
        const hotspot = s.hotspots.find(item => item.id === state.hotspot) || s.hotspots[0];
        const customer = shop && shop.business && state.target.trim() ? { target: Number(state.target) } : {};
        const services = { shop: shop && shop.id, ...customer };
        const shopSwap = s.simSwap === 'shop' || state.swapAtShop;
        const swapContext = shopSwap ? { shop: shop && shop.id } : {};
        const cards = [
            ['device', deviceCard(s)], ['security', faceCard(s)], ['connections', simCard(s, shop, shopSwap, swapContext)], ['connections', wifiCard(s, hotspot)],
            ['cloud', cloudCard(s)], ['device', servicesCard(s, shop, services)], ['device', resetCard(s)],
        ];
        render(root, state.note ? h('p', { class: 'kp-row-sub', role: 'alert' }, state.note) : null, cards.filter(([section]) => view === 'all' || section === view).map(([, node]) => node));
    }

    paint();
    refresh();
}
