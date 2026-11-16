import { Mail as MailIcon,Trash2 } from 'lucide-react';
import { useEffect,useState } from 'react';
import { api } from '../../api';
import { dateLabel,Empty,Row } from '../../components';
import { LoadState,useLoad,usePhone } from '../../core/PhoneContext';
import type { MailItem } from '../../types';
import { asList } from '../../types';

export function MailScreen(_props: { target: string }) {
  const { run, busy, revision } = usePhone();
  const [tab, setTab] = useState<'inbox' | 'activity'>('inbox');
  const list = useLoad(() => api('systemMailList', {}), [revision]);
  const activity = useLoad(() => api('systemActivity', {}), [revision]);
  const [open, setOpen] = useState<MailItem>();
  const [more, setMore] = useState(true);
  useEffect(() => { setMore(true); }, [revision, tab]);
  const read = (item: MailItem) => {
    setOpen(item);
    if (item.unread) void run(async () => { await api('systemMailRead', { id: item.id }); list.refresh(); });
  };
  if (open) return <article className="mail-read">
    <button className="text-button" onClick={() => setOpen(undefined)}>← Inbox</button>
    <h3>{open.subject}</h3><p className="muted">From {open.peer} · {dateLabel(open.created_at)}</p>
    <p className="mail-body">{open.body}</p>
    {open.hasAction && <button className="primary" disabled={busy} onClick={() => run(async () => { const { accepted } = await api('mailAccept', { id: open.id }); if (accepted) setOpen({ ...open, hasAction: false }); list.refresh(); })}>Accept</button>}
    <button className="text-button danger" disabled={busy} onClick={() => run(async () => { await api('systemMailDelete', { id: open.id }); setOpen(undefined); list.refresh(); })}><Trash2 size={15} />Delete</button>
  </article>;
  const items = asList<MailItem>(list.value);
  return <><div className="segments" role="group" aria-label="Mail sections">{(['inbox', 'activity'] as const).map(value => <button type="button" key={value} className={tab === value ? 'selected' : ''} aria-pressed={tab === value} onClick={() => setTab(value)}>{value === 'inbox' ? 'Inbox' : 'Activity'}</button>)}</div>
    {tab === 'inbox' ? <><p className="muted">System mail follows your character across handsets.</p>
      <LoadState {...list} retry={list.refresh} />
      {items.map(item => <Row key={item.id} title={item.subject} detail={`From ${item.peer} · ${dateLabel(item.created_at)}`} icon={<MailIcon size={18} />} end={item.unread ? <i className="mail-dot" aria-label="Unread" /> : undefined} onClick={() => read(item)} />)}
      {!items.length && !list.loading && <Empty title="Nothing new" detail="Job offers, invoices and updates arrive here." />}
      {more && items.length >= 50 && <button className="text-button" disabled={busy} onClick={() => run(async () => { const rows=await api('systemMailList', {before:items[items.length-1].id}); list.setValue([...items,...rows]); setMore(rows.length===50); })}>Older mail</button>}
    </> : <><p className="muted">Informational activity. These notes do not change your balance.</p>
      <LoadState {...activity} retry={activity.refresh} />
      {activity.value?.map(item=><article className="note-card" key={item.id}><h3>{item.title}</h3><p className="mail-body">{item.message}</p><small>{dateLabel(item.created_at)}</small></article>)}
      {!activity.value?.length && !activity.loading && <Empty title="No activity yet" detail="Transaction notes from city services appear here." />}
      {more && (activity.value?.length || 0)>=50 && <button className="text-button" disabled={busy} onClick={() => run(async () => { const items=activity.value!; const rows=await api('systemActivity',{before:items[items.length-1].id}); activity.setValue([...items,...rows]);setMore(rows.length===50); })}>Older activity</button>}
    </>}
  </>;
}
