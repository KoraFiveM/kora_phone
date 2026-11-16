import { BatteryFull, Moon, Signal, Wifi } from 'lucide-react';
import type { PointerEvent as ReactPointerEvent } from 'react';

interface DragHandlers {
  onPointerDown: (event: ReactPointerEvent<HTMLDivElement>) => void;
  onPointerMove: (event: ReactPointerEvent<HTMLDivElement>) => void;
  onPointerUp: () => void;
  onPointerCancel: () => void;
}

/** The status bar doubles as the handle for dragging the phone around the game screen. */
export function StatusBar({ time, quiet, drag }: { time: string; quiet: boolean; drag: DragHandlers }) {
  return <div className="status-bar" {...drag}><span className="status-time">{time}</span><div className="camera-dot" /><span className="status-icons">{quiet && <Moon size={12} aria-label="Do Not Disturb is on" />}<Signal size={13} /><Wifi size={14} /><BatteryFull size={17} /></span></div>;
}
