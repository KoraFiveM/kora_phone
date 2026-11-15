import { useSyncExternalStore } from 'react';
import type { AppId } from './types';

type LocaleTable = Record<string, unknown>;
type Listener = () => void;

let Locales: LocaleTable = {};
const listeners = new Set<Listener>();

function subscribe(listener: Listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function snapshot() {
  return Locales;
}

export function setLocales(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return;
  Locales = value as LocaleTable;
  listeners.forEach(listener => listener());
}

export function useLocales() {
  return useSyncExternalStore(subscribe, snapshot, snapshot);
}

function getLocale(key: string) {
  let value: unknown = Locales;
  for (const part of key.split('.')) {
    if (!value || typeof value !== 'object') return key;
    value = (value as LocaleTable)[part];
  }
  return typeof value === 'string' ? value : key;
}

export const appCopy = (id: AppId) => {
  const key = `UI.Apps.${id}`;
  return {
    label: getLocale(`${key}.label`),
    subtitle: getLocale(`${key}.subtitle`),
  };
};
