import { phone, ready, h, render, states, toast, confirm, menu, prompt, pick, icon, i18n } from '/sdk/runtime/kit.js';
import { parseToken, previewText, locationBody, photoBody } from '/sdk/runtime/chat-tokens.js';
import { createClipRecorder } from '/sdk/runtime/recorder.js';

const t = i18n({ en: { title: 'Pulse', chat: 'New chat', group: 'New group', search: 'Search chats', all: 'All', people: 'People', groups: 'Groups', back: 'Back to chats',
    emptyTitle: 'Start a conversation', emptyDetail: 'Message a number or make a group.', number: 'Phone number', groupName: 'Group name', members: 'Numbers, comma separated',
    start: 'Start chat', create: 'Create group', placeholder: 'Message', send: 'Send', attach: 'Attach', location: 'Share my location', photo: 'Send a gallery photo', clip: 'Record a clip',
    stopClip: 'Stop recording', noPhotos: 'Take a photo in Camera first.', addMember: 'Add someone', leave: 'Leave group', leaveTitle: 'Leave this group?', leaveDetail: 'You will stop receiving its messages.',
    block: 'Block', blocked: 'Blocked', save: 'Save contact', saved: 'Contact saved', waypoint: 'Set waypoint', shown: 'Hidden until you tap (not in your contacts)', tap: 'Tap to show',
    earlier: 'Earlier messages', you: 'You', sharedFlash: 'Shared from Flash', groupLabel: 'Group', location2: 'Shared a location', clipOff: 'Clips are turned off on this server.', waypointSet: 'Waypoint set',
    clipSent: 'Clip sent', archived: 'Archived group · read only', nameOf: 'Name this contact' } });
