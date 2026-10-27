import { normalizeData } from './types';
import { isOptional, starterApps } from './catalog';
import { blobToDataUrl } from './useClipRecorder';
import type { AppId } from './types';
import type { Api, Bootstrap, Bank, Call, CallHistory, ChatMessage, Comment, Conversation, DeviceData, LegacyActivity, MailItem, Message, ModerationReport, Post } from './types';
const key = 'nothing-phone-preview-v1';
const timestamp = () => new Date().toISOString();
const number = '5550102048';
const seed: DeviceData = {
  installedApps: starterApps,
  // Keep the first-run preview aligned with the default QBCore theme. The server-side
  // data normalizer also defaults to the QBCore wallpaper, so a new preview should not boot into
  // the Midnight wallpaper before the user has made a choice.
  settings: { name: 'Nothing Phone', volume: 0.5, scale: 1, wallpaper: 'qbcore' },
  contacts: [{ name: 'Alex Morgan', number: '5550192042' }, { name: 'Jules Chen', number: '5550178031' }, { name: 'Los Santos Customs', number: '5550103000' }],
  notes: [{ id: 'first-note', title: 'A fresh start', body: 'Pick up the car. Meet Jules at the pier.\nFind a little room for something new.' }], photos: [],
  stations: [{ id: 'first-station', label: 'Lo-fi beats', url: 'https://www.youtube.com/watch?v=jfKfPfyJRdk' }],
  alarms: [{ id: 'first-alarm', label: 'Wake up', time: '08:00', days: [1, 2, 3, 4, 5], enabled: true }],
};
const sampleFlashPhoto = () => `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800"><rect width="600" height="800" fill="#e8a15c"/><circle cx="300" cy="320" r="110" fill="#fff3e0"/><path d="M0 620 200 480 340 560 460 420 600 560V800H0" fill="#8a5a2b"/></svg>')}`;
interface Store { legacyMail?: MailItem[]; legacyActivity?: LegacyActivity[]; data: DeviceData; pin: string; messages: Message[]; posts: Post[]; flash: Post[]; comments: (Comment & { postId: number })[]; bank: Bank; history: CallHistory[]; conversations: Conversation[]; chatMessages: Record<number, ChatMessage[]> }
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
  ], comments: [], bank: { balance: 24850, account: 'LS-1048', name: 'Charlie Parker', history: [] }, history: [],
    conversations: [{ id: 1, kind: 'direct', name: null, members: '5550192042', last_body: 'On my way. Give me five.', last_kind: null, last_number: number, last_at: timestamp() }],
    chatMessages: { 1: [
      { id: 1, sender_number: '5550192042', body: 'You around? Coffee at the usual spot.', created_at: timestamp() },
      { id: 2, sender_number: number, body: 'On my way. Give me five.', created_at: timestamp() },
    ] } };
}
let store: Store;
try { store = JSON.parse(localStorage.getItem(key) || 'null') || initial(); store.data = normalizeData(store.data); } catch { store = initial(); }
// Preserve existing phones when a preview saved before Flash/Pulse is opened.
store.flash = Array.isArray(store.flash) ? store.flash : initial().flash;
store.conversations = Array.isArray(store.conversations) ? store.conversations : initial().conversations;
store.chatMessages = store.chatMessages && typeof store.chatMessages === 'object' ? store.chatMessages : initial().chatMessages;
store.legacyMail ??= [{id:1,peer:'Job Office',subject:'Delivery offer',body:'Collect your delivery at the depot.\nAccept when you are ready.',hasAction:true,unread:true,created_at:timestamp()}];
store.legacyActivity ??= [{id:1,title:'Crypto activity',message:'A city service recorded a transaction note.',created_at:timestamp()}];
let activeCall: Call | undefined;
let classifieds: Post[] = [{ id: 99, number: '5550192042', body: 'Karin Sultan Â· Great condition, low miles. Ready for its next adventure.', price: 18000, created_at: timestamp(), likes: 0, comments: 0, liked: false, mine: false }];
let reports: (ModerationReport & { targetId: number })[] = [{ id: 1, targetType: 'listing', targetId: 99, reason: 'scam', details: 'The price seems too good to be true.', status: 'open', createdAt: timestamp(), snapshot: { title: 'Karin Sultan', description: 'Great condition, low miles. Ready for its next adventure.', price: 18000 } }];
const completed = new Map<string, unknown>();
function save() { localStorage.setItem(key, JSON.stringify(store)); }
export function previewBootstrap(): Bootstrap {
  return { id: 'preview-device', number, locked: !!store.pin, hasPin: !!store.pin, data: store.pin ? undefined : structuredClone(store.data), preferences: structuredClone(store.data.settings),
    transfers: true, capabilities: { banking: true, camera: true, property: true, vehicles: true, weather: true, moderation: true }, unavailable: {}, admin: true, moderator: true, video: { iceServers: [] },
    locations: [{ label: 'Legion Square', x: 195.2, y: -933.8 }, { label: 'Pillbox Medical', x: 298.5, y: -584.4 }, { label: 'Mission Row Police', x: 425.1, y: -979.5 }], services: [], call: activeCall,
    flash: { maxSeconds: 12 } };
}
export function previewIncoming() {
  activeCall = { id: crypto.randomUUID(), status: 'ringing', number: '5550178031', direction: 'incoming', deviceId: 'preview-device' };
  window.dispatchEvent(new MessageEvent('message', { data: { type: 'call', data: activeCall } }));
}
let demoDuty = true;
export function resetPreview() { localStorage.removeItem(key); location.reload(); }
export async function mockRequest<K extends keyof Api>(action: K, payload: Api[K][0], id: string): Promise<Api[K][1]> {
  await new Promise(resolve => setTimeout(resolve, 100));
  if (completed.has(id)) return structuredClone(completed.get(id)) as Api[K][1];
  // This is a local demo adapter; production authorization lives exclusively in Lua.
  const p = payload as Record<string, unknown>;
  let result: unknown = true;
  const feed = p.kind === 'classifieds' ? classifieds : p.kind === 'flash' ? store.flash : store.posts;
  switch (action) {
    case 'installApp': {
      const app = p.app as AppId;
      if (!isOptional(app)) throw new Error('This app is part of the phone');
      const installed = new Set(store.data.installedApps || []);
      if (p.installed) installed.add(app); else installed.delete(app);
      store.data.installedApps = [...installed]; result = store.data; break;
    }
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
    case 'messages': result = store.messages.filter(m => m.kind === p.kind && (!p.before || m.id < Number(p.before))).sort((a, b) => b.id - a.id).slice(0, 50); break;
    case 'sendMessage': store.messages.push({ id: Date.now(), sender: number, recipient: String(p.recipient), kind: p.kind as 'sms' | 'mail', subject: String(p.subject), body: String(p.body), created_at: timestamp() }); result = { sent: true }; break;
    case 'history': result = store.history; break;
    case 'dial': {
      if (activeCall) throw new Error('Already in a call');
      activeCall = { id, number: String(p.number), direction: 'outgoing', status: 'ringing', deviceId: 'preview-device' }; result = activeCall;
      store.history.unshift({ id, caller: number, recipient: String(p.number), status: 'ringing', created_at: timestamp() });
      setTimeout(() => { if (activeCall?.id === id) { activeCall = { ...activeCall, status: 'active' }; window.dispatchEvent(new MessageEvent('message', { data: { type: 'call', data: activeCall } })); } }, 2500);
      break;
    }
    case 'answer': if (activeCall) { activeCall = { ...activeCall, status: 'active' }; result = activeCall; } break;
    case 'hangup': activeCall = undefined; store.history = store.history.map(h => h.id === p.id ? { ...h, status: 'ended' } : h); break;
    case 'notes': store.data.notes = store.data.notes.filter(n => n.id !== p.id); if (!p.remove) store.data.notes.unshift({ id: String(p.id), title: String(p.title), body: String(p.body) }); result = store.data; break;
    case 'stations': store.data.stations = store.data.stations.filter(s => s.id !== p.id); if (!p.remove) store.data.stations.unshift({ id: String(p.id), label: String(p.label), url: String(p.url) }); result = store.data; break;
    case 'alarms': store.data.alarms = store.data.alarms.filter(a => a.id !== p.id); if (!p.remove) store.data.alarms.unshift({ id: String(p.id), label: String(p.label), time: String(p.time), days: Array.isArray(p.days) ? p.days as number[] : [], enabled: !!p.enabled }); result = store.data; break;
    case 'feed': result = feed.filter(post => !p.before || post.id < Number(p.before)); break;
    case 'post': {
      const post: Post = { id: Date.now(), number, body: String(p.body || ''), price: Number(p.price) || 0, created_at: timestamp(), likes: 0, comments: 0, liked: false, mine: true };
      if (p.kind === 'flash') { post.media_kind = p.mediaKind as Post['media_kind']; post.media_url = p.mediaKind === 'photo' ? sampleFlashPhoto() : String(p.media); }
      feed.unshift(post); break;
    }
    case 'reportListing': {
      const listing = classifieds.find(item => item.id === p.id);
      const [title, ...rest] = (listing?.body ?? '').split('\n');
      reports.unshift({ id: Date.now(), targetType: 'listing', targetId: Number(p.id), reason: String(p.reason), details: String(p.details || ''), status: 'open', createdAt: timestamp(), snapshot: { title, description: rest.join('\n'), price: listing?.price ?? 0 } });
      break;
    }
    case 'moderationQueue': result = reports.filter(report => report.status === (p.status || 'open')); break;
    case 'moderationResolve': {
      const report = reports.find(item => item.id === p.reportId);
      if (!report) throw new Error('Open report was not found');
      if (p.action === 'remove_content') classifieds = classifieds.filter(item => item.id !== report.targetId);
      report.status = p.action === 'dismiss' ? 'dismissed' : 'resolved';
      break;
    }
    case 'markSold': classifieds = classifieds.filter(post => post.id !== p.id); break;
    case 'contactSeller': break;
    case 'removePost': store.posts = store.posts.filter(post => post.id !== p.id); classifieds = classifieds.filter(post => post.id !== p.id); store.flash = store.flash.filter(post => post.id !== p.id); break;
    case 'like': for (const post of [...store.posts, ...classifieds, ...store.flash]) if (post.id === p.id) { post.likes += p.liked ? 1 : -1; post.liked = !!p.liked; } break;
    case 'comments': result = store.comments.filter(c => c.postId === p.id); break;
    case 'comment': store.comments.push({ id: Date.now(), postId: Number(p.id), number, body: String(p.body), created_at: timestamp() }); for (const post of [...store.posts, ...classifieds, ...store.flash]) if (post.id === p.id) post.comments++; break;
    case 'removeComment': store.comments = store.comments.filter(c => c.id !== p.id); break;
    case 'bank': result = store.bank; break;
    case 'transfer': {
      const amount = Number(p.amount);
      if (!Number.isInteger(amount) || amount <= 0 || amount > 100000 || amount > store.bank.balance) throw new Error('Invalid amount or insufficient funds');
      if (p.recipient !== '5550192042') throw new Error('Demo recipient: 5550192042');
      store.bank.balance -= amount; store.bank.history.unshift({ id, citizenid: store.bank.account, recipient: String(p.recipient), amount, status: 'completed', created_at: timestamp() }); result = { status: 'completed' }; break;
    }
    case 'property': result = [{ name: 'alta-14', label: '14 Alta Street', coords: { x: -270.2, y: -957.7 } }]; break;
    case 'vehicles': result = [{ vehicle: 'sultan', plate: 'NOTH1NG', garage: 'Legion Square', state: 1, fuel: 82 }]; break;
    case 'services': result = [{ label: 'Police', description: 'On-duty officers', numbers: ['5550109110'] }, { label: 'Medical', description: 'On-duty medics', numbers: ['5550103110'] }, { label: 'Mechanic', description: 'Repairs and roadside assistance', numbers: [] }]; break;
    case 'job': case 'setDuty': {
      if (action === 'setDuty') demoDuty = !!p.onDuty;
      result = { job: { name: 'police', label: 'Police', grade: 2, gradeLabel: 'Officer', onDuty: demoDuty }, actions: [{ id: 'panic', label: 'Send backup request' }] }; break;
    }
    case 'jobAction': result = { completed: true }; break;
    case 'capture': {
      const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="800"><rect width="600" height="800" fill="#c7c4b8"/><circle cx="420" cy="230" r="85" fill="#ede8d8"/><path d="M0 650 180 400 300 530 440 350 600 600V800H0" fill="#434844"/><path d="M0 760 220 600 420 670 600 510V800H0" fill="#262c29"/></svg>';
      store.data.photos.push({ id, url: `data:image/svg+xml,${encodeURIComponent(svg)}`, created_at: Date.now() / 1000 }); result = store.data; break;
    }
    case 'deletePhoto': store.data.photos = store.data.photos.filter(photo => photo.id !== p.id); result = store.data; break;
    case 'weather': result = { condition: 'EXTRASUNNY', hour: 10, minute: 8, rain: 0 }; break;
    case 'waypoint': break;
    case 'videoSignal': break;
    case 'wallet': result = { name: 'Charlie Parker', citizenId: 'ABC12345', birthdate: '1994-03-12', gender: 'Male', nationality: 'American', job: 'Police', licences: [{ id: 'driver', label: 'Driver licence', valid: true }, { id: 'weapon', label: 'Firearms licence', valid: false }, { id: 'business', label: 'Business licence', valid: false }] }; break;
    case 'showWallet': result = { shown: true }; break;
    case 'myLocation': result = { x: 195.2, y: -933.8, label: 'Legion Square, Downtown Vinewood', heading: 45 }; break;
    case 'conversations': result = store.conversations.map(c=>({...c,sortId:c.sortId??c.id})).filter(c=>!p.before || c.sortId<Number(p.before) || (p.cursorId && c.sortId===Number(p.before)&&c.id<Number(p.cursorId))).sort((a,b)=>b.sortId-a.sortId||b.id-a.id).slice(0,50); break;
    case 'startChat': {
      const target = String(p.number);
      let conversation = store.conversations.find(c => c.kind === 'direct' && c.members === target);
      if (!conversation) {
        conversation = { id: Date.now(), kind: 'direct', name: null, members: target, last_body: '', last_kind: null, last_number: null, last_at: null };
        store.conversations.unshift(conversation); store.chatMessages[conversation.id] = [];
      }
      result = { id: conversation.id }; break;
    }
    case 'createGroup': {
      const newId = Date.now();
      const numbers = Array.isArray(p.numbers) ? p.numbers as string[] : [];
      store.conversations.unshift({ id: newId, kind: 'group', name: String(p.name), members: numbers.join(','), last_body: '', last_kind: null, last_number: null, last_at: null });
      store.chatMessages[newId] = []; result = { id: newId }; break;
    }
    case 'conversation': result = (store.chatMessages[Number(p.id)] || []).filter(m => !p.before || m.id < Number(p.before)).slice().sort((a, b) => b.id - a.id); break;
    case 'sendChatMessage': {
      const convId = Number(p.conversationId);
      const message: ChatMessage = { id: Date.now(), sender_number: number, body: String(p.body || ''), created_at: timestamp() };
      if (p.mediaId) { const photo=store.data.photos.find(item=>item.id===String(p.mediaId)); if(!photo) throw new Error('Photo not found'); message.media_kind='photo'; message.media_url=photo.url; message.mediaId=Number(p.mediaId); }
      else if (p.mediaKind === 'video') { message.media_kind = 'video'; message.media_url = String(p.media); }
      (store.chatMessages[convId] ||= []).push(message);
      const conversation = store.conversations.find(c => c.id === convId);
      if (conversation) { conversation.last_body = message.body; conversation.last_kind = message.media_kind || null; conversation.last_number = number; conversation.last_at = timestamp(); conversation.sortId=message.id; }
      result=message; break;
    }
    case 'shareToChat': {
      const convId = Number(p.conversationId);
      const post = [...store.posts, ...classifieds, ...store.flash].find(item => item.id === Number(p.postId));
      if (!post) throw new Error('Post no longer available');
      const message: ChatMessage = { id: Date.now(), sender_number: number, body: post.body, media_url: post.media_url, media_kind: post.media_kind, shared_from_post: post.id, created_at: timestamp() };
      (store.chatMessages[convId] ||= []).push(message);
      const conversation = store.conversations.find(c => c.id === convId);
      if (conversation) { conversation.last_body = ''; conversation.last_kind = post.media_kind || null; conversation.last_number = number; conversation.last_at = timestamp(); conversation.sortId=message.id; }
      break;
    }
    case 'uploadMedia': { const blob = p.blob as Blob; (p.onProgress as ((n: number) => void) | undefined)?.(1); result = { id: 0, url: await blobToDataUrl(blob), kind: blob.type.startsWith('video/') ? 'video' : 'photo' }; break; }
    case 'createProfile': break;
    case 'blocked': result = (store as { blocked?: string[] }).blocked ?? []; break;
    case 'setBlocked': { const list = new Set((store as { blocked?: string[] }).blocked ?? []); if (p.blocked) list.add(String(p.number)); else list.delete(String(p.number)); (store as { blocked?: string[] }).blocked = [...list]; break; }
    case 'legacyMailList': result=store.legacyMail!.filter(m=>!p.before || m.id<Number(p.before)).slice().sort((a,b)=>b.id-a.id).slice(0,50); break;
    case 'legacyActivity': result=store.legacyActivity!.filter(m=>!p.before || m.id<Number(p.before)).slice().sort((a,b)=>b.id-a.id).slice(0,50); break;
    case 'mailAccept': { const mail=store.legacyMail!.find(m=>m.id===p.id); if(!mail?.hasAction) throw new Error('Mail action is no longer available'); mail.hasAction=false; break; }
    case 'legacyMailRead': { const mail=store.legacyMail!.find(m=>m.id===p.id); if(mail)mail.unread=false; break; }
    case 'legacyMailDelete': store.legacyMail=store.legacyMail!.filter(m=>m.id!==p.id); break;
    case 'mailList': result = store.messages.filter(m => m.kind === 'mail' && (p.box === 'sent' ? m.sender === number : m.recipient === number)).sort((a, b) => b.id - a.id).map(m => ({ id: m.id, peer: p.box === 'sent' ? m.recipient : m.sender, subject: m.subject, body: m.body, created_at: m.created_at, unread: p.box !== 'sent' && !(m as { read?: boolean }).read })); break;
    case 'mailSend': store.messages.push({ id: Date.now(), sender: number, recipient: String(p.to), body: String(p.body), kind: 'mail', subject: String(p.subject), created_at: timestamp() }); break;
    case 'mailRead': { const mail = store.messages.find(m => m.id === p.id) as { read?: boolean } | undefined; if (mail) mail.read = true; break; }
    case 'mailDelete': store.messages = store.messages.filter(m => m.id !== p.id); break;
    case 'addMember': { const conversation = store.conversations.find(c => c.id === Number(p.id)); if (conversation) conversation.members = [conversation.members, String(p.number)].filter(Boolean).join(','); break; }
    case 'markConversationRead': { const conversation = store.conversations.find(c => c.id === Number(p.id)); if (conversation) conversation.unreadCount = 0; break; }
    case 'leaveGroup': store.conversations = store.conversations.filter(c => c.id !== Number(p.id)); break;
  }
  save(); completed.set(id, structuredClone(result));
  return structuredClone(result) as Api[K][1];
}
