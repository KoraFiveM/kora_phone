import { phone, ready, h, render, states, toast, confirm, pick as choose, icon, i18n } from '/sdk/runtime/kit.js';
import { parseToken, previewText } from '/sdk/runtime/chat-tokens.js';

const t = i18n({ en: { title: 'Messages', compose: 'New message', all: 'All messages', to: 'Phone number', placeholder: 'Message', send: 'Send', attach: 'Attach gallery photo',
    removeAttachment: 'Remove attachment', del: 'Delete message for me', emptyTitle: 'Start a conversation', emptyDetail: 'A simple hello goes a long way.', older: 'Older conversations',
    unread: 'unread', noMessages: 'No messages yet', photo: 'Photo', noPhotos: 'Take a photo in Camera before attaching it here.', archived: 'Archived group · read only', you: 'You', sent: 'Sent a photo',
    youDeleteTitle: 'Delete this message for you?', youDeleteDetail: 'The other person still has it.', group: 'Group', waypoint: 'Shared a location' } });
const root = document.getElementById('app');
const PAGE = 50;
const ref = () => `msg-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
const day = value => { const date = new Date(typeof value === 'number' ? value * 1000 : value); return Number.isNaN(date.getTime()) ? '' : date.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }); };
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };

let me = '';
let names = {};
let conversations = [];
let active;       // the open conversation
let messages = [];
let attachment;   // a gallery photo chosen for the next message

const nameOf = number => names[number] || number || t('group');
const peerOf = conversation => conversation.peerPhoneNumber || '';
const titleOf = conversation => conversation.title || (conversation.type === 'group' ? t('group') : nameOf(peerOf(conversation)));

async function loadConversations(more) {
    const last = conversations[conversations.length - 1];
    const result = await phone.callback('conversations', more && last ? { before: last.sortId ?? last.lastMessageId ?? last.id, cursorId: last.id } : {});
    me = result.number || me;
    conversations = more ? conversations.concat(result.items) : result.items;
    return result.items;
}

// One screen: a header and a split. Narrow, the split shows the list or the open conversation; wide (Atlas Fold unfolded) both.
function frame() {
    const compose = h('button', { class: 'kp-icon-btn', 'aria-label': t('compose'), onclick: newMessage }, icon('plus'));
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title')), compose),
        h('div', { class: 'kp-split', id: 'split' }, h('div', { 'data-pane': 'list', id: 'listPane', class: 'kp-flush' }), h('div', { 'data-pane': 'detail', id: 'detailPane' })));
}

const split = () => document.getElementById('split');
const showDetail = open => { const el = split(); if (el) { if (open) el.setAttribute('data-detail', 'open'); else el.removeAttribute('data-detail'); } };

async function list() {
    active = undefined; messages = []; attachment = undefined;
    if (!split()) frame();
    showDetail(false);
    render(document.getElementById('detailPane'));
    const holder = document.getElementById('listPane');
    render(holder, states.loading());
    try {
        await loadConversations(false);
    } catch (error) { render(holder, states.error('Something went wrong', error.message, list)); return; }
    paintList(holder);
}

function paintList(holder) {
    if (!conversations.length) { render(holder, states.empty(t('emptyTitle'), t('emptyDetail'))); return; }
    render(holder, h('ul', { class: 'kp-list' }, conversations.map(conversation => h('li', null, h('button', { class: 'kp-row', 'aria-selected': !!active && active.id === conversation.id, onclick: () => open(conversation) },
        h('span', { class: 'contact-photo' }),
        h('span', { class: 'kp-row-main' },
            h('span', { class: 'kp-row-title' }, titleOf(conversation)),
            h('span', { class: 'kp-row-sub' }, previewText(conversation.lastMessagePreview) || (conversation.lastMediaMime ? t('photo') : t('noMessages')))),
        conversation.unreadCount > 0 && h('span', { class: 'unread' }, `${conversation.unreadCount}`))))),
        conversations.length % PAGE === 0 && h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => attempt(async () => { await loadConversations(true); paintList(holder); }) }, t('older')));
}

function newMessage() {
    const input = h('input', { class: 'kp-input', inputmode: 'tel', maxlength: 16, 'aria-label': t('to'), placeholder: t('to') });
    const go = h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: () => {
        const number = input.value.replace(/\D/g, '');
        if (/^\d{7,16}$/.test(number)) startWith(number);
    } }, t('compose'));
    showDetail(true);
    render(document.getElementById('detailPane'),
        h('div', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('all'), onclick: () => showDetail(false) }, icon('back')), h('h2', { class: 'kp-title' }, t('compose'))),
        h('div', { class: 'kp-content' }, input, go));
}

async function startWith(number) {
    const conversation = await attempt(() => phone.callback('start', { number }));
    if (conversation) open({ ...conversation, peerPhoneNumber: conversation.peerPhoneNumber || number });
}

function bubble(message) {
    const mine = message.isMine === 1 || message.isMine === true;
    const token = parseToken(message.body);
    let content;
    if (token && token.kind === 'photo') content = h('img', { src: token.url, alt: t('photo') });
    else if (token && token.kind === 'video') content = h('video', { src: token.url, controls: true, playsinline: true, preload: 'metadata' });
    else if (token) content = h('p', null, `${t('waypoint')}: ${token.label}`);
    else content = message.body ? h('p', null, message.body) : null;
    const del = h('button', { class: 'kp-icon-btn', 'aria-label': t('del'), onclick: async () => {
        if (!(await confirm({ title: t('youDeleteTitle'), message: t('youDeleteDetail'), confirmLabel: t('del'), danger: true }))) return;
        await attempt(async () => { await phone.callback('delete', { messageId: message.id }); messages = messages.filter(item => item.id !== message.id); paintThread(); });
    } }, icon('trash'));
    return h('div', { class: 'bubble', 'data-mine': mine },
        message.mediaUrl && !token ? h('img', { src: message.mediaUrl, alt: t('photo') }) : null, content,
        h('small', null, `${day(message.createdAt)} · ${mine ? t('you') : nameOf(message.senderNumber)}`), del);
}

function paintThread() {
    const holder = document.getElementById('thread');
    if (!holder) return;
    const ordered = messages.slice().sort((a, b) => a.id - b.id);
    render(holder, ordered.length ? ordered.map(bubble) : states.empty(t('emptyTitle'), t('emptyDetail')));
    holder.scrollTop = holder.scrollHeight;
}

async function loadThread() {
    const rows = await phone.callback('thread', { id: active.id });
    messages = rows;
    paintThread();
    phone.callback('read', { id: active.id, messageId: rows[0] && rows[0].id }).catch(() => {});
}

async function open(conversation) {
    active = conversation; messages = []; attachment = undefined;
    if (!split()) frame();
    const archived = peerOf(conversation).startsWith('@group:');
    const body = h('textarea', { class: 'kp-input', maxlength: 1900, rows: 1, 'aria-label': t('placeholder'), placeholder: t('placeholder') });
    const preview = h('div');
    const paintAttachment = () => render(preview, attachment ? h('div', { class: 'attachment' }, h('img', { src: attachment.url, alt: '' }),
        h('button', { class: 'kp-icon-btn', 'aria-label': t('removeAttachment'), onclick: () => { attachment = undefined; paintAttachment(); } }, icon('x'))) : null);
    const pickPhoto = async () => {
        const photos = await attempt(() => phone.callback('photos'));
        if (!photos) return;
        if (!photos.length) { toast(t('noPhotos')); return; }
        const chosen = await choose({ title: t('attach'), items: photos.map((photo, index) => ({ title: `${t('photo')} ${index + 1}`, photo })) });
        if (chosen) { attachment = chosen.photo; paintAttachment(); }
    };
    const send = async () => {
        const text = body.value.trim();
        if (!text && !attachment) return;
        const sent = await attempt(() => phone.callback('send', { conversationId: conversation.id, body: text, mediaId: attachment ? Number(attachment.id) : undefined, clientRequestId: ref() }));
        if (sent) { body.value = ''; attachment = undefined; paintAttachment(); messages = messages.concat(sent); paintThread(); }
    };
    showDetail(true);
    render(document.getElementById('detailPane'),
        h('div', { class: 'kp-app' },
            h('div', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('all'), onclick: () => { showDetail(false); active = undefined; } }, icon('back')), h('h2', { class: 'kp-title' }, titleOf(conversation))),
            h('div', { class: 'kp-content thread', id: 'thread' }, states.loading()),
            archived ? h('div', { class: 'kp-footer' }, h('p', { class: 'kp-row-sub' }, t('archived')))
                : h('div', { class: 'kp-footer', style: 'flex-direction:column' }, preview, h('div', { class: 'composer' },
                    h('button', { class: 'kp-icon-btn', 'aria-label': t('attach'), onclick: pickPhoto }, icon('camera')), body,
                    h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: send }, t('send'))))));
    await attempt(loadThread);
}

// The phone tells open apps when a message arrives or is read on another screen.
phone.on('messages:new', async () => {
    if (active) await attempt(loadThread);
    await attempt(() => loadConversations(false));
    const holder = document.getElementById('listPane');
    if (holder) paintList(holder);
});

ready().then(async init => {
    const people = await phone.contacts.list().catch(() => []);
    names = Object.fromEntries(people.map(contact => [contact.number, contact.name]));
    if (init.target && /^\d{7,16}$/.test(init.target)) { await startWith(init.target); return; }
    await list();
}).catch(error => render(root, states.error('Could not start', error.message)));
