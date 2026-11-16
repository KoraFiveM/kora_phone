import { recall } from '../lastScreen';
import type { DeviceData } from '../types';
import { defaultData } from './adapters/bootstrap';

/** The one phone the UI is showing: its cached data and the handset id writes are bound to. */
export const device: { cache: DeviceData; activeId: string | undefined; customApps: Record<string, boolean> } = {
    cache: defaultData(),
    activeId: undefined,
    // Custom add-on apps keep their install preferences in NUI storage.
    customApps: (() => {
        try {
            const value: unknown = JSON.parse(recall('customApps') ?? 'null');
            return value && typeof value === 'object' ? value as Record<string, boolean> : {};
        } catch { return {}; }
    })(),
};
