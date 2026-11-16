import { ShieldCheck, X } from 'lucide-react';
import { useEffect, useRef } from 'react';
import { nui } from '../api';
import { HandsetPanel } from '../apps/handset/HandsetPanel';
import { usePhoneStore } from './storeContext';

type Reply = { ok: boolean; error?: string | { message?: string } };
const OPERATIONS: Record<string, string> = { buy: 'a purchase', replaceSim: 'a SIM replacement', recoverCloud: 'cloud account recovery', resell: 'handset resale', insertSim: 'SIM insertion', removeSim: 'SIM removal' };

/** Mobile-shop consent and result dialogs, plus the full-screen service panel, shown even while the phone is closed. */
export function ServiceDialogs() {
  const { state, dispatch, actions } = usePhoneStore();
  const { serviceRequest: request, serviceResult: result, serviceOpen, shown, busy } = state;
  const dialog = useRef<HTMLDivElement>(null);
  const patch = (value: Partial<typeof state>) => dispatch({ type: 'patch', patch: value });

  // Escape declines a request or dismisses a result; Tab stays inside the dialog.
  useEffect(() => {
    if (!request && !result) return;
    const previous = document.activeElement as HTMLElement | null;
    dialog.current?.querySelector<HTMLButtonElement>('button')?.focus();
    const trap = (event: KeyboardEvent) => {
      if (event.key !== 'Tab') return;
      const buttons = dialog.current?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)');
      if (!buttons?.length) return;
      const first = buttons[0], last = buttons[buttons.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', trap);
    return () => { document.removeEventListener('keydown', trap); previous?.focus(); };
  }, [request, result]);

  const finish = () => { if (!shown && !serviceOpen) void nui('close'); };
  const decline = () => actions.run(async () => {
    if (!request) return;
    await nui('handset:action', { op: 'consent', id: request.id, accept: false });
    patch({ serviceRequest: undefined }); finish();
  });
  const accept = () => actions.run(async () => {
    if (!request) return;
    const reply = await nui<Reply>('handset:action', { op: 'consent', id: request.id, accept: true });
    if (!reply.ok) throw new Error(typeof reply.error === 'string' ? reply.error : reply.error?.message || 'Service could not complete');
    patch({ serviceRequest: undefined });
  });

  return <>
    {(request || result) && <div ref={dialog} className="phone-service-consent" role="alertdialog" aria-modal="true" aria-label={request ? 'Approve mobile service' : 'Mobile service result'}><div><ShieldCheck size={28} /><h2>{request ? request.label : 'Mobile service'}</h2>{request ? <><p>A technician wants to perform <strong>{OPERATIONS[request.operation] || request.operation}</strong> for your character. The configured fee or resale payout applies.</p><div className="hs-actions"><button className="hs-button" autoFocus disabled={busy} onClick={() => void decline()}>Decline</button><button className="hs-button hs-primary" disabled={busy} onClick={() => void accept()}>Accept service</button></div></> : <><p>{result?.message}</p>{result?.recoveryCode && <><p>Save these details now. Your old recovery code no longer works.</p><label>Cloud account<code tabIndex={0}>{result.accountId}</code></label><label>Recovery code<code tabIndex={0}>{result.recoveryCode}</code></label></>}<button className="hs-button hs-primary" onClick={() => { patch({ serviceResult: undefined }); finish(); }}>Done</button></>}</div></div>}
    {serviceOpen && <div className="phone-service-overlay" role="dialog" aria-modal="true" aria-label="Mobile shop services"><header><span>MOBILE SERVICES</span><button className="icon-button" onClick={actions.close} aria-label="Close mobile services"><X size={20} /></button></header><main><HandsetPanel onReload={() => undefined} /></main></div>}
  </>;
}
