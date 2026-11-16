import type { SdkApp } from '../../types';
import type { RawSdkApp } from '../raw';
import { isFlag } from '../raw';

/** `apps:list` entry -> typed SDK app. Entries without an id are dropped by the caller. */
export const mapSdkApp = (x: RawSdkApp): SdkApp => ({
    id: String(x.id),
    name: String(x.name ?? x.id),
    description: String(x.description ?? ''),
    icon: x.icon,
    entry: String(x.entry ?? ''),
    version: x.version,
    resource: String(x.resource ?? ''),
    url: x.url,
    permissions: Array.isArray(x.permissions) ? x.permissions.filter((p): p is string => typeof p === 'string') : [],
    job: x.job,
    defaultInstalled: isFlag(x.defaultInstalled),
    price: x.price,
    installed: isFlag(x.installed),
});
