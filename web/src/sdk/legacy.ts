import { isRecord } from './protocol';

export interface LegacyEvent { name: string; data: unknown }

/** Legacy lb-phone style messages carry `{ action, data }`; map them onto protocol events. */
export function legacyEvent(data: unknown): LegacyEvent | null {
    if (!isRecord(data) || typeof data.action !== 'string') return null;
    return { name: data.action, data: data.data };
}

/** Event name used to hand device settings to legacy apps through compat.js. */
export const SETTINGS_EVENT = 'kora:settings';
