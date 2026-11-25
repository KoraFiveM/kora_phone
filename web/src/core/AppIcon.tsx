import { Bell } from 'lucide-react';
import type { PointerEvent as ReactPointerEvent } from 'react';
import { appCopy } from '../locales';
import type { AppId } from '../types';
import { SdkIcon } from '../apps/custom/CustomApps';
import { appDefinition } from './appRegistry';
import { sdkHomeId } from './runtimeApps';
import type { SdkApp } from './runtimeApps';

export function NotificationIcon({ id, size = 18 }: { id: AppId; size?: number }) {
  const Icon = appDefinition(id)?.icon ?? Bell;
  return <Icon size={size} strokeWidth={1.6} />;
}

interface AppIconProps {
  id: AppId; onClick: () => void; dock?: boolean; badge?: number; editing?: boolean; dragging?: boolean; over?: boolean;
  onPointerDown?: (e: ReactPointerEvent<HTMLButtonElement>) => void;
}

export function AppIcon({ id, onClick, dock = false, badge = 0, editing = false, dragging = false, over = false, onPointerDown }: AppIconProps) {
  const Icon = appDefinition(id)!.icon;
  const { label } = appCopy(id);
  return <button data-app-id={id} data-zone={dock ? 'dock' : 'grid'} draggable={false} onPointerDown={onPointerDown} onClick={onClick} className={`app-icon ${dock ? 'dock-icon' : ''} app-${id} ${editing ? 'jiggle' : ''} ${dragging ? 'dragging' : ''} ${over ? 'drop-target' : ''}`} aria-label={`Open ${label}`}><span><Icon size={25} strokeWidth={1.6} /></span>{badge > 0 && <b className="app-badge" aria-label={`${badge} new`}>{badge > 9 ? '9+' : badge}</b>}{!dock && <small>{label}</small>}{editing && <i className="edit-handle" aria-hidden="true" />}</button>;
}

interface SdkAppIconProps extends Omit<AppIconProps, 'id'> { app: SdkApp }

/** Home-screen icon of an app that is not built in. Same button and classes as AppIcon, so reordering treats it alike. */
export function SdkAppIcon({ app, onClick, dock = false, badge = 0, editing = false, dragging = false, over = false, onPointerDown }: SdkAppIconProps) {
  const id = sdkHomeId(app);
  return <button data-app-id={id} data-zone={dock ? 'dock' : 'grid'} draggable={false} onPointerDown={onPointerDown} onClick={onClick} className={`app-icon ${dock ? 'dock-icon' : ''} app-sdk ${editing ? 'jiggle' : ''} ${dragging ? 'dragging' : ''} ${over ? 'drop-target' : ''}`} aria-label={`Open ${app.name}`}><span><SdkIcon icon={app.icon} size={25} /></span>{badge > 0 && <b className="app-badge" aria-label={`${badge} new`}>{badge > 9 ? '9+' : badge}</b>}{!dock && <small>{app.name}</small>}{editing && <i className="edit-handle" aria-hidden="true" />}</button>;
}
