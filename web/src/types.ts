import type { Theme } from './themes';
import { installedApps } from './catalog';
export type AppId = 'custom' | 'store' | 'home' | 'phone' | 'contacts' | 'messages' | 'banking' | 'camera' | 'gallery' | 'social' | 'classifieds' | 'gps' | 'services' | 'mail' | 'notes' | 'weather' | 'calculator' | 'property' | 'vehicles' | 'flash' | 'music' | 'clock' | 'settings' | 'moderation';
export interface Settings { name: string; volume: number; scale: number; wallpaper: 'orbit' | 'plain' | 'midnight' | 'slate' | 'ember' | 'qbcore' | 'custom'; wallpaperUrl?: string; theme?: Theme; setupComplete?: boolean; phoneStyle?: 'classic' | 'flip'; phoneCase?: 'default' | 'nightdrive' | 'citypop' | 'sakura' | 'touge' | 'garage' | 'qbcore' | 'arcade' | 'space' | 'palms' | 'skyline' | 'custom'; phoneCaseUrl?: string; iconStyle?: 'circle' | 'squircle' | 'outline' | 'solid'; dnd?: boolean; dndFrom?: string; dndTo?: string; appOrder?: AppId[] }
export interface Contact { id?: number; name: string; number: string; photo?: string; favorite?: boolean }
export interface Note { id: string; title: string; body: string }
export interface Photo { id: string; url: string; created_at: number }
export interface Station { id: string; label: string; url: string }
export interface Alarm { id: string; label: string; time: string; days: number[]; enabled: boolean }
export interface DeviceData { contacts: Contact[]; notes: Note[]; photos: Photo[]; stations: Station[]; alarms: Alarm[]; settings: Settings; installedApps?: AppId[]; customApps?: Record<string, boolean> }
export interface Call { id: string; status: 'ringing' | 'active' | 'busy' | 'missed' | 'ended' | 'declined' | 'cancelled' | 'failed'; number: string; direction: 'incoming' | 'outgoing'; deviceId: string; volume?: number }
export interface WalletCard { name: string; citizenId: string; birthdate: string; gender: string; nationality: string; job: string; licences: { id: string; label: string; valid: boolean }[] }
export interface MailItem { id: number; peer: string; subject: string; body: string; created_at: string; unread: boolean }
export interface Location { label: string; x: number; y: number }
export interface Service { label: string; description: string; numbers: string[] }
export interface JobData { job: { name: string; label: string; grade: number; gradeLabel: string; onDuty: boolean }; actions: { id: string; label: string }[] }
export interface ModerationReport { id: number; targetType: 'profile' | 'post' | 'comment' | 'listing'; targetId: number; reason: string; details: string; status: string; createdAt: string; snapshot?: Record<string, unknown> }
export interface Bootstrap { characterName?: string; transfers?: boolean; moderator?: boolean; id: string; number: string; locked: boolean; hasPin: boolean; data?: DeviceData; preferences?: Settings; capabilities: Partial<Record<AppId, boolean>>; unavailable: Record<string, string>; locations: Location[]; services: Service[]; call?: Call; video: { iceServers: RTCIceServer[] } | false; flash: { maxSeconds: number; maxBytes?: number } | false; admin: boolean }
export type MediaKind = 'photo' | 'video';
export interface Message { id: number; sender: string; recipient: string; kind: 'sms' | 'mail'; subject: string; body: string; created_at: string }
export interface CallHistory { id: string; caller: string; recipient: string; status: string; created_at: string }
export interface Post { id: number; number: string; body: string; price: number; media_url?: string; media_kind?: MediaKind; created_at: string; likes: number; comments: number; liked: boolean | number; mine: boolean | number }
export interface Comment { id: number; number: string; body: string; created_at: string }
export interface Conversation { id: number; type?: 'direct' | 'group'; title?: string | null; peerPhoneNumber?: string | null; displayLabel?: string; lastMessageId?: number | null; lastMessagePreview?: string | null; lastMessageAt?: string | null; unreadCount?: number; sortId?: number; kind?: 'direct' | 'group'; name?: string | null; members?: string | null; last_body?: string; last_kind?: MediaKind | null; last_number?: string | null; last_at?: string | null }
export interface ChatMessage { id: number; conversationId?: number; messageType?: 'text'; body: string; mediaId?: number | null; isMine?: boolean; senderNumber?: string; createdAt?: string; sender_number: string; media_url?: string; media_kind?: MediaKind; shared_from_post?: number; created_at: string }
export interface Bank { balance: number; account: string; name: string; history: { id: string; citizenid: string; recipient: string; amount: number; status: string; created_at: string }[] }
export interface Property { name: string; label: string; coords?: { x: number; y: number } }
export interface Vehicle { vehicle: string; plate: string; garage: string; state: number; fuel: number }
export interface Weather { condition: string; hour: number; minute: number; rain: number }
export interface Notification { deviceId: string; title: string; body: string; app: AppId; at?: number; count?: number }
export type Api = {
  customApp: [{ app: string; installed?: boolean }, DeviceData];
  installApp: [{ app: AppId; installed: boolean }, DeviceData];
  unlock: [{ pin: string }, Bootstrap]; lock: [Record<string, never>, Bootstrap]; refresh: [Record<string, never>, Bootstrap];
  pin: [{ currentPin: string; pin: string }, { hasPin: boolean }];
  settings: [Settings, DeviceData]; contactSave: [Contact & { remove?: boolean }, DeviceData];
  messages: [{ kind: 'sms' | 'mail'; before?: number }, Message[]];
  sendMessage: [{ recipient: string; kind: 'sms' | 'mail'; subject: string; body: string }, { sent: boolean }];
  history: [Record<string, never>, CallHistory[]]; dial: [{ number: string }, Call];
  answer: [{ id: string }, Call]; hangup: [{ id: string; reject?: boolean }, boolean];
  notes: [Note & { remove?: boolean }, DeviceData];
  stations: [Station & { remove?: boolean }, DeviceData];
  alarms: [Alarm & { remove?: boolean }, DeviceData];
  feed: [{ kind: 'classifieds' | 'flash'; before?: number }, Post[]];
  post: [{ kind: 'classifieds' | 'flash'; body: string; price: number; mediaKind?: MediaKind; media?: string; mediaId?: number }, boolean];
  uploadMedia: [{ blob: Blob; onProgress?: (fraction: number) => void }, { id: number; url: string; kind: MediaKind }]; createProfile: [{ handle: string; displayName: string }, boolean];
  removePost: [{ id: number; kind?: 'classifieds' | 'flash' }, boolean]; reportListing: [{ id: number; reason: string; details: string }, boolean]; moderationQueue: [{ status?: 'open' | 'reviewing' }, ModerationReport[]]; moderationResolve: [{ reportId: number; action: 'dismiss' | 'remove_content' | 'suspend_profile'; note: string }, boolean]; markSold: [{ id: number }, boolean]; contactSeller: [{ id: number; message: string }, boolean]; like: [{ id: number; liked: boolean }, boolean];
  comments: [{ id: number }, Comment[]]; comment: [{ id: number; body: string }, boolean]; removeComment: [{ id: number }, boolean];
  conversations: [{ before?: number; cursorId?: number }, Conversation[]]; startChat: [{ number: string }, Conversation];
  createGroup: [{ name: string; numbers: string[] }, { id: number }];
  conversation: [{ id: number; before?: number }, ChatMessage[]];
  sendChatMessage: [{ conversationId: number; body: string; mediaKind?: MediaKind; media?: string; mediaId?: number }, ChatMessage];
  markConversationRead: [{ id: number; messageId?: number }, boolean];
  deleteChatMessage: [{ messageId: number }, boolean];
  shareToChat: [{ conversationId: number; postId: number; body?: string; mediaUrl?: string; mediaKind?: MediaKind }, boolean];
  leaveGroup: [{ id: number }, boolean]; addMember: [{ id: number; number: string }, boolean];
  bank: [Record<string, never>, Bank]; transfer: [{ recipient: string; amount: number }, { status: string }];
  property: [Record<string, never>, Property[]]; vehicles: [Record<string, never>, Vehicle[]]; services: [Record<string, never>, Service[]];
  job: [Record<string, never>, JobData]; setDuty: [{ onDuty: boolean }, JobData]; jobAction: [{ action: string }, { completed: boolean }];
  capture: [Record<string, never>, DeviceData]; deletePhoto: [{ id: string }, DeviceData];
  blocked: [Record<string, never>, string[]]; setBlocked: [{ number: string; blocked: boolean }, boolean];
  mailList: [{ box: 'inbox' | 'sent'; before?: number }, MailItem[]]; mailSend: [{ to: string; subject: string; body: string }, boolean]; mailRead: [{ id: number }, boolean]; mailDelete: [{ id: number }, boolean];
  wallet: [Record<string, never>, WalletCard]; showWallet: [Record<string, never>, { shown: boolean }]; myLocation: [Record<string, never>, { x: number; y: number; label: string; heading?: number; waypoint?: { x: number; y: number } }];
  waypoint: [{ x: number; y: number }, boolean]; weather: [Record<string, never>, Weather];
  videoSignal: [{ id: string; kind: 'offer' | 'answer' | 'ice'; sdp?: RTCSessionDescriptionInit; candidate?: RTCIceCandidateInit }, boolean];
};
export type Response<T> = { ok: true; data: T } | { ok: false; error: string };
export function asList<T>(value: T[] | null | undefined): T[];
export function asList<T = unknown>(value: unknown): T[];
export function asList<T>(value: unknown): T[] { return Array.isArray(value) ? value : []; }
export function normalizeData(value?: DeviceData): DeviceData {
  // Stored settings may predate the Flip color theme's removal.
  type Stored = Omit<Settings, 'theme'> & { theme?: Theme | 'flip' };
  const settings: Stored = { name: 'Nothing Phone', volume: 0.5, scale: 1, wallpaper: 'qbcore', ...value?.settings };
  // The Flip color theme is retired: legacy devices map to a real theme, keeping the flip style.
  if (settings.theme === 'flip') { settings.theme = 'dark'; settings.phoneStyle ??= 'flip'; }
  return { customApps: value?.customApps || {}, contacts: asList(value?.contacts), notes: asList(value?.notes), photos: asList(value?.photos), stations: asList(value?.stations), alarms: asList(value?.alarms), installedApps: installedApps(value?.installedApps), settings: settings as Settings };
}
