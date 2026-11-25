import { lazy } from 'react';
import type { ComponentType, LazyExoticComponent } from 'react';
import {
  AlarmClock, Aperture, Blocks, Camera, MapPin,
  MessageCircle, Music, Phone, Radio, Settings as SettingsIcon, Store as StoreIcon,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { ClockScreen } from '../apps/clock/ClockScreen';
import { MessagesScreen } from '../apps/communication/Communication';
import { CustomAppRoute } from '../apps/custom/CustomApps';
import { GPSScreen } from '../apps/maps/GPSScreen';
import { MusicScreen } from '../apps/music/MusicScreen';
import { SettingsHost } from './SettingsHost';
import { appCopy } from '../locales';
import { optionalApps } from '../catalog';
import { recall } from '../lastScreen';
import type { AppId, Bootstrap } from '../types';

export interface ScreenProps { target: string }
export type AppComponent = ComponentType<ScreenProps> | LazyExoticComponent<ComponentType<ScreenProps>>;
export type StoreCategory = 'Life' | 'Social' | 'Tools';

export interface AppDefinition {
  id: Exclude<AppId, 'home'>;
  /** Label and tagline shown on the icon and the page header (see locales.ts). */
  copy: { label: string; subtitle: string };
  icon: LucideIcon;
  component: AppComponent;
  /** Optional apps are installed from the App Store; their listing lives here. */
  optional?: { category: StoreCategory; description: string };
  /** Where the app sits on the home screen. `system` apps are launched from elsewhere (dock defaults, Settings). */
  placement: 'grid' | 'dock' | 'system' | 'hidden';
  /** The app draws its own header and fills the screen. */
  fullBleed?: boolean;
  /** Extra capability gate on top of `device.capabilities[id] !== false`. */
  gate?: (device: Bootstrap) => boolean;
}

const screen = (load: () => Promise<ComponentType<ScreenProps>>) => lazy(async () => ({ default: await load() }));
// Heavy apps are split into their own chunks and loaded the first time they open.
// The App Store reads this registry for its listings, so it loads lazily to keep the module graph acyclic.
const StoreApp = screen(async () => (await import('../apps/store/Store')).StoreScreen);
const PulseApp = screen(async () => (await import('../apps/pulse/Pulse')).PulseScreen);
const FlashApp = screen(async () => (await import('../apps/flash/Flash')).FlashScreen);
const CameraApp = screen(async () => (await import('../apps/camera/CameraScreen')).CameraScreen);

const entry = (
  id: AppDefinition['id'], icon: LucideIcon, component: AppComponent,
  placement: AppDefinition['placement'], extra: Partial<Pick<AppDefinition, 'optional' | 'fullBleed' | 'gate'>> = {},
): AppDefinition => ({ id, icon, component, placement, copy: appCopy(id), ...extra });

/** One entry per built-in app. Adding an app is adding a line here (plus its server-side id). Order is the home-screen order. */
export const appRegistry: readonly AppDefinition[] = [
  entry('store', StoreIcon, StoreApp, 'grid'),
  entry('social', Radio, PulseApp, 'grid', { fullBleed: true, optional: { category: 'Social', description: 'Message your people, one-on-one or in a group.' } }),
  entry('gps', MapPin, GPSScreen, 'grid', { optional: { category: 'Tools', description: 'Familiar places. New directions. Your city, mapped.' } }),
  entry('flash', Aperture, FlashApp, 'grid', { fullBleed: true, optional: { category: 'Social', description: 'Short videos and photos from around the city, for everyone to see.' } }),
  entry('music', Music, MusicScreen, 'grid', { optional: { category: 'Tools', description: 'Save YouTube, SoundCloud, or stream links and play them from your phone.' } }),
  entry('clock', AlarmClock, ClockScreen, 'grid', { optional: { category: 'Tools', description: 'Set alarms that ring on your local clock, even with the phone closed.' } }),
  entry('messages', MessageCircle, MessagesScreen, 'dock'),
  entry('camera', Camera, CameraApp, 'dock'),
  entry('settings', SettingsIcon, SettingsHost, 'system'),
  // Third-party SDK apps (apps:list) are not entries: they all render through this host, with the SDK app id as the
// route target. Their runtime list lives in runtimeApps.ts and feeds the App Store and the host.
  entry('custom', Blocks, CustomAppRoute, 'hidden', { fullBleed: true }),
];

const byId = new Map<string, AppDefinition>(appRegistry.map(item => [item.id, item]));
export const appDefinition = (id: string): AppDefinition | undefined => byId.get(id);
/** Icon and copy for any app id, with a safe fallback for ids that are not registered. */
export const iconOf = (id: AppId): LucideIcon => byId.get(id)?.icon ?? Phone;

/** Optional apps, in registry order. Must stay in step with catalog.ts (and the server allow-list). */
export const optionalListings = appRegistry.filter((item): item is AppDefinition & { optional: NonNullable<AppDefinition['optional']> } => !!item.optional);
export const registeredOptionalIds = optionalListings.map(item => item.id);
export const catalogMatchesRegistry = (): boolean =>
  registeredOptionalIds.length === optionalApps.length && optionalApps.every(id => registeredOptionalIds.includes(id));

const isOptionalApp = (id: AppId): boolean => !!byId.get(id)?.optional;

/**
 * Whether an app can open on this handset: registered, not switched off by the server (`capabilities`),
 * passing its own gate, and installed when it is an optional app.
 */
export function canLaunch(id: string, device?: Bootstrap): boolean {
  if (id === 'home') return true;
  const definition = byId.get(id);
  if (!definition || id === 'custom' || definition.placement === 'hidden') return false;
  if (device?.capabilities[id] === false || (device && definition.gate && !definition.gate(device))) return false;
  return !isOptionalApp(id as AppId) || device?.data?.installedApps?.includes(id as AppId) === true;
}

/** The screen the phone reopens on: the last one used, if it still exists and may open. */
export function restoreApp(device?: Bootstrap): AppId {
  const id = recall('app') as AppId;
  return byId.has(id) && canLaunch(id, device) ? id : 'home';
}

export const homeGridIds = (device?: Bootstrap): AppId[] =>
  appRegistry.filter(item => item.placement === 'grid' && canLaunch(item.id, device)).map(item => item.id);

/** Default dock; the gallery stands in when the camera is unavailable. */
export const defaultDock = (device?: Bootstrap): string[] => ['phone', 'messages', 'contacts', canLaunch('camera', device) ? 'camera' : 'gallery'];
/** Every id that can sit in the default dock, so a folder app with one of these ids is shown there instead of in the grid. */
export const DOCK_IDS: readonly string[] = ['phone', 'messages', 'contacts', 'camera', 'gallery'];
