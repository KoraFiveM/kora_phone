import { useRef, useState } from 'react';
import type { Notification } from '../types';
import { NotificationIcon } from './AppIcon';

/** The banner that drops from the top of the screen; swipe up to dismiss, tap to open. */
export function HeadsUp({ alert, locked, onOpen, onDismiss }: { alert: Notification; locked: boolean; onOpen: () => void; onDismiss: () => void }) {
  const drag = useRef<{ y: number; scale: number; moved: boolean } | null>(null);
  const [dy, setDy] = useState(0);
  return <button className="heads-up" style={dy ? { transform: `translateY(${dy}px)`, opacity: 1 + dy / 90 } : undefined}
    onPointerDown={e => { drag.current = { y: e.clientY, scale: e.currentTarget.getBoundingClientRect().height / e.currentTarget.offsetHeight || 1, moved: false }; e.currentTarget.setPointerCapture(e.pointerId); }}
    onPointerMove={e => { const d = drag.current; if (!d) return; const next = Math.min(0, (e.clientY - d.y) / d.scale); if (next < -6) d.moved = true; setDy(next); }}
    onPointerUp={() => { if (dy < -24) onDismiss(); else setDy(0); }}
    onPointerCancel={() => { drag.current = null; setDy(0); }}
    onClick={() => { const swiped = drag.current?.moved; drag.current = null; if (!swiped) onOpen(); }}>
    <span className="heads-up-icon"><NotificationIcon id={alert.app} size={16} /></span>
    <span className="heads-up-text"><strong>{alert.title}</strong><small>{locked ? 'Unlock to view.' : alert.body}</small></span>
  </button>;
}
