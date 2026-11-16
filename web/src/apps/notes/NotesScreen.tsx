import { Plus,Save,StickyNote,Trash2 } from 'lucide-react';
import { useState } from 'react';
import { api,requestId } from '../../api';
import { Empty } from '../../components';
import { usePhone } from '../../core/PhoneContext';
import type { Note } from '../../types';

export function NotesScreen() {
  const { data, updateData, run, busy } = usePhone();
  const [draft, setDraft] = useState<Note>();
  return <>{draft ? <form className="form" onSubmit={e => { e.preventDefault(); run(async () => { updateData(await api('notes', draft)); setDraft(undefined); }); }}><button type="button" className="text-button" onClick={() => setDraft(undefined)}>← All notes</button><label>Title<input required maxLength={100} value={draft.title} onChange={e => setDraft({ ...draft, title: e.target.value })} /></label><textarea className="note-editor" aria-label="Note body" required maxLength={4000} value={draft.body} placeholder="A thought worth keeping…" onChange={e => setDraft({ ...draft, body: e.target.value })} /><button className="primary" disabled={busy}><Save size={17} />Save note</button></form> : <><button className="primary" onClick={() => setDraft({ id: requestId(), title: '', body: '' })}><Plus size={18} />New note</button>{data.notes.map(note => <article className="note-card" key={note.id}><button onClick={() => setDraft({ ...note })}><StickyNote size={18} /><h3>{note.title}</h3><p>{note.body}</p></button><button className="icon-button" aria-label={`Delete note ${note.title}`} disabled={busy} onClick={() => run(async () => updateData(await api('notes', { ...note, remove: true })))}><Trash2 size={16} /></button></article>)}{!data.notes.length && <Empty title="Space to think" detail="Keep your plans, ideas, and little reminders here." />}</>}</>;
}
