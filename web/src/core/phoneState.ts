import type { AppId, Bootstrap, Call, Conversation, DeviceData, Notification } from '../types';
import { normalizeData } from '../types';
import { recall } from '../lastScreen';
import type { ShareRequest } from './ShareRequest';

export interface ServiceRequest { id: string; label: string; operation: string }
export interface ServiceResult { message: string; accountId?: string; recoveryCode?: string }
export interface HomeState { page: number; editing: boolean; dragId: string | null; overId: string | null }
export interface VideoState { request: boolean; pending: boolean; on: boolean; remote: boolean; muted: boolean }
export interface Peek { title: string; body: string }

/** Everything the phone shell shows or reacts to. The reducer below is the only writer. */
export interface PhoneState {
  device?: Bootstrap;
  shown: boolean;
  app: AppId;
  target: string;
  call?: Call;
  toast: string;
  alert?: Notification;
  busy: boolean;
  revision: number;
  hiddenCapture: boolean;
  notifications: Notification[];
  earlier: Notification[];
  showNotifications: boolean;
  home: HomeState;
  folded: boolean;
  unfolding: boolean;
  serviceOpen: boolean;
  serviceRequest?: ServiceRequest;
  serviceResult?: ServiceResult;
  shareRequest?: ShareRequest;
  video: VideoState;
  coverCamera: boolean;
  coverPlaying: boolean;
  foldInbox: Conversation[];
  foldInboxMore: boolean;
  peek?: Peek;
  pin: string;
  lockError: string;
}

export type PhoneAction =
  | { type: 'patch'; patch: Partial<PhoneState> }
  | { type: 'home'; patch: Partial<HomeState> }
  | { type: 'video'; patch: Partial<VideoState> }
  | { type: 'apply'; value: Bootstrap; app: AppId }
  | { type: 'close'; source: 'ui' | 'host' }
  | { type: 'reset' }
  | { type: 'navigate'; app: AppId; target: string }
  | { type: 'device'; update: (device: Bootstrap) => Bootstrap }
  | { type: 'data'; value: DeviceData; deviceId?: string }
  | { type: 'notification'; notification: Notification; popup: boolean }
  | { type: 'markRead'; items: Notification[] }
  | { type: 'clearNotifications' }
  | { type: 'bump' }
  | { type: 'callEnded'; id?: string };

// Notifications survive closing the phone and reloading the UI: unread ones stay in the shade, read ones move to "Earlier".
export function storedNotifications(): { a: Notification[]; e: Notification[] } {
  try {
    const value = JSON.parse(recall('notifications') ?? 'null');
    return { a: Array.isArray(value?.a) ? value.a : [], e: Array.isArray(value?.e) ? value.e : [] };
  } catch { return { a: [], e: [] }; }
}

const idleHome: HomeState = { page: 0, editing: false, dragId: null, overId: null };
const idleVideo: VideoState = { request: false, pending: false, on: false, remote: false, muted: false };

export function initialPhoneState(device: Bootstrap | undefined, shown: boolean, app: AppId): PhoneState {
  const stored = storedNotifications();
  return {
    device, shown, app, target: '', toast: '', busy: false, revision: 0, hiddenCapture: false,
    notifications: stored.a, earlier: stored.e, showNotifications: false, home: idleHome, folded: false, unfolding: false,
    serviceOpen: false, video: idleVideo, coverCamera: false, coverPlaying: false, foldInbox: [], foldInboxMore: false,
    pin: '', lockError: '',
  };
}

const onlyDevice = (id: string) => (item: Notification) => item.deviceId === id;

export function mergeNotification(previous: Notification[], notification: Notification): Notification[] {
  const matching = previous.find(item => item.deviceId === notification.deviceId && item.app === notification.app && item.title === notification.title);
  return matching
    ? [{ ...notification, count: (matching.count ?? 1) + 1 }, ...previous.filter(item => item !== matching)]
    : [notification, ...previous].slice(0, 20);
}

export function phoneReducer(state: PhoneState, action: PhoneAction): PhoneState {
  switch (action.type) {
    case 'patch': return { ...state, ...action.patch };
    case 'home': return { ...state, home: { ...state.home, ...action.patch } };
    case 'video': return { ...state, video: { ...state.video, ...action.patch } };
    case 'bump': return { ...state, revision: state.revision + 1 };
    case 'device': return state.device ? { ...state, device: action.update(state.device) } : state;
    case 'data': {
      const device = state.device;
      if (!device || (action.deviceId !== undefined && device.id !== action.deviceId)) return state;
      return { ...state, device: { ...device, data: normalizeData(action.value) } };
    }
    case 'navigate':
      return { ...state, app: action.app, target: action.target, showNotifications: false, home: idleHome };
    case 'apply': {
      const mine = onlyDevice(action.value.id);
      return {
        ...state, folded: action.value.model === 'fold', device: action.value, shown: true, app: action.app,
        target: '', pin: '', lockError: '', notifications: state.notifications.filter(mine), earlier: state.earlier.filter(mine),
        toast: '', alert: undefined, call: action.value.call, hiddenCapture: false, showNotifications: false,
        home: { ...state.home, editing: false, dragId: null, overId: null },
      };
    }
    case 'close': {
      const closed: PhoneState = {
        ...state, coverCamera: false, coverPlaying: false, serviceOpen: false, serviceRequest: undefined, serviceResult: undefined,
        call: undefined, alert: undefined, shown: false, device: undefined, pin: '',
      };
      if (action.source === 'ui') return { ...closed, home: { ...state.home, editing: false, dragId: null, overId: null } };
      return { ...closed, shareRequest: undefined };
    }
    case 'reset': return { ...state, notifications: [], earlier: [] };
    case 'notification': {
      const notification = action.notification;
      return {
        ...state, notifications: mergeNotification(state.notifications, notification),
        alert: action.popup ? notification : state.alert, revision: state.revision + 1,
      };
    }
    case 'markRead':
      return {
        ...state,
        notifications: state.notifications.filter(n => !action.items.some(item => item === n || (item.app === n.app && item.title === n.title))),
        earlier: [...action.items, ...state.earlier].slice(0, 30),
      };
    case 'clearNotifications': return { ...state, notifications: [], earlier: [], alert: undefined };
    case 'callEnded':
      return state.call && state.call.id === action.id ? { ...state, call: { ...state.call, status: 'ended' } } : state;
  }
}
