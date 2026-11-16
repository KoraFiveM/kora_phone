import { useSyncExternalStore } from 'react';

/** A third-party app announced by the server (apps:list / customList). It plugs into the phone at runtime, no rebuild. */
export interface SdkApp {
  permissions?: unknown;
  identifier: string;
  name: string;
  description: string;
  resource: string;
  ui: string;
  icon?: string;
  defaultApp?: boolean;
  price?: number;
}

let current: readonly SdkApp[] = [];
const listeners = new Set<() => void>();

export const getSdkApps = (): readonly SdkApp[] => current;
export const sdkApp = (id: string): SdkApp | undefined => current.find(item => item.identifier === id);
export function setSdkApps(next: readonly SdkApp[]): void {
  current = next;
  listeners.forEach(listener => listener());
}
const subscribe = (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; };
export const useSdkApps = (): readonly SdkApp[] => useSyncExternalStore(subscribe, getSdkApps);