const root = document.getElementById('app');
const PAGE = 50;
const ref = () => `p-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };
const stamp = value => new Date(typeof value === 'number' ? value * 1000 : value);
const dayLabel = value => stamp(value).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
const timeLabel = value => stamp(value).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });

let cfg = { number: '', flash: false };
let names = {};
let conversations = [];
let active;
let messages = [];
let filter = 'all';
let query = '';
let attachment;       // { kind: 'photo', id, url } or { kind: 'clip', media }
let recorder;

const isGroup = conversation => conversation.type === 'group';
const peerOf = conversation => conversation.peerPhoneNumber || '';
const nameOf = number => names[number] || number || t('groupLabel');
const titleOf = conversation => conversation.title || (isGroup(conversation) ? t('groupLabel') : nameOf(peerOf(conversation)));

async function loadConversations(more) {
    const last = conversations[conversations.length - 1];
    const rows = await phone.callback('conversations', more && last ? { before: last.sortId ?? last.lastMessageId ?? last.id, cursorId: last.id } : {});
    conversations = more ? conversations.concat(rows) : rows;
}

function frame() {
    const add = h('button', { class: 'kp-icon-btn', 'aria-label': t('chat'), onclick: newChat }, icon('plus'));
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title')), add),
        h('div', { class: 'kp-split', id: 'split' }, h('div', { 'data-pane': 'list', id: 'listPane' }), h('div', { 'data-pane': 'detail', id: 'detailPane' })));
}
const split = () => document.getElementById('split');
const showDetail = on => { const el = split(); if (el) { if (on) el.setAttribute('data-detail', 'open'); else el.removeAttribute('data-detail'); } };

function visible() {
    return conversations.filter(c => (filter === 'all' || (filter === 'groups') === isGroup(c))
        && (!query || `${titleOf(c)} ${peerOf(c)}`.toLowerCase().includes(query.toLowerCase())));
}

function paintList() {
    const holder = document.getElementById('listPane');
    if (!holder) return;
    const search = h('input', { class: 'kp-input', 'aria-label': t('search'), placeholder: t('search'), value: query });
    search.addEventListener('input', () => { query = search.value; paintRows(); });
    const tabs = h('div', { class: 'kp-segmented filters', role: 'group', 'aria-label': t('title') },
        [['all', t('all')], ['people', t('people')], ['groups', t('groups')]].map(([id, label]) => h('button', { 'aria-pressed': filter === id, onclick: () => { filter = id; paintList(); } }, label)));
    render(holder, h('div', { class: 'kp-content' }, search, tabs), h('div', { id: 'rows' }));
    paintRows();
}

function paintRows() {
    const holder = document.getElementById('rows');
    if (!holder) return;
    const shown = visible();
    if (!shown.length) { render(holder, states.empty(t('emptyTitle'), t('emptyDetail'))); return; }
    render(holder, h('ul', { class: 'kp-list' }, shown.map(c => h('li', null, h('button', { class: 'kp-row', 'aria-selected': !!active && active.id === c.id, onclick: () => openConversation(c) },
        h('span', { class: 'kp-row-main' }, h('span', { class: 'kp-row-title' }, titleOf(c)),
            h('span', { class: 'kp-row-sub' }, previewText(c.lastMessagePreview) || (c.lastMediaMime ? t('photo') : ''))),
        c.unreadCount > 0 ? h('span', { class: 'unread' }, `${c.unreadCount}`) : null)))),
        conversations.length % PAGE === 0 ? h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => attempt(async () => { await loadConversations(true); paintRows(); }) }, t('earlier')) : null);
}

async function list() {
    active = undefined; messages = []; attachment = undefined;
    if (recorder) recorder.discard();
    if (!split()) frame();
    showDetail(false);
    render(document.getElementById('detailPane'));
    render(document.getElementById('listPane'), states.loading());
    try { await loadConversations(false); } catch (error) { render(document.getElementById('listPane'), states.error('Something went wrong', error.message, list)); return; }
    paintList();
}

async function startWith(number) {
    const conversation = await attempt(() => phone.callback('start', { number }));
    if (conversation) { await attempt(() => loadConversations(false)); openConversation({ ...conversation, peerPhoneNumber: conversation.peerPhoneNumber || number }); }
}

function newChat() {
    const choice = menu({ title: t('title'), items: [{ label: t('chat'), value: 'chat' }, { label: t('group'), value: 'group' }] });
    choice.then(async value => {
        if (value === 'chat') {
            const number = await prompt({ title: t('chat'), label: t('number'), confirmLabel: t('start') });
            const digits = (number || '').replace(/\D/g, '');
            if (/^\d{7,16}$/.test(digits)) startWith(digits);
        } else if (value === 'group') {
            const name = await prompt({ title: t('group'), label: t('groupName'), confirmLabel: 'Next' });
            if (!name || !name.trim()) return;
            const raw = await prompt({ title: name, label: t('members'), confirmLabel: t('create') });
            const numbers = (raw || '').split(',').map(item => item.replace(/\D/g, '')).filter(item => /^\d{7,16}$/.test(item));
            if (!numbers.length) return;
            const made = await attempt(() => phone.callback('createGroup', { name: name.trim(), numbers }));
            if (made) { await attempt(() => loadConversations(false)); paintRows(); toast(t('create')); }
        }
    });
}

// A photo or clip from someone outside your contacts stays hidden until tapped, so a stranger cannot make your phone fetch their link.
function mediaNode(token, trusted) {
    const make = () => token.kind === 'video' ? h('video', { src: token.url, controls: true, playsinline: true, preload: 'metadata' }) : h('img', { src: token.url, alt: t('photo') });
    if (trusted) return make();
    const holder = h('div');
    render(holder, h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => render(holder, make()) }, `${t('tap')}`));
    return holder;
}

function bubble(message) {
    const mine = message.isMine === 1 || message.isMine === true;
    const trusted = mine || Boolean(names[message.senderNumber]);
    const token = parseToken(message.body);
    let content = null;
    if (token && token.kind === 'location') {
        content = h('div', null, h('p', null, `${t('location2')}: ${token.label}`),
            h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => attempt(async () => { await phone.client('waypoint', { x: token.x, y: token.y }); toast(t('waypointSet')); }) }, t('waypoint')));
    } else if (token) content = mediaNode(token, trusted);
    else if (message.body) content = h('p', null, message.body);
    const stored = message.mediaUrl && !token ? mediaNode({ kind: String(message.mediaMime || '').startsWith('video') ? 'video' : 'photo', url: message.mediaUrl }, trusted) : null;
    return h('div', { class: 'bubble', 'data-mine': mine }, stored, content,
        message.shared_from_post ? h('span', { class: 'tag' }, t('sharedFlash')) : null,
        h('small', null, `${timeLabel(message.createdAt)} · ${mine ? t('you') : nameOf(message.senderNumber)}`));
}

function paintThread() {
    const holder = document.getElementById('thread');
    if (!holder) return;
    const ordered = messages.slice().sort((a, b) => a.id - b.id);
    const nodes = []; let lastDay = '';
    for (const message of ordered) {
        const label = dayLabel(message.createdAt);
        if (label !== lastDay) { nodes.push(h('span', { class: 'day' }, label)); lastDay = label; }
        nodes.push(bubble(message));
    }
    render(holder, messages.length >= PAGE ? h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => attempt(async () => {
        const older = await phone.callback('thread', { id: active.id, before: Math.min(...messages.map(m => m.id)) });
        messages = messages.concat(older.filter(row => !messages.some(known => known.id === row.id))); paintThread();
    }) }, t('earlier')) : null, nodes.length ? nodes : states.empty(t('emptyTitle'), t('emptyDetail')));
}

async function loadThread() {
    const rows = await phone.callback('thread', { id: active.id });
    messages = rows;
    paintThread();
    const holder = document.getElementById('thread');
    if (holder) holder.scrollTop = holder.scrollHeight;
    phone.callback('read', { id: active.id, messageId: rows[0] && rows[0].id }).catch(() => {});
}

async function openConversation(conversation) {
    active = conversation; messages = []; attachment = undefined;
    if (!split()) frame();
    const archived = peerOf(conversation).startsWith('@group:');
    const body = h('textarea', { class: 'kp-input', maxlength: 1900, rows: 1, 'aria-label': t('placeholder'), placeholder: t('placeholder') });
    const preview = h('div');
    const paintAttachment = () => render(preview, !attachment ? null : h('div', { class: 'attachment' },
        attachment.kind === 'photo' ? h('img', { src: attachment.url, alt: '', style: 'max-width:72px' }) : h('video', { src: attachment.url, controls: true }),
        h('button', { class: 'kp-icon-btn', 'aria-label': t('stopClip'), onclick: () => { attachment = undefined; if (recorder) recorder.discard(); paintAttachment(); } }, icon('x'))));
    const sendBody = async (text, mediaId) => {
        const sent = await attempt(() => phone.callback('send', { conversationId: conversation.id, body: text, mediaId, clientRequestId: ref() }));
        if (sent) { messages = messages.concat(sent); paintThread(); const holder = document.getElementById('thread'); if (holder) holder.scrollTop = holder.scrollHeight; }
        return Boolean(sent);
    };
    const attach = async () => {
        const options = [{ label: t('location'), value: 'loc' }, { label: t('photo'), value: 'photo' }];
        if (cfg.flash) options.push({ label: t('clip'), value: 'clip' });
        const choice = await menu({ title: t('attach'), items: options });
        if (choice === 'loc') {
            const here = await attempt(() => phone.client('here'));
            if (here) await sendBody(locationBody(here));
        } else if (choice === 'photo') {
            const photos = await attempt(() => phone.callback('photos'));
            if (!photos) return;
            if (!photos.length) { toast(t('noPhotos')); return; }
            const chosen = await pick({ title: t('photo'), items: photos.map((p, index) => ({ title: `${t('photo')} ${index + 1}`, photo: p })) });
            if (chosen) { attachment = { kind: 'photo', id: chosen.photo.id, url: chosen.photo.url }; paintAttachment(); }
        } else if (choice === 'clip') {
            recorder = createClipRecorder(cfg.flash.maxSeconds || 15, state => {
                if (state.clip) { attachment = { kind: 'clip', blob: state.clip.blob, url: state.clip.url }; paintAttachment(); }
            });
            await attempt(() => recorder.start());
            toast(t('stopClip'));
        }
    };
    const send = async () => {
        if (recorder && recorder.state().recording) { recorder.stop(); return; }
        const text = body.value.trim();
        if (attachment && attachment.kind === 'clip') {
            const saved = await attempt(() => phone.media.upload(attachment.blob));
            if (!saved) return;
            if (await sendBody(text || photoBodyFor(saved), Number(saved.id))) { toast(t('clipSent')); attachment = undefined; recorder.discard(); paintAttachment(); body.value = ''; }
            return;
        }
        if (!text && !attachment) return;
        if (await sendBody(text, attachment ? Number(attachment.id) : undefined)) { body.value = ''; attachment = undefined; paintAttachment(); }
    };
    const photoBodyFor = saved => photoBody(saved.url);
    const contactKnown = Boolean(names[peerOf(conversation)]);
    const actions = [];
    if (isGroup(conversation)) {
        actions.push(h('button', { class: 'kp-icon-btn', 'aria-label': t('addMember'), onclick: async () => {
            const number = ((await prompt({ title: t('addMember'), label: t('number'), confirmLabel: t('addMember') })) || '').replace(/\D/g, '');
            if (/^\d{7,16}$/.test(number)) attempt(async () => { await phone.callback('addMember', { id: conversation.id, number }); toast(t('addMember')); });
        } }, icon('plus')));
        actions.push(h('button', { class: 'kp-icon-btn', 'aria-label': t('leave'), onclick: async () => {
            if (!(await confirm({ title: t('leaveTitle'), message: t('leaveDetail'), confirmLabel: t('leave'), danger: true }))) return;
            if (await attempt(async () => { await phone.callback('leaveGroup', { id: conversation.id }); return true; })) list();
        } }, icon('trash')));
    } else {
        if (!contactKnown && peerOf(conversation)) actions.push(h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: async () => {
            const name = await prompt({ title: t('save'), label: t('nameOf'), confirmLabel: t('save') });
            if (name && name.trim() && await attempt(async () => { await phone.contacts.save({ name: name.trim(), number: peerOf(conversation) }); return true; })) { names[peerOf(conversation)] = name.trim(); toast(t('saved')); paintThread(); }
        } }, t('save')));
        actions.push(h('button', { class: 'kp-btn', 'data-variant': 'danger', onclick: async () => {
            if (await attempt(async () => { await phone.callback('block', { number: peerOf(conversation), blocked: true }); return true; })) toast(t('blocked'));
        } }, t('block')));
    }
    showDetail(true);
    render(document.getElementById('detailPane'), h('div', { class: 'kp-app' },
        h('div', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('back'), onclick: () => { if (recorder) recorder.discard(); showDetail(false); active = undefined; paintRows(); } }, icon('back')),
            h('h2', { class: 'kp-title' }, titleOf(conversation)), ...actions),
        h('div', { class: 'kp-content thread', id: 'thread' }, states.loading()),
        archived ? h('div', { class: 'kp-footer' }, h('p', { class: 'kp-row-sub' }, t('archived')))
            : h('div', { class: 'kp-footer', style: 'flex-direction:column' }, preview, h('div', { class: 'composer' },
                h('button', { class: 'kp-icon-btn', 'aria-label': t('attach'), onclick: attach }, icon('plus')), body,
                h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: send }, t('send'))))));
    await attempt(loadThread);
}

phone.on('messages:new', async () => {
    if (active) await attempt(loadThread);
    await attempt(() => loadConversations(false));
    paintRows();
});

ready().then(async init => {
    cfg = await phone.callback('config');
    const people = await phone.contacts.list().catch(() => []);
    names = Object.fromEntries(people.map(contact => [contact.number, contact.name]));
    if (init.target && /^\d{7,16}$/.test(init.target)) { frame(); await startWith(init.target); return; }
    await list();
}).catch(error => render(root, states.error('Could not start', error.message)));
