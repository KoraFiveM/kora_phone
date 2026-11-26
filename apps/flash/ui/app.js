import { phone, ready, h, render, states, toast, confirm, menu, pick, icon, i18n } from '/sdk/runtime/kit.js';
import { createClipRecorder } from '/sdk/runtime/recorder.js';

const t = i18n({ en: { title: 'Flash', refresh: 'Refresh feed', explore: 'Explore', mine: 'Your posts', capture: 'Capture a moment', exploreTitle: 'Life, in a flash.', mineTitle: 'Your point of view.',
    profileTitle: 'Set up your Flash profile', profileDetail: 'Your handle and name show on everything you post.', handle: 'Handle', displayName: 'Display name', createProfile: 'Create profile',
    resting: 'The camera is resting.', restingDetail: 'Media uploads have not been configured on this server.', emptyMine: 'Make your first moment.', emptyAll: 'The city is yours.',
    emptyMineDetail: 'Capture something worth sharing.', emptyAllDetail: 'Be the first to show your side of Los Santos.', older: 'Explore older moments', you: 'You',
    like: 'Like post', unlike: 'Unlike post', comments: 'View comments', send: 'Send', remove: 'Remove post', removeTitle: 'Remove this moment?', removeDetail: 'It will disappear from the public feed.',
    photo: 'Photo', video: 'Video', caption: 'A few words', record: 'Record a clip', stop: 'Stop recording', retake: 'Retake clip', publish: 'Publish', posted: 'Posted to Flash', big: 'That clip is too big. Try a shorter one.',
    capturePhoto: 'Capture & publish', mute: 'Mute clip', unmute: 'Unmute clip', commentPlaceholder: 'Add a comment', shareTitle: 'Pass it on.', noChats: 'Start a chat in Pulse first.', openPulse: 'Open Pulse',
    getPulse: 'Install Pulse from the App Store to share moments.', shared: 'Shared to Pulse', note: 'Posts are public and stay until removed.', failed: 'This moment couldn’t load.', retry: 'Try again', group: 'Group' } });
