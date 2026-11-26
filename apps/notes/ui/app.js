import { phone, ready, h, render, states, load, toast, confirm, icon, i18n } from '/sdk/runtime/kit.js';

const t = i18n({
    en: { title: 'Notes', all: 'All notes', add: 'New note', save: 'Save note', del: 'Delete', noteTitle: 'Title', noteBody: 'A thought worth keeping…',
        emptyTitle: 'Space to think', emptyDetail: 'Keep your plans, ideas, and little reminders here.', untitled: 'Untitled',
        deleteTitle: 'Delete this note?', deleteDetail: 'This cannot be undone.', saved: 'Saved', full: 'You have reached the note limit' },
    nl: { title: 'Notities', all: 'Alle notities', add: 'Nieuwe notitie', save: 'Notitie opslaan', del: 'Verwijderen', noteTitle: 'Titel', noteBody: 'Een gedachte om te bewaren…',
        emptyTitle: 'Ruimte om na te denken', emptyDetail: 'Bewaar hier je plannen, ideeën en kleine herinneringen.', untitled: 'Naamloos',
        deleteTitle: 'Deze notitie verwijderen?', deleteDetail: 'Dit kan niet ongedaan worden gemaakt.', saved: 'Opgeslagen', full: 'Je hebt de notitielimiet bereikt' },
});

const PREFIX = 'note:';
const MAX_NOTES = 100;
const root = document.getElementById('app');
const newId = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const fetchNotes = async () => {
    const stored = await phone.storage.list(PREFIX);
    return Object.entries(stored).map(([key, note]) => ({ id: key.slice(PREFIX.length), ...note })).sort((a, b) => b.updated - a.updated);
};

function shell(title, actions, body) {
    return [h('header', { class: 'kp-header' }, h('h1', { class: 'kp-title' }, title), actions), body];
}

async function showList() {
    const body = h('div', { class: 'kp-content kp-flush' });
    const add = h('button', { class: 'kp-icon-btn', 'aria-label': t('add'), onclick: () => showEditor({ id: newId(), title: '', body: '' }, true) }, icon('plus'));
    render(root, ...shell(t('title'), add, body));
    await load(body, fetchNotes, notes => h('ul', { class: 'kp-list' }, notes.map(note => h('li', null,
        h('button', { class: 'kp-row', onclick: () => showEditor(note, false) },
            h('span', { class: 'kp-row-main' },
                h('span', { class: 'kp-row-title' }, note.title || t('untitled')),
                h('span', { class: 'kp-row-sub note-body' }, note.body)))))),
    { empty: notes => notes.length === 0 && [t('emptyTitle'), t('emptyDetail')] });
}

function showEditor(note, isNew) {
    const title = h('input', { class: 'kp-input', maxlength: 100, placeholder: t('noteTitle'), 'aria-label': t('noteTitle'), value: note.title });
    const text = h('textarea', { class: 'kp-input note-editor', maxlength: 4000, placeholder: t('noteBody'), 'aria-label': t('noteBody'), value: note.body });
    const save = async () => {
        if (!title.value.trim() && !text.value.trim()) return showList();
        try {
            await phone.storage.set(PREFIX + note.id, { title: title.value.trim(), body: text.value, updated: Date.now() });
            toast(t('saved'));
            await showList();
        } catch (error) { toast(error.message); }
    };
    const remove = async () => {
        if (!(await confirm({ title: t('deleteTitle'), message: t('deleteDetail'), confirmLabel: t('del'), danger: true }))) return;
        await phone.storage.remove(PREFIX + note.id).catch(error => toast(error.message));
        await showList();
    };
    const back = h('button', { class: 'kp-icon-btn', 'aria-label': t('all'), onclick: showList }, icon('back'));
    const actions = isNew ? null : h('button', { class: 'kp-icon-btn', 'aria-label': t('del'), onclick: remove }, icon('trash'));
    render(root,
        h('header', { class: 'kp-header' }, back, h('h1', { class: 'kp-title' }, note.title || t('untitled')), actions),
        h('div', { class: 'kp-content' }, title, text),
        h('div', { class: 'kp-footer' }, h('button', { class: 'kp-btn kp-grow', 'data-variant': 'primary', onclick: save }, t('save'))));
}

(async () => {
    try {
        await ready();
        await showList();
    } catch (error) {
        render(root, states.error('Could not start', error.message));
    }
})();
