import { isOptional } from '../../catalog';
import type { Alarm, DeviceData, Station } from '../../types';
import { normalizeData } from '../../types';
import type { HandlerSet } from '../routeTypes';
import { loadGallery, reload } from '../session';
import { device } from '../state';
import { mapSdkApp } from '../adapters/apps';
import type { Page, RawSdkApp } from '../raw';
import { nui, server } from '../transport';
import { remember } from '../../lastScreen';

type Item = Alarm | Station;
type Collection = 'alarms' | 'stations';
const itemKind: Record<Collection, string> = { alarms: 'alarm', stations: 'station' };

/** Notes, alarms and stations are one shape of action: save or remove an item, mirror it in the cache. */
const itemRoute = (collection: Collection) => async (payload: Item & { remove?: boolean }): Promise<DeviceData> => {
    const { remove, ...item } = payload;
    const kind = itemKind[collection];
    if (remove) await server('items:remove', { kind, id: payload.id });
    else await server('items:save', { kind, item });
    const rest = (device.cache[collection] as Item[]).filter(x => x.id !== payload.id);
    device.cache = { ...device.cache, [collection]: remove ? rest : [item, ...rest] };
    return device.cache;
};

export const deviceRoutes: HandlerSet<
    'refresh' | 'unlock' | 'lock' | 'pin' | 'settings' | 'installApp' | 'appsList' | 'appsInstall' | 'appsUninstall' | 'customApp' | 'contactSave'
    | 'alarms' | 'stations' | 'capture' | 'deletePhoto'
> = {
    refresh: () => reload(),
    unlock: async ({ pin }) => { await server('security:unlock', { pin }); return reload(); },
    lock: async () => { await server('security:lock', {}); return reload(); },
    pin: async ({ pin, currentPin }) => {
        if (pin === '') {
            await server('security:removePin', { currentPin });
            return { hasPin: false };
        }
        await server('security:setPin', { pin, currentPin });
        return { hasPin: true };
    },
    settings: async ({ expectedDeviceId, ...settings }) => {
        const saved = await server<DeviceData['settings']>('settings:save', {
            ...settings, installedApps: device.cache.installedApps, expectedDeviceId,
        });
        device.cache = normalizeData({ ...device.cache, settings: saved });
        return device.cache;
    },
    installApp: async p => {
        if (!isOptional(p.app)) throw new Error('This app is part of the phone');
        if (p.expectedDeviceId !== device.activeId) throw new Error('Handset changed before these settings were saved');
        const next = new Set(device.cache.installedApps);
        if (p.installed) next.add(p.app); else next.delete(p.app);
        const settings = await server<DeviceData['settings']>('settings:save', {
            ...device.cache.settings, installedApps: [...next], expectedDeviceId: p.expectedDeviceId,
        });
        device.cache = normalizeData({ ...device.cache, settings, installedApps: settings.installedApps });
        return device.cache;
    },
    appsList: async () => (await server<Page<RawSdkApp> & { apps?: RawSdkApp[] }>('apps:list', {})).apps?.filter(x => x?.id).map(mapSdkApp) ?? [],
    appsInstall: async ({ id }) => server<{ id: string; installed: boolean }>('apps:install', { id }),
    appsUninstall: async ({ id }) => server<{ id: string; installed: boolean }>('apps:uninstall', { id }),
    customApp: async p => {
        const sdkApps = await deviceRoutes.appsList({}, { id: '' }).catch(() => []);
        const sdk = sdkApps.find(item => item.id === p.app);
        const installed = { ...(device.cache.customApps || {}) };
        if (sdk) {
            // Server-registered apps keep their install state on the server.
            if ('installed' in p) {
                await (p.installed ? deviceRoutes.appsInstall : deviceRoutes.appsUninstall)({ id: p.app }, { id: '' });
                installed[p.app] = p.installed === true;
            } else if (!sdk.installed) throw new Error('This app is not installed');
            else installed[p.app] = true;
            device.cache = { ...device.cache, customApps: installed };
            return device.cache;
        }
        // Client-registered (legacy) apps: NUI storage only, no server permissions.
        const list = await nui<{ identifier: string; defaultApp?: boolean }[]>('customList');
        const app = Array.isArray(list) ? list.find(item => item.identifier === p.app) : undefined;
        if (!app) throw new Error('This app is unavailable');
        if ('installed' in p) installed[p.app] = p.installed === true;
        else if (!(installed[p.app] ?? app.defaultApp)) throw new Error('This app is not installed');
        device.customApps = installed;
        remember('customApps', JSON.stringify(installed));
        device.cache = { ...device.cache, customApps: installed };
        return device.cache;
    },
    contactSave: async p => {
        const current = p.id ? p : device.cache.contacts.find(c => c.number === p.number);
        if (p.remove) {
            await server('contacts:delete', { id: current?.id });
        } else {
            await server(current?.id ? 'contacts:update' : 'contacts:create', {
                id: current?.id,
                displayName: p.name,
                phoneNumber: p.number,
                isFavorite: p.favorite === true,
                avatarMediaId: Number(device.cache.photos.find(x => x.url === p.photo)?.id) || undefined,
            });
        }
        return (await reload()).data as DeviceData;
    },
    alarms: itemRoute('alarms'),
    stations: itemRoute('stations'),
    capture: async ({ front }) => {
        await server('camera:open', { front });
        // Let the UI finish hiding so the phone is not in the screenshot.
        await new Promise(resolve => setTimeout(resolve, 400));
        await server('camera:capture');
        await loadGallery();
        return device.cache;
    },
    deletePhoto: async ({ id }) => {
        await server('gallery:delete', { id: Number(id) });
        device.cache = { ...device.cache, photos: device.cache.photos.filter(x => x.id !== String(id)) };
        return device.cache;
    },
};
