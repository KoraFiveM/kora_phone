import type { Theme } from './themes';
import { installedApps } from './catalog';
export type AppId = `app:${string}` | 'custom' | 'store' | 'home' | 'camera' | 'social' | 'gps' | 'flash' | 'music' | 'clock' | 'settings';
/** Where navigate() may go: a built-in app, or the id of a folder app (which opens through the app host). */
export type AppTarget = AppId | (string & {});
export interface Settings { name: string; volume: number; scale: number; wallpaper: 'orbit' | 'plain' | 'midnight' | 'slate' | 'ember' | 'kora_core' | 'custom'; wallpaperUrl?: string; theme?: Theme; setupComplete?: boolean; phoneStyle?: 'classic' | 'standard' | 'flip' | 'fold'; phoneCase?: 'default' | 'nightdrive' | 'citypop' | 'sakura' | 'touge' | 'garage' | 'kora_core' | 'arcade' | 'space' | 'palms' | 'skyline' | 'custom'; phoneCaseUrl?: string; iconStyle?: 'circle' | 'squircle' | 'outline' | 'solid'; dnd?: boolean; dndFrom?: string; dndTo?: string; installedApps?: AppId[]; appOrder?: AppId[]; dockOrder?: AppId[] }
export interface MapBlip { id: number; x: number; y: number; sprite: number; label: string; street?: string; zone?: string; colour: string }
export interface Contact { id?: number; name: string; number: string; photo?: string; favorite?: boolean }
export interface Photo { id: string; url: string; created_at: number; kind?: MediaKind }
export interface Station { id: string; label: string; url: string }
export interface Alarm { id: string; label: string; time: string; days: number[]; enabled: boolean }
export interface DeviceData { contacts: Contact[]; photos: Photo[]; stations: Station[]; alarms: Alarm[]; settings: Settings; installedApps?: AppId[]; customApps?: Record<string, boolean> }
export interface Call { id: string; status: 'ringing' | 'active' | 'busy' | 'missed' | 'ended' | 'declined' | 'cancelled' | 'failed'; number: string; direction: 'incoming' | 'outgoing'; deviceId: string; volume?: number }
/** A server-registered SDK app as `apps:list` returns it. */
export interface SdkApp {
  id: string; name: string; description: string; icon?: string; entry: string; version?: string; resource: string; url?: string;
  permissions: string[]; job?: unknown; defaultInstalled?: boolean; price?: number; installed: boolean;
}
export interface MailItem { hasAction?: boolean; id: number; peer: string; subject: string; body: string; created_at: string; unread: boolean }
export interface Location { label: string; x: number; y: number }
export interface Service { label: string; description: string; numbers: string[] }
export interface Bootstrap { homeReorder?: boolean; galleryViewer?: boolean; model?: 'standard' | 'flip' | 'fold'; characterName?: string; transfers?: boolean; moderator?: boolean; id: string; number: string; locked: boolean; hasPin: boolean; data?: DeviceData; preferences?: Settings; capabilities: Partial<Record<string, boolean>>; unavailable: Record<string, string>; locations: Location[]; services: Service[]; call?: Call; video: { iceServers: RTCIceServer[] } | false; flash: { maxSeconds: number; maxBytes?: number } | false; admin: boolean }
export type MediaKind = 'photo' | 'video';
export interface Message { id: number; sender: string; recipient: string; kind: 'sms' | 'mail'; subject: string; body: string; created_at: string }
export interface Post { id: number; number: string; body: string; price: number; media_url?: string; media_kind?: MediaKind; created_at: string; likes: number; comments: number; liked: boolean | number; mine: boolean | number }
export interface Comment { id: number; number: string; body: string; created_at: string }
export interface Conversation { id: number; type?: 'direct' | 'group'; title?: string | null; peerPhoneNumber?: string | null; displayLabel?: string; lastMessageId?: number | null; lastMessagePreview?: string | null; lastMessageAt?: string | null; unreadCount?: number; sortId?: number; kind?: 'direct' | 'group'; name?: string | null; members?: string | null; last_body?: string; last_kind?: MediaKind | null; last_number?: string | null; last_at?: string | null }
export interface ChatMessage { id: number; conversationId?: number; messageType?: 'text'; body: string; mediaId?: number | null; isMine?: boolean; senderNumber?: string; createdAt?: string; sender_number: string; media_url?: string; media_kind?: MediaKind; shared_from_post?: number; created_at: string }
export interface Weather { condition: string; hour: number; minute: number; rain: number }
export interface Notification { deviceId: string; title: string; body: string; app: AppId; at?: number; count?: number }
export type Api = {
  appsList: [Record<string, never>, SdkApp[]]; appsInstall: [{ id: string }, { id: string; installed: boolean }]; appsUninstall: [{ id: string }, { id: string; installed: boolean }];
  customApp: [{ app: string; installed?: boolean }, DeviceData];
  installApp: [{ app: AppId; installed: boolean; expectedDeviceId?: string }, DeviceData];
  unlock: [{ pin: string }, Bootstrap]; lock: [Record<string, never>, Bootstrap]; refresh: [Record<string, never>, Bootstrap];
  pin: [{ currentPin: string; pin: string }, { hasPin: boolean }];
  settings: [Settings & { expectedDeviceId?: string }, DeviceData]; contactSave: [Contact & { remove?: boolean }, DeviceData];
  dial: [{ number: string }, Call];
  answer: [{ id: string }, Call]; hangup: [{ id: string; reject?: boolean }, boolean];
  stations: [Station & { remove?: boolean }, DeviceData];
  alarms: [Alarm & { remove?: boolean }, DeviceData];
  feed: [{ kind?: 'flash'; before?: number }, Post[]];
  post: [{ kind?: 'flash'; body: string; price?: number; mediaKind?: MediaKind; media?: string; mediaId?: number }, boolean];
  uploadMedia: [{ blob: Blob; onProgress?: (fraction: number) => void }, { id: number; url: string; kind: MediaKind }]; createProfile: [{ handle: string; displayName: string }, boolean];
  removePost: [{ id: number; kind?: 'flash' }, boolean]; like: [{ id: number; liked: boolean }, boolean];
  comments: [{ id: number }, Comment[]]; comment: [{ id: number; body: string }, boolean]; removeComment: [{ id: number }, boolean];
  conversations: [{ before?: number; cursorId?: number }, Conversation[]]; startChat: [{ number: string }, Conversation];
  createGroup: [{ name: string; numbers: string[] }, { id: number }];
  conversation: [{ id: number; before?: number }, ChatMessage[]];
  sendChatMessage: [{ conversationId: number; body: string; mediaKind?: MediaKind; media?: string; mediaId?: number }, ChatMessage];
  markConversationRead: [{ id: number; messageId?: number }, boolean];
  shareToChat: [{ conversationId: number; postId: number; body?: string; mediaUrl?: string; mediaKind?: MediaKind }, boolean];
  leaveGroup: [{ id: number }, boolean]; addMember: [{ id: number; number: string }, boolean];
  capture: [{ front?: boolean }, DeviceData];
  blocked: [Record<string, never>, string[]]; setBlocked: [{ number: string; blocked: boolean }, boolean];
  mailList: [{ box: 'inbox' | 'sent'; before?: number }, MailItem[]]; mailSend: [{ to: string; subject: string; body: string }, boolean]; mailRead: [{ id: number }, boolean]; mailDelete: [{ id: number }, boolean];
  myLocation: [Record<string, never>, { x: number; y: number; label: string; heading?: number; waypoint?: { x: number; y: number } }];
  mapBlips: [Record<string, never>, MapBlip[]];
  waypoint: [{ x: number; y: number }, boolean]; weather: [Record<string, never>, Weather];
  videoSignal: [{ id: string; epoch?: string; kind: 'offer' | 'answer' | 'ice'; sdp?: RTCSessionDescriptionInit; candidate?: RTCIceCandidateInit }, boolean];
};
export type Response<T> = { ok: true; data: T } | { ok: false; error: string };
export function asList<T>(value: T[] | null | undefined): T[];
export function asList<T = unknown>(value: unknown): T[];
export function asList<T>(value: unknown): T[] { return Array.isArray(value) ? value : []; }
export function normalizeData(value?: DeviceData): DeviceData {
  // Stored settings may predate the Flip color theme's removal.
  type Stored = Omit<Settings, 'theme'> & { theme?: Theme | 'flip' };
  const settings: Stored = { name: 'Kora Phone', volume: 0.5, scale: 1, wallpaper: 'kora_core', ...value?.settings };
  // The old default id "qbcore" was renamed "kora_core"; saved handsets may still carry it.
  const legacy = settings as { wallpaper: string; theme?: string; phoneCase?: string };
  if (legacy.wallpaper === 'qbcore') legacy.wallpaper = 'kora_core';
  if (legacy.theme === 'qbcore') legacy.theme = 'kora_core';
  if (legacy.phoneCase === 'qbcore') legacy.phoneCase = 'kora_core';
  // The Flip color theme is retired: legacy devices map to a real theme, keeping the flip style.
  if (settings.theme === 'flip') { settings.theme = 'dark'; settings.phoneStyle ??= 'flip'; }
  return { customApps: value?.customApps || {}, contacts: asList(value?.contacts), photos: asList(value?.photos), stations: asList(value?.stations), alarms: asList(value?.alarms), installedApps: installedApps(value?.installedApps), settings: settings as Settings };
}
