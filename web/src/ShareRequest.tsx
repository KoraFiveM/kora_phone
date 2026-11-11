import { useEffect, useRef, useState } from 'react';
import { ContactRound } from 'lucide-react';
import { nui } from './api';

export type ShareRequest = { id: string; label: string; number: string; expiresIn: number; shareBack: boolean; at: number };

type Reply = { ok: boolean; data?: { existing?: boolean; name?: string; sharedBack?: boolean }; error?: string | { message?: string } };

// Accepts anything the client forwards and keeps only well-formed values; text is rendered as text, never HTML.
export function parseShareRequest(data: unknown): ShareRequest | undefined {
  if (!data || typeof data !== 'object') return undefined;
  const value = data as Record<string, unknown>;
  if (typeof value.id !== 'string' || !value.id || value.id.length > 64 || typeof value.number !== 'string') return undefined;
  const seconds = Number(value.expiresIn);
  return {
    id: value.id,
    label: (typeof value.label === 'string' && value.label.trim() ? value.label : 'Someone').slice(0, 64),
    number: value.number.replace(/\D/g, '').slice(0, 15),
    expiresIn: Number.isFinite(seconds) ? Math.min(120, Math.max(1, seconds)) : 30,
    shareBack: value.shareBack === true,
    at: Date.now(),
  };
}

const pretty = (number: string) => number.length === 10 ? `${number.slice(0, 3)}-${number.slice(3, 6)}-${number.slice(6)}` : number;
const problem = (reply: Reply, fallback: string) => typeof reply.error === 'string' && !/^[A-Z_]+$/.test(reply.error) ? reply.error : typeof reply.error === 'object' && reply.error?.message ? reply.error.message : fallback;

// Shown inside the phone screen when someone nearby shares their number while the phone is open.
export function ShareRequestSheet({ request, onClose, onSaved, onMessage }: { request: ShareRequest; onClose: () => void; onSaved: () => void; onMessage: (text: string) => void }) {
  const [name, setName] = useState(request.label);
  const [shareBack, setShareBack] = useState(false);
  const [busy, setBusy] = useState(false);
  const [left, setLeft] = useState(request.expiresIn);
  const answered = useRef(false);
  const dialog = useRef<HTMLDivElement>(null);
  const callbacks = useRef({ onClose, onMessage });
  callbacks.current = { onClose, onMessage };

  useEffect(() => {
    const tick = () => {
      const remaining = Math.ceil(request.expiresIn - (Date.now() - request.at) / 1000);
      setLeft(remaining);
      if (remaining <= 0 && !answered.current) { answered.current = true; callbacks.current.onMessage('The number request expired.'); callbacks.current.onClose(); }
    };
    tick();
    const timer = setInterval(tick, 500);
    return () => clearInterval(timer);
  }, [request]);
  useEffect(() => { dialog.current?.querySelector<HTMLInputElement>('input')?.focus(); }, [request.id]);

  const respond = async (accept: boolean) => {
    if (answered.current) return;
    answered.current = true; setBusy(true);
    try {
      const reply = await nui<Reply>('share:answer', { id: request.id, accept, name: name.trim() || request.label, shareBack: accept && shareBack });
      if (!accept) return;
      if (!reply.ok) { onMessage(problem(reply, 'Could not save the contact.')); return; }
      onMessage(reply.data?.existing ? 'That number is already in your contacts.' : `Saved ${reply.data?.name || name} to your contacts.${reply.data?.sharedBack ? ' Your number was shared back.' : ''}`);
      onSaved();
    } catch { onMessage('Could not save the contact.'); }
    finally { setBusy(false); onClose(); }
  };

  const valid = name.trim().length > 0 && name.length <= 64;
  return <div ref={dialog} className="share-request-sheet" role="alertdialog" aria-modal="true" aria-labelledby="share-request-title"
    onKeyDown={event => { if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); void respond(false); } }}>
    <div>
      <ContactRound size={26} aria-hidden="true" />
      <h2 id="share-request-title">{request.label} wants to share their number</h2>
      <p className="share-request-number">{pretty(request.number)}</p>
      <label>Save as<input value={name} maxLength={64} disabled={busy} onChange={event => setName(event.target.value)} /></label>
      {request.shareBack && <label className="share-request-back"><input type="checkbox" checked={shareBack} disabled={busy} onChange={event => setShareBack(event.target.checked)} />Share my number back</label>}
      <p className="share-request-timer" aria-live="polite">{left > 0 ? `Expires in ${left}s` : 'Expired'}</p>
      <div className="share-request-actions">
        <button className="text-button" disabled={busy} onClick={() => void respond(false)}>Decline</button>
        <button className="share-request-accept" disabled={busy || !valid || left <= 0} onClick={() => void respond(true)}>Save contact</button>
      </div>
    </div>
  </div>;
}
