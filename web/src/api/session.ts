import type { Bootstrap, DeviceData } from '../types';
import { mapBootstrap } from './adapters/bootstrap';
import { mapPhoto } from './adapters/media';
import type { Page, RawBootstrap, RawMedia } from './raw';
import { device } from './state';
import { server } from './transport';

/**
 * Bootstrap payload -> shell model; also points the device cache at that phone.
 * A different phone starts from a clean cache. A re-bootstrap of the SAME phone keeps what the
 * server omitted (gallery, collections, previously saved settings) so a refresh never wipes them.
 */
export function adaptBootstrap(raw: RawBootstrap): Bootstrap {
    const previous = device.activeId !== undefined && device.activeId === String(raw.device?.id || 'kora_phone')
        ? device.cache : undefined;
    const { bootstrap, cache: mapped } = mapBootstrap(raw, device.customApps);
    let cache = mapped;
    if (previous) {
        const unlocked = !bootstrap.locked;
        cache = {
            ...mapped,
            settings: { ...previous.settings, ...(raw.device?.settings || {}) } as DeviceData['settings'],
            ...(unlocked ? {
                photos: previous.photos,
                contacts: Array.isArray(raw.contacts) ? mapped.contacts : previous.contacts,
                stations: raw.items?.stations ? mapped.stations : previous.stations,
            } : {}),
        };
        bootstrap.preferences = cache.settings;
        if (unlocked) bootstrap.data = cache;
    }
    device.activeId = bootstrap.id;
    device.cache = cache;
    return bootstrap;
}

export async function loadGallery(): Promise<void> {
    device.cache = { ...device.cache, photos: (await server<Page<RawMedia>>('gallery:list', { limit: 100 })).items?.map(mapPhoto) ?? [] };
}

export async function reload(): Promise<Bootstrap> {
    const value = adaptBootstrap(await server<RawBootstrap>('bootstrap'));
    if (!value.locked) {
        try {
            await loadGallery();
            value.data = device.cache;
        } catch { /* the gallery is optional: the rest of the phone still opens */ }
    }
    return value;
}
