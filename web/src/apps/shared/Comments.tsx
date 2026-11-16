import { Send,Trash2 } from 'lucide-react';
import { useState } from 'react';
import { api } from '../../api';
import { LoadState,useLoad,usePhone } from '../../core/PhoneContext';
import type { Comment,Post } from '../../types';
import { asList } from '../../types';

export function Comments({ post }: { post: Post }) {
  const { run, busy, device } = usePhone();
  const comments = useLoad(() => api('comments', { id: post.id }), [post.id]);
  const [body, setBody] = useState('');
  return <div className="comments"><LoadState {...comments} retry={comments.refresh} />{asList<Comment>(comments.value).map(comment => <div className="comment" key={comment.id}><div><strong>{comment.number}</strong><p>{comment.body}</p></div>{(device.admin || comment.number === device.number) && <button className="icon-button" aria-label="Delete comment" disabled={busy} onClick={() => run(async () => { await api('removeComment', { id: comment.id }); comments.refresh(); })}><Trash2 size={14} /></button>}</div>)}<form className="composer" onSubmit={e => { e.preventDefault(); run(async () => { await api('comment', { id: post.id, body }); setBody(''); comments.refresh(); }); }}><input aria-label="Comment" required maxLength={500} value={body} placeholder="Add your thoughts" onChange={e => setBody(e.target.value)} /><button className="icon-button" disabled={busy} aria-label="Send comment"><Send size={17} /></button></form></div>;
}
