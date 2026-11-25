import { isRecord } from './protocol';

/**
 * The phone's own settings, PIN, blocked numbers and handset controls, for the system apps that live in this resource
 * (Settings). The router only gets these handlers for such an app, so a third-party or lb-phone app can never reach them.
 */
export interface SystemDeps {
    /** The settings object the phone shows now, plus identity facts the Settings screens need. */
    snapshot(): { settings: Record<string, unknown>; model?: string; hasPin: boolean; number?: string; characterName?: string; deviceId?: string };
    /** Saves a full settings object through the validated server route and returns the phone's refreshed copy. */
    saveSettings(next: Record<string, unknown>): Promise<Record<string, unknown>>;
    setPin(currentPin: string, pin: string): Promise<{ hasPin: boolean }>;
    listBlocked(): Promise<string[]>;
    setBlocked(number: string, blocked: boolean): Promise<boolean>;
    /** One `handset:action` (SIM, cloud, Face ID, Wi-Fi ...). The server checks the operation and who may run it. */
    handset(payload: Record<string, unknown>): Promise<unknown>;
}

/** Keys an app may change through settings.save. The server validates the values again. */
export const SETTING_KEYS: readonly string[] = [
    'name', 'volume', 'scale', 'wallpaper', 'wallpaperUrl', 'theme', 'phoneStyle', 'phoneCase', 'phoneCaseUrl', 'iconStyle',
    'dnd', 'dndFrom', 'dndTo', 'setupComplete', 'appOrder', 'dockOrder',
];

export class SystemError extends Error {
    constructor(public code: string, message: string) { super(message); }
}

const text = (value: unknown, max: number): string | undefined => typeof value === 'string' && value.length <= max ? value : undefined;

/** Runs one system action. Anything it does not know is refused. */
export async function runSystemAction(deps: SystemDeps, action: string, payload: Record<string, unknown>): Promise<unknown> {
    switch (action) {
        case 'settings.get':
            return deps.snapshot();
        case 'settings.save': {
            const patch = isRecord(payload.patch) ? payload.patch : undefined;
            if (!patch) throw new SystemError('INVALID_PAYLOAD', 'A settings patch is required');
            const unknown = Object.keys(patch).filter(key => !SETTING_KEYS.includes(key));
            if (unknown.length) throw new SystemError('INVALID_PAYLOAD', `Unknown setting: ${unknown[0]}`);
            return deps.saveSettings({ ...deps.snapshot().settings, ...patch });
        }
        case 'pin.set': {
            const pin = text(payload.pin, 16);
            const current = text(payload.currentPin ?? '', 16);
            if (pin === undefined || current === undefined) throw new SystemError('INVALID_PAYLOAD', 'A PIN is required');
            return deps.setPin(current, pin);
        }
        case 'blocks.list':
            return deps.listBlocked();
        case 'blocks.set': {
            const number = text(payload.number, 24);
            if (!number || typeof payload.blocked !== 'boolean') throw new SystemError('INVALID_PAYLOAD', 'A number and blocked flag are required');
            return deps.setBlocked(number, payload.blocked);
        }
        case 'handset': {
            const op = text(payload.op, 32);
            if (!op) throw new SystemError('INVALID_PAYLOAD', 'An operation is required');
            const { action: _action, ...rest } = payload;
            return deps.handset(rest);
        }
        default:
            throw new SystemError('INVALID_PAYLOAD', `Unknown system action ${action}`);
    }
}
