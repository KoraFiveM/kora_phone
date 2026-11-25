import { starterApps } from '../../catalog';
import type { AppId, Bootstrap, DeviceData } from '../../types';
import { normalizeData } from '../../types';
import type { RawBootstrap } from '../raw';
import { mapContact } from './media';

export const defaultData = (): DeviceData => normalizeData({
    settings: { name: 'Kora Phone', volume: .5, scale: 1, wallpaper: 'kora_core', theme: 'kora_core', setupComplete: false },
    contacts: [], photos: [], stations: [], alarms: [],
});

/** What a bootstrap adds to the device cache, and what the shell gets back. */
export interface BootstrapResult { bootstrap: Bootstrap; cache: DeviceData }

type Collection<K extends 'alarms' | 'stations'> = DeviceData[K];

/** Server bootstrap -> shell model. Pure: the caller decides where the cache lives. */
export function mapBootstrap(raw: RawBootstrap, customApps: Record<string, boolean>): BootstrapResult {
    const id = String(raw.device?.id || 'kora_phone');
    const blank = defaultData();
    const apps = raw.apps && typeof raw.apps === 'object' ? raw.apps : {};
    const features = raw.features;
    const settings = raw.device?.settings;
    let cache = normalizeData({
        ...blank,
        contacts: Array.isArray(raw.contacts) ? raw.contacts.map(mapContact) : blank.contacts,
        alarms: (raw.items?.alarms ?? blank.alarms) as Collection<'alarms'>,
        stations: (raw.items?.stations ?? blank.stations) as Collection<'stations'>,
        settings: { ...blank.settings, ...(settings || {}) },
        installedApps: (settings?.installedApps ?? starterApps) as AppId[],
        customApps,
    });
    const locked = raw.security?.locked === true;
    if (locked) cache = { ...defaultData(), settings: cache.settings };
    const bootstrap: Bootstrap = {
        model: raw.device?.model || 'standard',
        homeReorder: features?.homeReorder !== false,
        galleryViewer: features?.galleryViewer !== false,
        id,
        number: String(raw.device?.phoneNumber || ''),
        locked,
        hasPin: raw.security?.hasPin === true,
        moderator: raw.moderator === true,
        transfers: features?.transfers === true,
        preferences: cache.settings,
        data: locked ? undefined : cache,
        admin: raw.admin === true,
        video: features?.video ? { iceServers: (Array.isArray(features.video.iceServers) ? features.video.iceServers : []) as RTCIceServer[] } : false,
        characterName: [raw.character?.firstName, raw.character?.lastName].filter(Boolean).join(' '),
        flash: features?.flash
            ? { maxSeconds: Number(features.flash.maxSeconds) || 15, maxBytes: Number(features.flash.maxBytes) || undefined }
            : false,
        capabilities: {
            store: raw.appStore !== false,
            camera: apps.camera !== false && features?.media === true,
            gallery: true,
            social: apps.social !== false,
            classifieds: apps.classifieds !== false,
            clock: apps.clock !== false,
            moderation: apps.moderation !== false && raw.moderator === true,
            gps: apps.gps !== false && features?.maps === true,
            weather: apps.weather !== false,
            flash: apps.flash !== false && !!features?.flash,
            music: apps.music !== false,
        },
        unavailable: { flash: 'Video uploads need a media host, which this server has not configured' },
        locations: (Array.isArray(raw.locations) ? raw.locations : []) as Bootstrap['locations'],
        services: [],
    };
    return { bootstrap, cache };
}
