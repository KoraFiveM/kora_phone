import { useEffect, useSyncExternalStore } from 'react';
import { api, isPreview, nui } from '../api';
import { isHostMessage } from '../nuiEvents';
import type { SdkApp as ServerApp } from '../types';

/**
 * Every app that is not built into the host, from both sources: apps registered with the server SDK (folder apps and
 * resources) and apps registered through the client exports (lb-phone style). The host sees one list.
 */
export interface SdkApp {
  permissions?: unknown;
  identifier: string;
  name: string;
  description: string;
  resource: string;
  /** Page the app shows: a path inside `resource`, or an https URL for client-registered apps. */
  ui: string;
  icon?: string;
  defaultApp?: boolean;
  price?: number;
  /** Where it was registered. Server apps keep their install state on the server. */
  source: 'server' | 'client';
  installed?: boolean;
  category?: string;
  system?: boolean;
}

let current: readonly SdkApp[] = [];
let loaded = false;
const listeners = new Set<() => void>();

export const getSdkApps = (): readonly SdkApp[] => current;
export const sdkApp = (id: string): SdkApp | undefined => current.find(item => item.identifier === id);
export function setSdkApps(next: readonly SdkApp[]): void {
  current = next;
  loaded = true;
  listeners.forEach(listener => listener());
}
const subscribe = (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; };
export const useSdkApps = (): readonly SdkApp[] => useSyncExternalStore(subscribe, getSdkApps);
export const useSdkAppsLoaded = (): boolean => useSyncExternalStore(subscribe, () => loaded);

const fromServer = (app: ServerApp): SdkApp => ({
  identifier: app.id, name: app.name, description: app.description, resource: app.resource, ui: app.entry,
  icon: app.icon, defaultApp: app.defaultInstalled, price: app.price, permissions: app.permissions,
  source: 'server', installed: app.installed, category: (app as { category?: string }).category, system: (app as { system?: boolean }).system,
});

type ClientApp = Omit<SdkApp, 'source'>;

/** Reads both registries and publishes the merged list. Safe to call whenever something may have changed. */
export async function refreshSdkApps(): Promise<void> {
  if (isPreview) { setSdkApps([]); return; }
  const [server, client] = await Promise.all([
    api('appsList', {}).catch(() => [] as ServerApp[]),
    nui<ClientApp[]>('customList').catch(() => [] as ClientApp[]),
  ]);
  const serverApps = Array.isArray(server) ? server.map(fromServer) : [];
  const taken = new Set(serverApps.map(app => app.identifier));
  const clientApps = (Array.isArray(client) ? client : []).filter(app => !taken.has(app.identifier)).map(app => ({ ...app, source: 'client' as const }));
  setSdkApps([...serverApps, ...clientApps]);
}

/** Keeps the shared list current while the component is mounted: loads it, then reloads when a resource (un)registers an app. */
export function useRuntimeApps(): { apps: readonly SdkApp[]; loaded: boolean } {
  useEffect(() => {
    void refreshSdkApps();
    const handler = (e: MessageEvent) => { if (isHostMessage(e.source, window, window.parent) && e.data?.type === 'customRegistry') void refreshSdkApps(); };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, []);
  return { apps: useSdkApps(), loaded: useSdkAppsLoaded() };
}

/** Whether the app is on this phone. Server apps ask the server; client apps use the locally stored choice. */
export const isSdkInstalled = (app: SdkApp, local?: Record<string, boolean>): boolean =>
  app.source === 'server' ? app.installed === true : local?.[app.identifier] ?? app.defaultApp === true;

/** Home-screen id of an app that is not built in. */
export const SDK_PREFIX = 'app:';
export const sdkHomeId = (app: SdkApp): `app:${string}` => `${SDK_PREFIX}${app.identifier}`;
export const sdkIdOf = (homeId: string): string | undefined => homeId.startsWith(SDK_PREFIX) ? homeId.slice(SDK_PREFIX.length) : undefined;
