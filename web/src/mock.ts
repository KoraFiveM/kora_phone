import { normalizeData } from './types';
import { isOptional, starterApps } from './catalog';
const blobToDataUrl = (blob: Blob): Promise<string> => new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(String(reader.result)); reader.onerror = () => reject(new Error('Could not read the recording.')); reader.readAsDataURL(blob); });
import type { AppId } from './types';
import type { Api, Bootstrap, Call, ChatMessage, Comment, Conversation, DeviceData, Message, Post } from './types';
const key = 'nothing-phone-preview-v1';
export const isDemo = new URLSearchParams(window.location?.search).has('demo');
const timestamp = () => new Date().toISOString();
const number = '5550102048';
const seed: DeviceData = {
  installedApps: starterApps,
  // Keep the first-run preview aligned with the default QBCore theme. The server-side
  // data normalizer also defaults to the QBCore wallpaper, so a new preview should not boot into
  // the Midnight wallpaper before the user has made a choice.
  settings: { name: 'Kora Phone', volume: 0.5, scale: 1, wallpaper: 'kora_core' },
  contacts: [{ name: 'Alex Morgan', number: '5550192042' }, { name: 'Jules Chen', number: '5550178031' }, { name: 'Los Santos Customs', number: '5550103000' }],
  photos: [],
  stations: [{ id: 'first-station', label: 'Lo-fi beats', url: 'https://www.youtube.com/watch?v=jfKfPfyJRdk' }],
};
const sampleFlashPhoto = () => `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800"><rect width="600" height="800" fill="#e8a15c"/><circle cx="300" cy="320" r="110" fill="#fff3e0"/><path d="M0 620 200 480 340 560 460 420 600 560V800H0" fill="#8a5a2b"/></svg>')}`;
interface Store { data: DeviceData; pin: string; messages: Message[]; posts: Post[]; flash: Post[]; comments: (Comment & { postId: number })[]; conversations: Conversation[]; chatMessages: Record<number, ChatMessage[]> }
function initial(): Store {
  return { data: structuredClone(seed), pin: '', messages: [
    { id: 1, sender: '5550192042', recipient: number, body: 'You around? Coffee at the usual spot.', kind: 'sms', subject: '', created_at: timestamp() },
    { id: 2, sender: number, recipient: '5550192042', body: 'On my way. Give me five.', kind: 'sms', subject: '', created_at: timestamp() },
    { id: 3, sender: '5550178031', recipient: number, body: 'Welcome to the city. Make yourself at home.', kind: 'mail', subject: 'Your next chapter', created_at: timestamp() },
  ], posts: [
    { id: 3, number: '5550178031', body: 'The city is a little quieter from up here. Take the long way home tonight.', price: 0, created_at: timestamp(), likes: 24, comments: 0, liked: false, mine: false },
    { id: 2, number: '5550192042', body: 'Fresh coffee. Good company. Now open on the corner of Alta Street. â˜•', price: 0, created_at: timestamp(), likes: 12, comments: 0, liked: false, mine: false },
  ], flash: [
    { id: 1, number: '5550178031', body: 'Golden hour on Alta Street.', price: 0, media_kind: 'photo', media_url: sampleFlashPhoto(), created_at: timestamp(), likes: 41, comments: 0, liked: false, mine: false },
  ], comments: [],
    conversations: [{ id: 1, kind: 'direct', name: null, members: '5550192042', last_body: 'On my way. Give me five.', last_kind: null, last_number: number, last_at: timestamp() }],
    chatMessages: { 1: [
      { id: 1, sender_number: '5550192042', body: 'You around? Coffee at the usual spot.', created_at: timestamp() },
      { id: 2, sender_number: number, body: 'On my way. Give me five.', created_at: timestamp() },
    ] } };
}
let store: Store;
try { store = isDemo ? initial() : JSON.parse(localStorage.getItem(key) || 'null') || initial(); store.data = normalizeData(store.data); } catch { store = initial(); }
if (isDemo) store.data.settings.setupComplete = true;
// Preserve existing phones when a preview saved before Flash/Pulse is opened.
store.flash = Array.isArray(store.flash) ? store.flash : initial().flash;
store.conversations = Array.isArray(store.conversations) ? store.conversations : initial().conversations;
store.chatMessages = store.chatMessages && typeof store.chatMessages === 'object' ? store.chatMessages : initial().chatMessages;
let activeCall: Call | undefined;
const completed = new Map<string, unknown>();
function save() { if (isDemo) return; localStorage.setItem(key, JSON.stringify(store)); }
export function previewBootstrap(): Bootstrap {
  return { id: 'preview-device', number, locked: !!store.pin, hasPin: !!store.pin, data: store.pin ? undefined : structuredClone(store.data), preferences: structuredClone(store.data.settings),
    transfers: true, capabilities: { camera: true, weather: true }, unavailable: {}, admin: true, moderator: true, video: { iceServers: [] },
    locations: [{ label: 'Legion Square', x: 195.2, y: -933.8 }, { label: 'Pillbox Medical', x: 298.5, y: -584.4 }, { label: 'Mission Row Police', x: 425.1, y: -979.5 }], services: [], call: activeCall,
    flash: { maxSeconds: 12 } };
}
export function previewIncoming() {
  activeCall = { id: crypto.randomUUID(), status: 'ringing', number: '5550178031', direction: 'incoming', deviceId: 'preview-device' };
  window.dispatchEvent(new MessageEvent('message', { data: { type: 'call', data: activeCall } }));
}
export function resetPreview() { if (!isDemo) localStorage.removeItem(key); location.reload(); }
export async function mockRequest<K extends keyof Api>(action: K, payload: Api[K][0], id: string): Promise<Api[K][1]> {
  await new Promise(resolve => setTimeout(resolve, 100));
  if (completed.has(id)) return structuredClone(completed.get(id)) as Api[K][1];
  // This is a local demo adapter; production authorization lives exclusively in Lua.
  const p = payload as Record<string, unknown>;
  let result: unknown = true;
  switch (action) {
    case 'installApp': {
      const app = p.app as AppId;
      if (!isOptional(app)) throw new Error('This app is part of the phone');
      const installed = new Set(store.data.installedApps || []);
      if (p.installed) installed.add(app); else installed.delete(app);
      store.data.installedApps = [...installed]; result = store.data; break;
    }
    case 'appsList': result = []; break;
    case 'appsInstall': case 'appsUninstall': throw new Error('This app is unavailable');
    case 'customApp': {
      const map = { ...(store.data.customApps || {}) };
      const identifier = String(p.app);
      if ('installed' in p) map[identifier] = p.installed === true;
      else if (!map[identifier]) throw new Error('This app is not installed');
      store.data.customApps = map; result = store.data; break;
    }
    case 'unlock': if (store.pin && p.pin !== store.pin) throw new Error('Incorrect PIN'); result = { ...previewBootstrap(), locked: false, data: store.data }; break;
    case 'refresh': result = { ...previewBootstrap(), locked: false, data: store.data }; break;
    case 'lock': result = { ...previewBootstrap(), locked: true, data: undefined }; break;
    case 'pin': if (store.pin && p.currentPin !== store.pin) throw new Error('Incorrect current PIN'); store.pin = String(p.pin); result = { hasPin: !!store.pin }; break;
    case 'settings': store.data.settings = payload as DeviceData['settings']; result = store.data; break;
    case 'contactSave': {
      store.data.contacts = store.data.contacts.filter(c => c.number !== p.number);
      if (!p.remove) store.data.contacts.push({ name: String(p.name), number: String(p.number), photo: String(p.photo || ''), favorite: p.favorite === true });
      result = store.data; break;
    }
    case 'dial': {
      if (activeCall) throw new Error('Already in a call');
      activeCall = { id, number: String(p.number), direction: 'outgoing', status: 'ringing', deviceId: 'preview-device' }; result = activeCall;
      setTimeout(() => { if (activeCall?.id === id) { activeCall = { ...activeCall, status: 'active' }; window.dispatchEvent(new MessageEvent('message', { data: { type: 'call', data: activeCall } })); } }, 2500);
      break;
    }
    case 'answer': if (activeCall) { activeCall = { ...activeCall, status: 'active' }; result = activeCall; } break;
    case 'hangup': activeCall = undefined; break;
    case 'capture': {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800"><rect width="600" height="800" fill="#c7c4b8"/><circle cx="420" cy="230" r="85" fill="#ede8d8"/><path d="M0 650 180 400 300 530 440 350 600 600V800H0" fill="#434844"/><path d="M0 760 220 600 420 670 600 510V800H0" fill="#262c29"/></svg>';
      store.data.photos.push({ id, url: `data:image/svg+xml,${encodeURIComponent(svg)}`, created_at: Date.now() / 1000 }); result = store.data; break;
    }
    case 'weather': result = { condition: 'EXTRASUNNY', hour: 10, minute: 8, rain: 0 }; break;
    case 'waypoint': break;
    case 'videoSignal': break;
    case 'myLocation': result = { x: 195.2, y: -933.8, label: 'Legion Square, Downtown Vinewood', heading: 45 }; break;
    case 'uploadMedia': { const blob = p.blob as Blob; (p.onProgress as ((n: number) => void) | undefined)?.(1); result = { id: 0, url: await blobToDataUrl(blob), kind: blob.type.startsWith('video/') ? 'video' : 'photo' }; break; }
    case 'blocked': result = (store as { blocked?: string[] }).blocked ?? []; break;
    case 'setBlocked': { const list = new Set((store as { blocked?: string[] }).blocked ?? []); if (p.blocked) list.add(String(p.number)); else list.delete(String(p.number)); (store as { blocked?: string[] }).blocked = [...list]; break; }
    case 'mailList': result = store.messages.filter(m => m.kind === 'mail' && (p.box === 'sent' ? m.sender === number : m.recipient === number)).sort((a, b) => b.id - a.id).map(m => ({ id: m.id, peer: p.box === 'sent' ? m.recipient : m.sender, subject: m.subject, body: m.body, created_at: m.created_at, unread: p.box !== 'sent' && !(m as { read?: boolean }).read })); break;
    case 'mailSend': store.messages.push({ id: Date.now(), sender: number, recipient: String(p.to), body: String(p.body), kind: 'mail', subject: String(p.subject), created_at: timestamp() }); break;
    case 'mailRead': { const mail = store.messages.find(m => m.id === p.id) as { read?: boolean } | undefined; if (mail) mail.read = true; break; }
    case 'mailDelete': store.messages = store.messages.filter(m => m.id !== p.id); break;
  }
  save(); completed.set(id, structuredClone(result));
  return structuredClone(result) as Api[K][1];
}
