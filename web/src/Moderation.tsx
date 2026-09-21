import { useState } from 'react';
import { api } from './api';
import { asList } from './types';
import type { ModerationReport } from './types';
import { dateLabel, Empty } from './components';
import { LoadState, useLoad, usePhone } from './PhoneContext';
import { SocialSheet } from './SocialUI';

type Action = 'dismiss' | 'remove_content' | 'suspend_profile';
const actionsFor = (report: ModerationReport): { id: Action; label: string }[] => [
  { id: 'dismiss', label: 'Dismiss' },
  report.targetType === 'profile' ? { id: 'suspend_profile', label: 'Suspend profile' } : { id: 'remove_content', label: 'Remove content' },
];
const words = (value: string) => value.replace(/_/g, ' ');
// The server snapshots whatever was reported at report time, so a moderator sees it even if it was edited later.
const preview = (report: ModerationReport) => {
  const shot = report.snapshot ?? {};
  const text = (key: string) => (typeof shot[key] === 'string' ? String(shot[key]) : '');
  if (report.targetType === 'listing') return [text('title'), typeof shot.price === 'number' ? `$${shot.price}` : '', text('description')].filter(Boolean).join('\n');
  if (report.targetType === 'profile') return [text('displayName'), text('handle') && `@${text('handle')}`, text('bio')].filter(Boolean).join('\n');
  return text('body');
};

export function ModerationScreen() {
  const { run, busy, notify } = usePhone();
  const [status, setStatus] = useState<'open' | 'reviewing'>('open');
  const queue = useLoad(() => api('moderationQueue', { status }), [status]);
  const [acting, setActing] = useState<{ report: ModerationReport; action: Action; label: string }>();
  const [note, setNote] = useState('');
  const reports = asList<ModerationReport>(queue.value);
  return <>
    <div className="segments">{(['open', 'reviewing'] as const).map(value => <button key={value} className={status === value ? 'selected' : ''} onClick={() => setStatus(value)}>{value === 'open' ? 'Open' : 'Reviewing'}</button>)}</div>
    <div className="section-heading"><span className="section-label">REPORTS</span><button className="text-button" onClick={queue.refresh}>Refresh</button></div>
    <LoadState {...queue} retry={queue.refresh} />
    {reports.map(report => <article className="post" key={report.id}>
      <div className="post-meta"><div><strong>{words(report.targetType)} · {words(report.reason)}</strong><small>{dateLabel(report.createdAt)} · report #{report.id}</small></div></div>
      <p className="post-body">{preview(report) || 'The reported content is no longer available.'}</p>
      {report.details && <p className="muted">“{report.details}”</p>}
      <div className="post-actions">{actionsFor(report).map(action => <button key={action.id} disabled={busy} onClick={() => { setNote(''); setActing({ report, action: action.id, label: action.label }); }}>{action.label}</button>)}</div>
    </article>)}
    {!reports.length && !queue.loading && <Empty title="All clear" detail="No reports need review right now." />}
    {acting && <SocialSheet title={`${acting.label}?`} detail="Your note is saved with the moderation record." onClose={() => setActing(undefined)}>
      <form onSubmit={event => {
        event.preventDefault();
        run(async () => {
          await api('moderationResolve', { reportId: acting.report.id, action: acting.action, note });
          setActing(undefined); notify('Report handled'); queue.refresh();
        });
      }}>
        <textarea aria-label="Moderator note" required minLength={3} maxLength={1000} placeholder="Why are you doing this?" value={note} onChange={event => setNote(event.target.value)} />
        <button className="primary" disabled={busy || note.trim().length < 3}>Confirm</button>
      </form>
    </SocialSheet>}
  </>;
}
