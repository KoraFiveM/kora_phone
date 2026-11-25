import { api } from '../../api';
import type { AppId, DeviceData } from '../../types';

interface LbHost {
  data: DeviceData;
  navigate: (app: AppId, target?: string) => void;
  run: (work: () => Promise<void>) => Promise<void>;
  setCall: (call: Awaited<ReturnType<typeof dialCall>>) => void;
}

const dialCall = (number: string) => api('dial', { number });

/** lb-phone app names the host can open, lower-cased. Anything else is an app registered through the SDK. */
const APP_NAMES: Record<string, AppId> = {
  phone: 'phone', messages: 'messages', contacts: 'contacts', camera: 'camera', photos: 'gallery', gallery: 'gallery',
  settings: 'settings', maps: 'gps', clock: 'clock', 'app store': 'store', appstore: 'store',
};

/** lb-phone names of apps that are folder apps here. */
const FOLDER_ALIASES: Record<string, string> = { wallet: 'banking' };

/** The actions an lb-phone page can ask of the phone through the injected shim. */
export async function lbAction(action: string, payload: Record<string, unknown>, host: LbHost): Promise<unknown> {
  switch (action) {
    case 'contacts':
      return host.data.contacts.map(contact => ({ firstname: contact.name, lastname: '', number: contact.number, avatar: contact.photo }));
    case 'gallery':
      return host.data.photos.map(photo => ({ id: photo.id, src: photo.url, isVideo: photo.kind === 'video', timestamp: photo.created_at }));
    case 'call': {
      const number = typeof payload.number === 'string' ? payload.number : '';
      if (!number) throw Object.assign(new Error('Calling a company is not supported'), { code: 'UNSUPPORTED' });
      await host.run(async () => { host.setCall(await dialCall(number)); });
      return true;
    }
    case 'openApp': {
      const name = typeof payload.app === 'string' ? payload.app : '';
      const key = name.toLowerCase();
      const builtIn = APP_NAMES[key];
      if (builtIn) host.navigate(builtIn); else if (name) host.navigate('custom', FOLDER_ALIASES[key] ?? name);
      return true;
    }
    default:
      throw Object.assign(new Error(`Unknown action ${action}`), { code: 'INVALID_PAYLOAD' });
  }
}