const root = document.getElementById('app');
const attempt = async work => { try { return await work(); } catch (error) { toast(error.message); return undefined; } };
const ref = () => `f-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
const day = value => { const date = new Date(typeof value === 'number' ? value * 1000 : value); return Number.isNaN(date.getTime()) ? '' : date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }); };
const kindOf = mime => String(mime || '').startsWith('video') ? 'video' : 'photo';

let cfg = { number: '', flash: false, media: true, moderator: false };
let names = {};
let posts = [];
let tab = 'explore';
let muted = true;
let recorder;
let needsProfile = false;
const failed = new Set();
let observer;

const author = post => post.handle === undefined ? '' : names[post.handle] || post.displayName || post.handle;

function mediaNode(post) {
    const url = post.mediaUrl;
    if (failed.has(post.id)) return h('div', { class: 'kp-card' }, h('p', null, t('failed')), h('button', { class: 'kp-btn', onclick: () => { failed.delete(post.id); paint(); } }, t('retry')));
    if (kindOf(post.mediaMime) === 'video') {
        const video = h('video', { src: url, loop: true, muted, playsinline: true, preload: 'metadata' });
        video.addEventListener('error', () => { failed.add(post.id); paint(); });
        if (observer) observer.observe(video);
        return h('div', { class: 'flash-media' }, video,
            h('button', { class: 'kp-icon-btn', 'aria-label': muted ? t('unmute') : t('mute'), style: 'position:absolute;right:8px;bottom:8px', onclick: () => { muted = !muted; paint(); } }, icon(muted ? 'x' : 'play')));
    }
    const img = h('img', { src: url, alt: post.body || t('photo'), loading: 'lazy', referrerpolicy: 'no-referrer' });
    img.addEventListener('error', () => { failed.add(post.id); paint(); });
    return h('div', { class: 'flash-media' }, img);
}

function card(post) {
    const mine = post.mine === 1 || post.mine === true;
    const liked = post.liked === 1 || post.liked === true;
    return h('section', { class: 'kp-card flash-card' }, post.mediaUrl ? mediaNode(post) : null,
        h('div', { class: 'flash-body' },
            h('div', { class: 'kp-row-flex' }, h('div', { class: 'kp-grow' }, h('strong', null, mine ? t('you') : author(post)), h('small', { class: 'kp-row-sub' }, ` ${day(post.createdAt)}`)),
                (mine || cfg.moderator) ? h('button', { class: 'kp-icon-btn', 'aria-label': t('remove'), onclick: async () => {
                    if (!(await confirm({ title: t('removeTitle'), message: t('removeDetail'), confirmLabel: t('remove'), danger: true }))) return;
                    if (await attempt(async () => { await phone.callback('remove', { id: post.id }); return true; })) { posts = posts.filter(item => item.id !== post.id); paint(); }
                } }, icon('trash')) : null),
            post.body ? h('p', null, post.body) : null,
            h('div', { class: 'flash-actions' },
                h('button', { class: 'kp-btn', 'data-variant': 'ghost', 'aria-pressed': liked, 'aria-label': liked ? t('unlike') : t('like'), onclick: async () => {
                    if (await attempt(async () => { await phone.callback('like', { id: post.id, liked: !liked }); return true; })) {
                        post.liked = liked ? 0 : 1; post.likeCount = (post.likeCount || 0) + (liked ? -1 : 1); paint();
                    }
                } }, `♥ ${post.likeCount || 0}`),
                h('button', { class: 'kp-btn', 'data-variant': 'ghost', 'aria-label': t('comments'), onclick: () => openComments(post) }, `💬 ${post.commentCount || 0}`),
                h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => share(post) }, t('send')))));
}

async function openComments(post) {
    const holder = h('div', null, states.loading());
    const input = h('input', { class: 'kp-input', maxlength: 1000, 'aria-label': t('commentPlaceholder'), placeholder: t('commentPlaceholder') });
    const loadComments = async () => {
        try {
            const rows = await phone.callback('comments', { id: post.id });
            render(holder, rows.map(comment => h('div', { class: 'comment' }, h('strong', null, comment.handle || comment.displayName || ''), h('p', null, comment.body),
                cfg.moderator ? h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: async () => { if (await attempt(async () => { await phone.callback('removeComment', { id: comment.id }); return true; })) loadComments(); } }, t('remove')) : null)));
        } catch (error) { render(holder, states.error('Something went wrong', error.message, loadComments)); }
    };
    const back = () => { show(); };
    render(root, h('header', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('title'), onclick: back }, icon('back')), h('h1', { class: 'kp-title' }, t('comments'))),
        h('div', { class: 'kp-content' }, holder), h('div', { class: 'kp-footer' }, input, h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
            const body = input.value.trim();
            if (!body) return;
            if (await attempt(async () => { await phone.callback('comment', { id: post.id, body, clientRequestId: ref() }); return true; })) { input.value = ''; post.commentCount = (post.commentCount || 0) + 1; loadComments(); }
        } }, t('send'))));
    loadComments();
}

async function share(post) {
    if (!cfg.installedPulse) { toast(t('getPulse')); return; }
    const chats = await attempt(() => phone.callback('chats'));
    if (!chats) return;
    if (!chats.length) { toast(t('noChats')); phone.open('social').catch(() => {}); return; }
    const chosen = await pick({ title: t('shareTitle'), items: chats.map(chat => ({ title: chat.title || names[chat.peerPhoneNumber] || chat.peerPhoneNumber || t('group'), chat })) });
    if (!chosen) return;
    if (await attempt(async () => { await phone.callback('share', { conversationId: chosen.chat.id, body: post.body, mediaUrl: post.mediaUrl, mediaKind: kindOf(post.mediaMime), clientRequestId: ref() }); return true; })) toast(t('shared'));
}

function profileForm() {
    const base = String(cfg.character || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 20) + Math.floor(10 + Math.random() * 90);
    const handle = h('input', { class: 'kp-input', required: true, pattern: '[A-Za-z0-9_]{3,24}', maxlength: 24, 'aria-label': t('handle'), value: base });
    const name = h('input', { class: 'kp-input', required: true, maxlength: 64, 'aria-label': t('displayName'), value: cfg.character || '' });
    return h('section', { class: 'kp-card' }, h('h2', { class: 'kp-row-title' }, t('profileTitle')), h('p', { class: 'kp-row-sub' }, t('profileDetail')),
        h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('handle')), handle), h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('displayName')), name),
        h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
            if (await attempt(async () => { await phone.callback('createProfile', { handle: handle.value.trim(), displayName: name.value.trim() }); return true; })) { needsProfile = false; await reloadFeed(); }
        } }, t('createProfile')));
}

function compose() {
    let kind = 'photo';
    let clip;
    let progress = 0;
    const caption = h('textarea', { class: 'kp-input', rows: 2, maxlength: 2000, 'aria-label': t('caption'), placeholder: t('caption') });
    const stage = h('div', { class: 'stage' });
    const bar = h('div');
    const actions = h('div');
    const maxBytes = cfg.flash && cfg.flash.maxBytes;
    const setProgress = value => { progress = value; render(bar, progress > 0 && progress < 1 ? h('div', { class: 'progress', role: 'progressbar', 'aria-label': t('title'), 'aria-valuenow': Math.round(progress * 100) }, h('i', { style: `width:${Math.round(progress * 100)}%` })) : null); };
    const done = () => { if (recorder) recorder.discard(); show(); };
    const paint = () => {
        render(stage, clip ? h('video', { src: clip.url, controls: true, playsinline: true }) : h('p', { class: 'kp-row-sub' }, kind === 'photo' ? 'Captures your game view' : 'Uses your real webcam & microphone'));
        const recording = recorder && recorder.state().recording;
        if (kind === 'photo') {
            render(actions, h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
                const shot = await attempt(() => phone.camera.capture());
                if (!shot) return;
                if (await attempt(async () => { await phone.callback('post', { body: caption.value, mediaId: shot.id, clientRequestId: ref() }); return true; })) { toast(t('posted')); show(); }
            } }, t('capturePhoto')));
        } else if (clip) {
            render(actions, h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
                if (maxBytes && clip.blob.size > maxBytes) { toast(t('big')); return; }
                const saved = await attempt(() => phone.media.upload(clip.blob));
                if (!saved) return;
                if (await attempt(async () => { await phone.callback('post', { body: caption.value, mediaId: saved.id, clientRequestId: ref() }); return true; })) { toast(t('posted')); done(); }
            } }, t('publish')), h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => { clip = undefined; recorder.discard(); paint(); } }, t('retake')));
        } else {
            render(actions, h('button', { class: 'kp-btn', 'data-variant': 'primary', onclick: async () => {
                if (recording) { recorder.stop(); return; }
                await attempt(() => recorder.start());
                paint();
            } }, recording ? t('stop') : t('record')));
        }
    };
    recorder = createClipRecorder(cfg.flash ? cfg.flash.maxSeconds : 15, state => { clip = state.clip; paint(); });
    const tabs = h('div', { class: 'kp-segmented' }, [['photo', t('photo')], ...(cfg.flash ? [['video', t('video')]] : [])].map(([id, label]) => h('button', { 'aria-pressed': kind === id, onclick: () => { kind = id; clip = undefined; recorder.discard(); drawTabs(); paint(); } }, label)));
    const drawTabs = () => render(tabs, [['photo', t('photo')], ...(cfg.flash ? [['video', t('video')]] : [])].map(([id, label]) => h('button', { 'aria-pressed': kind === id, onclick: () => { kind = id; clip = undefined; recorder.discard(); drawTabs(); paint(); } }, label)));
    drawTabs();
    render(root, h('header', { class: 'kp-header' }, h('button', { class: 'kp-icon-btn', 'aria-label': t('title'), onclick: done }, icon('back')), h('h1', { class: 'kp-title' }, t('capture'))),
        h('div', { class: 'kp-content' }, tabs, stage, h('div', { class: 'kp-field' }, h('label', { class: 'kp-label' }, t('caption')), caption), actions, bar, h('p', { class: 'kp-row-sub' }, t('note'))));
    paint();
}

function paint() {
    const holder = document.getElementById('feed');
    if (!holder) return;
    if (observer) observer.disconnect();
    observer = new IntersectionObserver(entries => entries.forEach(entry => { const video = entry.target; if (entry.isIntersecting && entry.intersectionRatio > 0.6) video.play().catch(() => {}); else video.pause(); }), { threshold: [0, 0.6, 1] });
    const shown = tab === 'mine' ? posts.filter(post => post.mine === 1 || post.mine === true) : posts;
    if (!cfg.media) { render(holder, states.empty(t('resting'), t('restingDetail'))); return; }
    render(holder, needsProfile ? profileForm() : null,
        shown.map(card),
        !shown.length && !needsProfile ? (tab === 'mine' ? states.empty(t('emptyMine'), t('emptyMineDetail')) : states.empty(t('emptyAll'), t('emptyAllDetail'))) : null,
        posts.length >= 30 ? h('button', { class: 'kp-btn', 'data-variant': 'ghost', onclick: () => attempt(async () => {
            const more = await phone.callback('feed', { before: Math.min(...posts.map(post => post.id)) });
            posts = posts.concat(more.filter(row => !posts.some(known => known.id === row.id))); paint();
        }) }, t('older')) : null);
}

async function reloadFeed() {
    const holder = document.getElementById('feed');
    if (holder) render(holder, states.loading());
    try { posts = await phone.callback('feed', {}); needsProfile = false; failed.clear(); } catch (error) {
        if (/social profile/i.test(error.message)) { needsProfile = true; posts = []; }
        else { if (holder) render(holder, states.error('Something went wrong', error.message, reloadFeed)); return; }
    }
    paint();
}

function show() {
    const tabs = h('div', { class: 'kp-segmented' }, [['explore', t('explore')], ['mine', t('mine')]].map(([id, label]) => h('button', { 'aria-pressed': tab === id, onclick: () => { tab = id; show(); } }, label)));
    render(root, h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, t('title')),
        h('button', { class: 'kp-icon-btn', 'aria-label': t('refresh'), onclick: reloadFeed }, icon('search'))),
        h('div', { class: 'kp-content' }, tabs, h('h2', { class: 'kp-row-title' }, tab === 'explore' ? t('exploreTitle') : t('mineTitle')), h('div', { id: 'feed' })),
        h('div', { class: 'kp-footer' }, h('button', { class: 'kp-btn kp-grow', 'data-variant': 'primary', disabled: !cfg.media, onclick: compose }, t('capture'))));
    if (posts.length || needsProfile) paint(); else reloadFeed();
}

ready().then(async () => {
    cfg = await phone.callback('config');
    const people = await phone.contacts.list().catch(() => []);
    names = Object.fromEntries(people.map(contact => [contact.number, contact.name]));
    show();
}).catch(error => render(root, states.error('Could not start', error.message)));
