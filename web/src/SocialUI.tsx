import { useEffect, useRef } from 'react';
import type { ReactNode } from 'react';
import { ArrowLeft, Users, X } from 'lucide-react';
import { PhotoImage } from './Images';
import { usePhone } from './PhoneContext';

export function SocialAvatar({ name, photo, group = false }: { name: string; photo?: string; group?: boolean }) {
  return <span className={`social-avatar ${group ? 'is-group' : ''}`}>{group ? <Users size={21} /> : photo ? <PhotoImage src={photo} alt="" /> : <span>{/^\d+$/.test(name) ? name.slice(-2) : name.split(/\s+/).map(word => word[0]).slice(0, 2).join('').toUpperCase()}</span>}</span>;
}
export function SocialHeader({ name, mark, actions }: { name: string; mark: ReactNode; actions?: ReactNode }) {
  const { navigate } = usePhone();
  return <header className="social-header"><button className="icon-button" aria-label="Back to phone" onClick={() => navigate('home')}><ArrowLeft size={19} /></button><h1><span className="social-brand-mark">{mark}</span>{name}<i /></h1><div className="social-header-actions">{actions}</div></header>;
}
export function SocialSheet({ title, detail, children, onClose }: { title: string; detail?: string; children: ReactNode; onClose: () => void }) {
  const root = useRef<HTMLDivElement>(null);
  const close = useRef(onClose); close.current = onClose;
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const panel = root.current!;
    panel.focus();
    const key = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); close.current(); }
      if (event.key !== 'Tab') return;
      const elements = [...panel.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),textarea:not(:disabled),select:not(:disabled),[tabindex="0"]')].filter(el => el.getClientRects().length);
      const first = elements[0], last = elements[elements.length - 1];
      if (!first) { event.preventDefault(); return; }
      if (event.shiftKey && (document.activeElement === first || document.activeElement === panel)) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && (document.activeElement === last || document.activeElement === panel)) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', key, true);
    return () => { document.removeEventListener('keydown', key, true); if (previous?.isConnected) previous.focus(); };
  }, []);
  return <div className="social-sheet-backdrop"><div className="social-sheet" role="dialog" aria-modal="true" aria-label={title} ref={root} tabIndex={-1}><div className="sheet-handle" aria-hidden="true" /><header><div><h2>{title}</h2>{detail && <p>{detail}</p>}</div><button className="icon-button" aria-label="Close panel" onClick={onClose}><X size={20} /></button></header><div className="social-sheet-body">{children}</div></div></div>;
}
export function messageTime(value?: string | null) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toDateString() === new Date().toDateString() ? date.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}
