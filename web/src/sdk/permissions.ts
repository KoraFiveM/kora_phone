import { PERMISSIONS, isRecord } from './protocol';
import type { Permission, RequestType } from './protocol';

/** Permission each request type needs. Types missing here need none. The server re-checks every one. */
export const REQUIRED_PERMISSION: Partial<Record<RequestType, Permission>> = {
    notify: 'notify',
    'storage.get': 'storage',
    'storage.set': 'storage',
    'storage.remove': 'storage',
    'contacts.list': 'contacts.read',
    'contacts.save': 'contacts.write',
};

export const isPermission = (value: unknown): value is Permission =>
    typeof value === 'string' && (PERMISSIONS as readonly string[]).includes(value);

/** Keep only known permissions, deduplicated. */
export function normalizePermissions(value: unknown): Permission[] {
    if (!Array.isArray(value)) return [];
    return [...new Set(value.filter(isPermission))];
}

export function isAllowed(granted: readonly Permission[], type: RequestType): boolean {
    const needed = REQUIRED_PERMISSION[type];
    return needed === undefined || granted.includes(needed);
}

/** Pull the permission list out of whatever shape the registry delivered (manifest app or legacy entry). */
export function permissionsOf(app: unknown): Permission[] {
    return isRecord(app) ? normalizePermissions(app.permissions) : [];
}
