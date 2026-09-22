import type { AppId } from './types';
export const optionalApps = ['banking', 'social', 'classifieds', 'gps', 'services', 'notes', 'mail', 'weather', 'calculator', 'property', 'vehicles', 'flash', 'music', 'clock'] as const;
export type OptionalApp = typeof optionalApps[number];
export const starterApps: OptionalApp[] = ['banking', 'gps', 'notes'];
export const isOptional = (id: AppId): id is OptionalApp => (optionalApps as readonly string[]).includes(id);
export const installedApps = (value: unknown): OptionalApp[] => value === undefined ? [...starterApps] : Array.isArray(value) ? optionalApps.filter(id => value.includes(id)) : [];
