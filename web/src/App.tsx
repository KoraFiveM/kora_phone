import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties, ComponentType, PointerEvent as ReactPointerEvent } from 'react';
import { AlarmClock, Aperture, ArrowDown, ArrowRight, ArrowUpRight, BatteryFull, Bell, Calculator, Camera, Car, Check, ChevronLeft, CloudSun, ContactRound, CreditCard, Fingerprint, House, Image, LockKeyhole, Mail, MapPin, MessageCircle, Moon, Music, Mic, MicOff, Pause, Play, Phone, PhoneIncoming, PhoneOff, Power, Radio, Settings as SettingsIcon, ShieldAlert, ShieldCheck, Signal, Smartphone, SlidersHorizontal, StickyNote, Store as StoreIcon, Sun, Tag, Video, VideoOff, SwitchCamera, Wifi, X } from 'lucide-react';
import { LONG_PRESS_MS, MOVE_TOLERANCE, mergeOrder, moveItem } from './homeReorder';
import { adaptBootstrap, adaptLiveCall, api, isPreview, launchApps, nui, sendSignal } from './api';
import { previewBootstrap, previewIncoming, resetPreview } from './mock';
import { normalizeData } from './types';
import type { Alarm, AppId, Bootstrap, Call, Conversation, DeviceData, Notification } from './types';
import { DotClock, PageHeader } from './components';
import { GameVideo, createGameView } from './gameVideo';
import type { VideoSignal } from './gameVideo';
import { HandsetPanel } from './HandsetPanel';
import './handset-shells.css';
import './theme-system.css';
import './nothing-standard.css';
import { CoverBackdrop } from './CoverArt';
import { imageUrl } from './Images';
import { PhoneContext } from './PhoneContext';
import { appCopy } from './locales';
import { StoreScreen } from './Store';
import { PhotoImage } from './Images';
import { handsetIconStyle, handsetThemeTokens, resolveHandsetTheme } from './themes';
import { SetupScreen } from './Setup';
import { isHostMessage } from './nuiEvents';
import { CustomAppScreen } from './CustomApps';
import { recall, remember } from './lastScreen';
import { isQuiet } from './quiet';
import type { Quiet } from './quiet';
import { previewText } from './chatTokens';
import { mergeConversations } from './chatMessages';
import { ContactsScreen, MailScreen, MessagesScreen, PhoneScreen } from './Communication';
import { BankScreen, FeedScreen } from './SocialBank';
import { PulseScreen } from './Pulse';
import { ModerationScreen } from './Moderation';
import { CalculatorScreen, GalleryScreen, GPSScreen, NotesScreen, PropertyScreen, ServicesScreen, VehiclesScreen, WeatherScreen } from './Utilities';
import { FlashScreen } from './Flash';
import { SettingsScreen } from './Settings';
import { ClockScreen, MusicScreen, alarmTone } from './Media';

type Icon = ComponentType<{ size?: number; strokeWidth?: number; className?: string }>;
const apps: { id: AppId; label: string; icon: Icon; subtitle: string }[] = [
  { id: 'banking', label: 'Wallet', icon: CreditCard, subtitle: 'A little peace of mind.' },
  { id: 'social', label: 'Pulse', icon: Radio, subtitle: 'The city, in conversation.' },
  { id: 'gallery', label: 'Gallery', icon: Image, subtitle: 'The moments you keep.' },
  { id: 'classifieds', label: 'Market', icon: Tag, subtitle: 'Good things. New beginnings.' },
  { id: 'gps', label: 'Maps', icon: MapPin, subtitle: 'Find your own way.' },
  { id: 'services', label: 'Services', icon: ShieldCheck, subtitle: 'Someone to count on.' },
  { id: 'notes', label: 'Notes', icon: StickyNote, subtitle: 'Room for a thought.' },
  { id: 'mail', label: 'Mail', icon: Mail, subtitle: 'A little more to say.' },
  { id: 'weather', label: 'Weather', icon: CloudSun, subtitle: 'Look on the bright side.' },
  { id: 'calculator', label: 'Calculator', icon: Calculator, subtitle: 'It all adds up.' },
  { id: 'property', label: 'Home', icon: House, subtitle: 'Your corner of the city.' },
  { id: 'vehicles', label: 'Garage', icon: Car, subtitle: 'Make your next move.' },
  { id: 'flash', label: 'Flash', icon: Aperture, subtitle: 'Your city, in short clips.' },
  { id: 'music', label: 'Sound', icon: Music, subtitle: 'Something to listen to.' },
  { id: 'clock', label: 'Clock', icon: AlarmClock, subtitle: 'Right on time.' },
  { id: 'phone', label: 'Phone', icon: Phone, subtitle: 'A voice on the other end.' },
  { id: 'messages', label: 'Messages', icon: MessageCircle, subtitle: 'Stay a little closer.' },
  { id: 'contacts', label: 'Contacts', icon: ContactRound, subtitle: 'Good people. One place.' },
  { id: 'camera', label: 'Camera', icon: Camera, subtitle: 'See something. Keep it.' },
  { id: 'settings', label: 'Settings', icon: SettingsIcon, subtitle: 'Unmistakably yours.' },
  { id: 'store', label: 'App Store', icon: StoreIcon, subtitle: 'A little more you.' },
  { id: 'moderation', label: 'Moderation', icon: ShieldAlert, subtitle: 'Keep the city civil.' },
];
const iconOf = (id: AppId) => apps.find(app => app.id === id)!;
function NotificationIcon({ id, size = 18 }: { id: AppId; size?: number }) { const Icon = apps.find(item => item.id === id)?.icon ?? Bell; return <Icon size={size} strokeWidth={1.6} />; }
function HeadsUp({ alert, locked, onOpen, onDismiss }: { alert: Notification; locked: boolean; onOpen: () => void; onDismiss: () => void }) {
  const drag = useRef<{ y: number; scale: number; moved: boolean } | null>(null);
  const [dy, setDy] = useState(0);
  return <button className="heads-up" style={dy ? { transform: `translateY(${dy}px)`, opacity: 1 + dy / 90 } : undefined}
    onPointerDown={e => { drag.current = { y: e.clientY, scale: e.currentTarget.getBoundingClientRect().height / e.currentTarget.offsetHeight || 1, moved: false }; e.currentTarget.setPointerCapture(e.pointerId); }}
    onPointerMove={e => { const d = drag.current; if (!d) return; const next = Math.min(0, (e.clientY - d.y) / d.scale); if (next < -6) d.moved = true; setDy(next); }}
    onPointerUp={() => { if (dy < -24) onDismiss(); else setDy(0); }}
    onPointerCancel={() => { drag.current = null; setDy(0); }}
    onClick={() => { const swiped = drag.current?.moved; drag.current = null; if (!swiped) onOpen(); }}>
    <span className="heads-up-icon"><NotificationIcon id={alert.app} size={16} /></span>
    <span className="heads-up-text"><strong>{alert.title}</strong><small>{locked ? 'Unlock to view.' : alert.body}</small></span>
  </button>;
}
// Notifications survive closing the phone and reloading the UI: unread ones stay in the shade, read ones move to "Earlier".
function storedNotifications(): { a: Notification[]; e: Notification[] } {
  try { const v = JSON.parse(recall('notifications') ?? 'null'); return { a: Array.isArray(v?.a) ? v.a : [], e: Array.isArray(v?.e) ? v.e : [] }; } catch { return { a: [], e: [] }; }
}
const lastApp = (value?: Bootstrap): AppId => {
  const id = recall('app') as AppId;
  if (!apps.some(item => item.id === id) || !launchApps.has(id) || value?.capabilities[id] === false) return 'home';
  return id;
};
function AppIcon({ id, onClick, dock = false, badge = 0, editing = false, dragging = false, over = false, onPointerDown }: {
  id: AppId; onClick: () => void; dock?: boolean; badge?: number; editing?: boolean; dragging?: boolean; over?: boolean;
  onPointerDown?: (e: ReactPointerEvent<HTMLButtonElement>) => void;
}) {
  const { icon: Icon } = iconOf(id);
  const { label } = appCopy(id);
  return <button data-app-id={id} data-zone={dock ? 'dock' : 'grid'} draggable={false} onPointerDown={onPointerDown} onClick={onClick} className={`app-icon ${dock ? 'dock-icon' : ''} app-${id} ${editing ? 'jiggle' : ''} ${dragging ? 'dragging' : ''} ${over ? 'drop-target' : ''}`} aria-label={`Open ${label}`}><span><Icon size={25} strokeWidth={1.6} /></span>{badge > 0 && <b className="app-badge" aria-label={`${badge} new`}>{badge > 9 ? '9+' : badge}</b>}{!dock && <small>{label}</small>}{editing && <i className="edit-handle" aria-hidden="true" />}</button>;
}
function useTime() { const [date, setDate] = useState(new Date()); useEffect(() => { const timer = setInterval(() => setDate(new Date()), 1000); return () => clearInterval(timer); }, []); return date; }
export default function App() {
  const [device, setDevice] = useState<Bootstrap | undefined>(() => isPreview ? previewBootstrap() : undefined);
  const [shown, setShown] = useState(isPreview); const [app, setApp] = useState<AppId>(() => lastApp(isPreview ? previewBootstrap() : undefined)); const [target, setTarget] = useState('');
  const [call, setCall] = useState<Call | undefined>(); const [toast, setToast] = useState(''); const [alert, setAlert] = useState<Notification | undefined>();
  const [busy, setBusy] = useState(false); const busyRef = useRef(false);
  const [revision, setRevision] = useState(0); const [hiddenCapture, setHiddenCapture] = useState(false);
  const [notifications, setNotifications] = useState<Notification[]>(() => storedNotifications().a); const [earlier, setEarlier] = useState<Notification[]>(() => storedNotifications().e); const [showNotifications, setShowNotifications] = useState(false);
  const [homePage, setHomePage] = useState(0);
  const [editing, setEditing] = useState(false);
  const [dragId, setDragId] = useState<AppId | null>(null);
  const [overId, setOverId] = useState<AppId | null>(null);
  const suppressClick = useRef(false);
  const dragCleanup = useRef<(() => void) | null>(null);
  const [folded, setFolded] = useState(false);
  const [serviceOpen, setServiceOpen] = useState(false);
  const [serviceRequest, setServiceRequest] = useState<{id:string;label:string;operation:string}>();
  const [serviceResult, setServiceResult] = useState<{message:string;accountId?:string;recoveryCode?:string}>();
  const serviceDialog = useRef<HTMLDivElement>(null);
  const [videoRequest, setVideoRequest] = useState(false);
  const [videoPending, setVideoPending] = useState(false);
  const [muted, setMuted] = useState(false);
  const [coverCamera, setCoverCamera] = useState(false);
  const [coverPlaying, setCoverPlaying] = useState(false);
  const [foldInbox, setFoldInbox] = useState<Conversation[]>([]);
  const [foldInboxMore,setFoldInboxMore]=useState(false);
  const coverCanvas = useRef<HTMLCanvasElement>(null);
  const coverAudio = useRef<HTMLAudioElement | undefined>(undefined);
  const model = device?.model || 'standard';
  const handsetPalette = resolveHandsetTheme(model,device?.data?.settings.theme || device?.preferences?.theme);
  const flip = model === 'flip';
  const fold = model === 'fold';
  const brand = model === 'standard' ? 'ORCHARD' : model === 'flip' ? 'CIRCUIT' : 'ATLAS';
  const [unfolding, setUnfolding] = useState(false);
  // Keep the cover mounted while it swings open, so unfolding plays the fold in reverse.
  const unfold = () => { if (flip) { snapshotForUnfold(); setUnfolding(true); window.setTimeout(() => setUnfolding(false), 800); } setFolded(false); setCoverCamera(false); };
  const phoneRef = useRef<HTMLDivElement>(null);
  const screenRef = useRef<HTMLDivElement>(null);
  // Folding hides the real display straight away, so copy it first: the top half of the copy rides on the
  // half that swings down and the bottom half stays lit under it, until the phone is shut.
  const snapshotForFold = () => {
    const phone = phoneRef.current, screen = screenRef.current;
    if (!phone || !screen || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const layer = (className: string, copyClass: string) => {
      const el = document.createElement('div'); el.className = className; el.setAttribute('aria-hidden', 'true');
      const copy = screen.cloneNode(true) as HTMLElement; copy.removeAttribute('inert'); copy.classList.add(copyClass);
      el.appendChild(copy); phone.appendChild(el); return el;
    };
    const face = document.createElement('div'); face.className = 'fold-face'; face.setAttribute('aria-hidden', 'true');
    const faceInner = layer('fold-face-inner', 'fold-copy-top'); face.appendChild(faceInner); phone.appendChild(face);
    const made = [layer('fold-rest', 'fold-copy-bottom'), face];
    window.setTimeout(() => made.forEach(el => el.remove()), 600);
  };
  const snapshotForUnfold = () => {
    const phone = phoneRef.current, screen = screenRef.current;
    if (!phone || !screen || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const layer = (className: string, copyClass: string) => {
      const el = document.createElement('div'); el.className = className; el.setAttribute('aria-hidden', 'true');
      const copy = screen.cloneNode(true) as HTMLElement; copy.removeAttribute('inert'); copy.classList.add(copyClass);
      el.appendChild(copy); phone.appendChild(el); return el;
    };
    const face = layer('unfold-face', 'unfold-copy-top');
    const rest = layer('unfold-rest', 'unfold-copy-bottom');
    window.setTimeout(() => { face.remove(); rest.remove(); }, 800);
  };
  const [pin, setPin] = useState(''); const [lockError, setLockError] = useState('');
  const [viewport, setViewport] = useState({ width: window.innerWidth, height: window.innerHeight });
  const [phonePosition, setPhonePosition] = useState<{ x: number; y: number } | null>(null);
  const phoneStage = useRef<HTMLDivElement>(null);
  const phoneDrag = useRef<{ x: number; y: number; width: number; height: number } | null>(null);
  const audio = useRef<AudioContext | undefined>(undefined);
  const [videoOn, setVideoOn] = useState(false); const [remoteVideo, setRemoteVideo] = useState(false);
  const gameVideo = useRef<GameVideo | undefined>(undefined);
  const videoCallId = useRef<string | undefined>(undefined);
  const videoEpoch = useRef<string | undefined>(undefined);
  const pauseVideo = useRef(false); pauseVideo.current = flip && folded;
  const videoReady = useRef(false);
  const pendingSignals = useRef<VideoSignal[]>([]);
  const localStream = useRef<MediaStream | undefined>(undefined);
  const remoteStream = useRef<MediaStream | undefined>(undefined);
  const localVideoRef = useRef<HTMLVideoElement>(null); const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const date = useTime();
  const callRef = useRef<Call | undefined>(undefined); callRef.current = call;
  const notificationDevice = useRef<string | undefined>(device?.id);
  if (device) notificationDevice.current=device.id;
  const shownRef = useRef(shown); shownRef.current = shown;
  const appRef = useRef(app); appRef.current = app;
  // Contact names, kept while the phone is closed so a game notification can say who it's from (memory only).
  const contactNames = useRef(new Map<string, string>());
  const data = useMemo(() => {
    const normalized = normalizeData(device?.data);
    if (device?.preferences && !device.data) normalized.settings = device.preferences;
    return normalized;
  }, [device?.data, device?.preferences]);
  const locked = device?.locked ?? true;
  const phoneCase = data.settings.phoneCase ?? 'default';
  const caseHasArt = phoneCase !== 'default' && (phoneCase !== 'custom' || imageUrl(data.settings.phoneCaseUrl ?? ''));
  // The phone screen is unmounted while closed, so the last-known Do Not Disturb setting lives in a ref (and storage).
  const quietConfig = useRef<Quiet>((() => { try { return JSON.parse(recall('quiet') ?? '{}') as Quiet; } catch { return {}; } })());
  const { dnd, dndFrom, dndTo } = data.settings;
  useEffect(() => { if (!device) return; quietConfig.current = { dnd, dndFrom, dndTo }; remember('quiet', JSON.stringify(quietConfig.current)); }, [device, dnd, dndFrom, dndTo]);
  const quiet = isQuiet(device ? { dnd, dndFrom, dndTo } : quietConfig.current, date);
  useEffect(() => { void nui('quiet', { quiet }); }, [quiet]);
  useEffect(() => { remember('notifications', JSON.stringify({ a: notifications, e: earlier })); }, [notifications, earlier]);
  useEffect(() => {
    if (!device?.id) return;
    setNotifications(list=>list.filter(item=>item.deviceId===device.id));
    setEarlier(list=>list.filter(item=>item.deviceId===device.id));
    setAlert(current=>current?.deviceId===device.id ? current : undefined);
  }, [device?.id]);
  // Alarms are checked here, not inside the Clock screen, so they still ring with the phone closed.
  const alarms = useRef<Alarm[]>((() => { try { const v = JSON.parse(recall('alarms') ?? '[]'); return Array.isArray(v) ? v : []; } catch { return []; } })());
  const firedAlarms = useRef(new Set<string>());
  useEffect(() => { if (!device) return; alarms.current = data.alarms; remember('alarms', JSON.stringify(data.alarms)); }, [device, data.alarms]);
  useEffect(() => {
    const at = `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
    for (const alarm of alarms.current) {
      if (!alarm.enabled || alarm.time !== at || (alarm.days.length && !alarm.days.includes(date.getDay()))) continue;
      const key = `${alarm.id}-${date.toDateString()}-${at}`;
      if (firedAlarms.current.has(key)) continue;
      firedAlarms.current.add(key);
      window.dispatchEvent(new MessageEvent('message', { data: { type: 'notification', data: { title: 'Alarm', body: alarm.label || 'Untitled', app: 'clock', urgent: true } } }));
      alarmTone(); void nui('alarm', { label: alarm.label });
      if (!alarm.days.length) {
        // A one-time alarm turns itself off after ringing.
        alarms.current = alarms.current.map(a => a.id === alarm.id ? { ...a, enabled: false } : a);
        void api('alarms', { ...alarm, enabled: false }).then(value => { if (device) updateData(value); }).catch(() => undefined);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [date]);
  useEffect(() => { if (device) contactNames.current = new Map(data.contacts.map(c => [c.number, c.name])); }, [device, data.contacts]);
  useEffect(() => { remember('app', app); }, [app]);
  const time = date.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const navigate = useCallback((requested: AppId, destination = '') => { const id: AppId = launchApps.has(requested) && (requested === 'home' || apps.some(item => item.id === requested)) ? requested : 'home'; setApp(id); setTarget(destination); setShowNotifications(false); setHomePage(0); setEditing(false); setDragId(null); setOverId(null); }, []);
  const notify = useCallback((message: string) => setToast(message), []);
  const markRead = useCallback((items: Notification[]) => { setNotifications(list => list.filter(n => !items.some(item => item === n || (item.app === n.app && item.title === n.title)))); setEarlier(list => [...items, ...list].slice(0, 30)); }, []);
  // Being in an app means you've seen its notifications.
  useEffect(() => { if (!shown || app === 'home') return; const seen = notifications.filter(n => n.app === app || (app === 'social' && n.app === 'messages')); if (seen.length) markRead(seen); }, [app, shown, notifications, markRead]);
  const run = useCallback(async (work: () => Promise<void>) => {
    if (busyRef.current) return;
    busyRef.current = true; setBusy(true);
    try { await work(); } catch (e) { setToast(e instanceof Error ? e.message : 'Something went wrong'); }
    finally { busyRef.current = false; setBusy(false); }
  }, []);
  const updateData = (value: DeviceData) => setDevice(current => current && current.id === device?.id ? { ...current, data: normalizeData(value) } : current);
  const apply = useCallback((value: Bootstrap) => {
    const mine = (n: Notification) => n.deviceId === value.id;
    setFolded(value.model === 'fold');
    setDevice(value); setShown(true); setApp(lastApp(value)); setTarget(''); setPin(''); setLockError(''); setNotifications(list => list.filter(mine)); setEarlier(list => list.filter(mine)); setToast(''); setAlert(undefined); setCall(value.call); setHiddenCapture(false); setShowNotifications(false); setEditing(false); setDragId(null); setOverId(null);
  }, []);
  const stopVideo = useCallback(() => {
    gameVideo.current?.stop(); gameVideo.current = undefined;
    videoReady.current = false; videoCallId.current = undefined; videoEpoch.current = undefined; pendingSignals.current = [];
    localStream.current = undefined; remoteStream.current = undefined;
    if (localVideoRef.current) localVideoRef.current.srcObject = null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null;
    setVideoOn(false); setRemoteVideo(false); setVideoRequest(false); setVideoPending(false);
  }, []);
  const close = useCallback(() => {
    stopVideo(); setCoverCamera(false); coverAudio.current?.pause(); setCoverPlaying(false);
    const current = callRef.current;
    if (current && ['active', 'ringing'].includes(current.status)) void api('hangup', { id: current.id, reject: current.direction === 'incoming' && current.status === 'ringing' }).catch(() => undefined);
    void nui('close'); setServiceOpen(false); setServiceRequest(undefined); setServiceResult(undefined); setCall(undefined); setAlert(undefined); setShown(false); setDevice(undefined); setPin(''); setEditing(false); setDragId(null); setOverId(null);
  }, [stopVideo]);
  const videoControl = useCallback(async (action: 'request' | 'accept' | 'decline' | 'stop' | 'mute', nextMuted?: boolean) => {
    const current = callRef.current;
    if (!current || current.status !== 'active') return;
    if (isPreview) { setToast('Live video and voice controls are available in FiveM.'); return; }
    const reply = await nui<{ok: boolean; error?: string | {message?: string}}>('calls:videoControl', { id: current.id, action, epoch:videoEpoch.current, ...(nextMuted === undefined ? {} : { muted: nextMuted }) });
    if (!reply.ok) throw new Error(typeof reply.error === 'string' ? reply.error : reply.error?.message || 'Call control failed');
    if (action === 'request') setVideoPending(true);
    if (action === 'decline' || action === 'stop') stopVideo();
    if (action === 'mute' && nextMuted !== undefined) setMuted(nextMuted);
  }, [stopVideo]);
  const beginVideo = useCallback(async () => {
    const current = callRef.current;
    if (!device?.video || !current || current.status !== 'active' || gameVideo.current) return;
    const id = current.id; const epoch = videoEpoch.current;
    if (!epoch) return;
    const connection = new GameVideo(); gameVideo.current = connection;
    videoCallId.current = id; videoReady.current = false;
    setVideoRequest(false); setVideoPending(false); setVideoOn(true);
    try {
      await connection.start(device.video.iceServers, current.direction === 'incoming',
        signal => { if (callRef.current?.id === id && gameVideo.current === connection) sendSignal({ id, epoch, ...signal }); },
        (stream, local) => {
          if (gameVideo.current !== connection || callRef.current?.id !== id) return;
          if (local) { connection.setPaused(pauseVideo.current); localStream.current = stream; if (localVideoRef.current) localVideoRef.current.srcObject = stream; }
          else { remoteStream.current = stream; setRemoteVideo(true); if (remoteVideoRef.current) remoteVideoRef.current.srcObject = stream; }
        },
        message => { if (gameVideo.current === connection) { stopVideo(); setToast(message); void nui('calls:videoControl', {id,epoch,action:'stop'}).catch(() => undefined); } });
      if (gameVideo.current !== connection || callRef.current?.id !== id) { connection.stop(); return; }
      connection.setPaused(pauseVideo.current);
      videoReady.current = true;
      for (const signal of pendingSignals.current.splice(0)) await connection.receive(signal);
    } catch (problem) {
      if (gameVideo.current === connection) { stopVideo(); setToast(problem instanceof Error ? problem.message : 'Video failed. Voice remains connected.'); void nui('calls:videoControl', {id,epoch,action:'stop'}).catch(() => undefined); }
    }
  }, [device?.video, stopVideo, videoControl]);
  const handleVideoSignal = useCallback(async (signal: VideoSignal & {id?: string; epoch?: string}) => {
    if (!signal || typeof signal !== 'object' || signal.id !== callRef.current?.id || !signal.epoch || signal.epoch !== videoEpoch.current || callRef.current?.status !== 'active') return;
    if (!gameVideo.current || !videoReady.current) {
      if (pendingSignals.current.length < 128) pendingSignals.current.push(signal);
      return;
    }
    if (videoCallId.current === signal.id) await gameVideo.current.receive(signal);
  }, []);
  const reloadHandset = useCallback(async () => {
    if (isPreview) { setRevision(value=>value+1); return; }
    const next = await api('refresh', {});
    setDevice(next); setRevision(value => value + 1);
  }, []);
  useEffect(() => {
    const resize = () => setViewport({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener('resize', resize);
    return () => window.removeEventListener('resize', resize);
  }, []);
  useEffect(() => {
    const handler = (event: MessageEvent) => {
      const message = event.data;
      if (!message || typeof message !== 'object') return;
      // Embedded apps must never spoof native phone events.
      if (!isHostMessage(event.source, window, window.parent)) return;
      const type = message.action || message.type;
      if (type === 'service:request' && message.data?.id) { setServiceRequest({ id: String(message.data.id), label: String(message.data.label || 'Mobile shop'), operation: String(message.data.operation || 'service') }); return; }
      if (type === 'service:result' && message.data) {
        const result = message.data.result || message.data; const details = result.data || result;
        const problem = result.error;
        setServiceRequest(undefined); setServiceResult({ message: result.ok === false ? (typeof problem === 'string' ? problem : problem?.message || 'Service could not complete') : 'Mobile service completed.', accountId: details.accountId, recoveryCode: details.recoveryCode }); return;
      }
      if (type === 'service:open') { stopVideo(); setShown(false); setServiceOpen(true); return; }
      if (type === 'customOpen' && !locked) navigate('custom', message.app);
      if (type === 'phone:open' || type === 'open') {
        const live = message.data?.state?.activeCall;
        void api('refresh', {}).then(value => apply(live ? { ...value, call: adaptLiveCall(live) } : value)).catch(error => { void nui('close', { error: error instanceof Error ? error.message : 'Could not open phone' }); });
      }
      else if (type === 'bootstrap' && message.data) setDevice(adaptBootstrap(message.data));
      else if (type === 'phone:close' || type === 'phone:reset' || type === 'close') {
        if(type==='phone:reset'){notificationDevice.current=undefined;setNotifications([]);setEarlier([]);alarms.current=[];quietConfig.current={};contactNames.current.clear();remember('alarms','[]');remember('quiet','{}');}
        setAlert(undefined); stopVideo(); setCoverCamera(false); coverAudio.current?.pause(); setCoverPlaying(false); setServiceOpen(false); setServiceRequest(undefined); setServiceResult(undefined); setShown(false); setDevice(undefined); setCall(undefined); setPin(''); }
      else if (type === 'content:cleared') { setNotifications([]); setEarlier([]); setAlert(undefined); }
      else if (type === 'capture') setHiddenCapture(!!message.hidden);
      else if (type === 'phone:visibility') setHiddenCapture(message.data === false);
      else if (type === 'camera:closed') setHiddenCapture(false);
      else if (type === 'call') { if (message.data?.id !== callRef.current?.id) { stopVideo(); setMuted(false); } setCall(message.data); }
      else if (type === 'calls:incoming' || type === 'calls:outgoing' || type === 'calls:accepted') { if (message.data?.id !== callRef.current?.id) { stopVideo(); setMuted(false); } setCall(adaptLiveCall(message.data)); }
      else if (type === 'calls:ended') {
        // An incoming call nobody answered leaves a note, even if the phone is closed.
        const ringing = callRef.current;
        if (ringing && ringing.direction === 'incoming' && ringing.id === message.data?.id && ['missed', 'cancelled'].includes(message.data?.status)) { push({ title: ringing.number, body: 'Missed call', app: 'phone' }); closedAlert(ringing.number, 'Missed call'); }
        setCall(current => current && current.id === message.data?.id ? { ...current, status: 'ended' } : current);
      }
      else if (type === 'videoSignal') void handleVideoSignal(message.data);
      else if (type === 'videoControl' && message.data?.id === callRef.current?.id) {
        const action = message.data.action;
        if (action === 'pending') { videoEpoch.current=message.data.epoch; setVideoPending(true); }
        else if (action === 'request' || action === 'requested') { if (typeof message.data.epoch === 'string') { videoEpoch.current = message.data.epoch; setVideoRequest(true); } }
        else if (action === 'accept' || action === 'accepted') { if (typeof message.data.epoch === 'string') { videoEpoch.current = message.data.epoch; void beginVideo(); } }
        else if (action === 'stop' || action === 'decline' || action === 'declined') { stopVideo(); if (action !== 'stop') setToast('Video invitation declined.'); }
        else if (action === 'mute' && typeof message.data.muted === 'boolean') setMuted(message.data.muted);
      }
      else if (type === 'video:stopped') { stopVideo(); setToast('Camera stopped. Voice remains connected.'); }
      else if (type === 'messages:read') setRevision(v => v + 1);
      else if (type === 'messages:new' && message.data && !message.data.isMine) {
        if(message.data.deviceId && notificationDevice.current && String(message.data.deviceId)!==notificationDevice.current) return;
        const sender = String(message.data.senderNumber || 'New message'); push({ deviceId:message.data.deviceId, title: sender, body: previewText(message.data.body), app: 'messages' }); closedAlert(sender, previewText(message.data.body)); }
      else if (type === 'legacy:activity') setRevision(v=>v+1);
      else if (type === 'mail:new' && message.data) {
        if(message.data.deviceId && notificationDevice.current && String(message.data.deviceId)!==notificationDevice.current) return;
        const sender = String(message.data.sender || 'New mail'); push({ deviceId:message.data.deviceId, title: sender, body: String(message.data.subject || 'New mail'), app: 'mail' }); closedAlert(sender, String(message.data.subject || 'New mail')); }
      else if (type === 'notification' || type === 'notification:push') push(message.data || {});
    };
    // With the phone closed nothing on screen can show a notification, so ask the game for one (silenced by Do Not Disturb).
    const closedAlert = (title: string, body: string) => {
      if (shownRef.current || isQuiet(quietConfig.current)) return;
      void nui('notify', { title: contactNames.current.get(title) ?? title, body });
    };
    const push = (incoming: Record<string, any>) => {
      const notification = { deviceId: String(incoming.deviceId || notificationDevice.current || ''), title: String(incoming.title || 'Notification'), body: String(incoming.body || incoming.message || ''), app: (incoming.app || 'messages') as AppId, at: Date.now() } as Notification;
      if (notification.deviceId && (!notificationDevice.current || notificationDevice.current === notification.deviceId)) {
        setNotifications(previous => {
          const matching = previous.find(item => item.deviceId === notification.deviceId && item.app === notification.app && item.title === notification.title);
          return matching ? [{ ...notification, count: (matching.count ?? 1) + 1 }, ...previous.filter(item => item !== matching)] : [notification, ...previous].slice(0, 20);
        });
        // Do Not Disturb still collects the notification, it just doesn't pop up (unless it's urgent).
        // No pop-up for a text while you're already looking at your chats.
        const reading = incoming.app === 'messages' && shownRef.current && (appRef.current === 'messages' || appRef.current === 'social');
        if (!reading && (incoming.urgent === true || !isQuiet(quietConfig.current))) setAlert(notification);
        setRevision(v => v + 1);
      }
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, [apply, device?.id, locked, navigate, handleVideoSignal, beginVideo, stopVideo]);
  useEffect(() => { if (call?.status !== 'active') stopVideo(); }, [call?.id, call?.status, stopVideo]);
  useEffect(() => { gameVideo.current?.setPaused(flip && folded); }, [flip, folded, videoOn]);
  useEffect(() => { if (localVideoRef.current) localVideoRef.current.srcObject = localStream.current || null; if (remoteVideoRef.current) remoteVideoRef.current.srcObject = remoteStream.current || null; }, [videoOn, remoteVideo, folded]);
  useEffect(() => () => { gameVideo.current?.stop(); coverAudio.current?.pause(); }, []);
  useEffect(() => {
    if (!fold || folded || app !== 'messages' || !shown || locked) return;
    let live = true;
    void api('conversations', {}).then(value => { if (live) { setFoldInbox(value);setFoldInboxMore(value.length===50); } }).catch(() => undefined);
    return () => { live = false; };
  }, [fold, folded, app, revision, shown, locked, device?.id]);
  useEffect(() => {
    if (!coverCamera || !flip || !folded || !shown || !coverCanvas.current) return;
    let cancelled = false; let animation = 0; let view: ReturnType<typeof createGameView> | undefined;
    void nui<{ok:boolean;error?:string}>('camera:coverStart', { active: true }).then(result => {
      if (!result.ok) throw new Error(result.error || 'Camera unavailable');
      if (cancelled || !coverCanvas.current) return;
      view = createGameView(coverCanvas.current); view.resize(280, 150);
      let previous = 0; const draw = (now: number) => { if (cancelled) return; animation = requestAnimationFrame(draw); if (now - previous > 66) { view?.render(); previous = now; } };
      animation = requestAnimationFrame(draw);
    }).catch(problem => { if (!cancelled) { setCoverCamera(false); setToast(problem instanceof Error ? problem.message : 'Camera unavailable'); } });
    return () => { cancelled = true; cancelAnimationFrame(animation); view?.dispose(); void nui('camera:coverStart', { active: false }); };
  }, [coverCamera, flip, folded, shown]);
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.defaultPrevented) return; if (event.key === 'Escape' && serviceRequest) { void nui('handset:action', { op: 'consent', id: serviceRequest.id, accept: false }); setServiceRequest(undefined); if (!shown && !serviceOpen) void nui('close'); return; } if (event.key === 'Escape' && (serviceOpen || serviceResult)) { close(); return; } if (event.key === 'Escape' && shown) { if (app !== 'home') navigate('home'); else close(); } };
    window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key);
  }, [app, shown, serviceOpen, serviceRequest, serviceResult, close, navigate]);
  useEffect(() => {
    if (!serviceRequest && !serviceResult) return;
    const previous = document.activeElement as HTMLElement | null;
    serviceDialog.current?.querySelector<HTMLButtonElement>('button')?.focus();
    const trap = (event: KeyboardEvent) => {
      if (event.key !== 'Tab') return;
      const buttons = serviceDialog.current?.querySelectorAll<HTMLButtonElement>('button:not(:disabled)');
      if (!buttons?.length) return;
      const first = buttons[0], last = buttons[buttons.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', trap);
    return () => { document.removeEventListener('keydown', trap); previous?.focus(); };
  }, [serviceRequest, serviceResult]);
  useEffect(() => { if (!alert) return; const timer = setTimeout(() => setAlert(undefined), 4000); return () => clearTimeout(timer); }, [alert]);
  useEffect(() => { if (!toast) return; const timer = setTimeout(() => setToast(''), 5000); return () => clearTimeout(timer); }, [toast]);
  useEffect(() => {
    if (!call || call.status === 'active' || call.status === 'ringing') return;
    const timer = setTimeout(() => setCall(undefined), 3000); return () => clearTimeout(timer);
  }, [call]);
  useEffect(() => {
    const beep = () => {
      const context = audio.current;
      if (!context || context.state !== 'running' || quiet || (call?.volume ?? data.settings.volume) === 0) return;
      const oscillator = context.createOscillator(); const gain = context.createGain();
      oscillator.type = 'sine'; oscillator.frequency.value = 740;
      gain.gain.setValueAtTime(0, context.currentTime); gain.gain.linearRampToValueAtTime((call?.volume ?? data.settings.volume) * 0.09, context.currentTime + 0.02); gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.35);
      oscillator.connect(gain); gain.connect(context.destination); oscillator.start(); oscillator.stop(context.currentTime + 0.4);
    };
    if (call?.status !== 'ringing' || call.direction !== 'incoming') return;
    beep(); const timer = setInterval(beep, 1800); return () => clearInterval(timer);
  }, [call?.status, call?.direction, call?.volume, data.settings.volume, quiet]);
  useEffect(() => {
    if (isPreview) return;
    let cancelled = false;
    // The NUI page loads immediately at resource start, but the client script can still be
    // mid-registration at that exact moment â€” retry the handshake instead of failing once.
    void (async () => {
      let lastError: unknown;
      for (let attempt = 0; attempt < 20 && !cancelled; attempt++) {
        try { await nui('phone:ready'); return; } catch (error) { lastError = error; await new Promise(resolve => setTimeout(resolve, 500)); }
      }
      if (!cancelled) console.error('[qbphone] UI handshake failed after multiple attempts', lastError);
    })();
    return () => { cancelled = true; };
  }, []);
  const enableAudio = () => { audio.current ??= new AudioContext(); void audio.current.resume(); };
  const available = (id: AppId) => launchApps.has(id) && device?.capabilities[id] !== false;
  const gridEligible = (item: { id: AppId }) => item.id !== 'store' && item.id !== 'phone' && item.id !== 'messages' && item.id !== 'contacts' && item.id !== 'camera' && item.id !== 'settings';
  const gridBase = apps.filter(gridEligible).filter(item => available(item.id));
  const gridIds = mergeOrder(data.settings.appOrder, gridBase.map(item => item.id));
  const homeApps = gridIds.map(id => iconOf(id));
  const dockIds = mergeOrder(data.settings.dockOrder, ['phone', 'messages', 'contacts', available('camera') ? 'camera' : 'gallery'] as AppId[]);
  // Server turns this off with Config.HomeScreen.allowReorder; the preview and older servers leave it on.
  const reorderAllowed = device?.homeReorder !== false;
  const saveOrder = (patch: Partial<typeof data.settings>) => {
    const settings = { ...data.settings, ...patch };
    updateData({ ...data, settings });
    void (async () => { try { updateData(await api('settings', settings)); } catch (e) { setToast(e instanceof Error ? e.message : 'Could not save the app order'); } })();
  };
  const reorder = (zone: 'grid' | 'dock', from: AppId, to: AppId) => {
    const current = zone === 'dock' ? dockIds : gridIds;
    const next = moveItem(current, from, to);
    if (next.join() !== current.join()) saveOrder(zone === 'dock' ? { dockOrder: next } : { appOrder: next });
  };
  // Pointer events instead of HTML5 drag-and-drop (unreliable in CEF): press and hold an icon to start
  // arranging, or press one straight away while arranging. Hovering a page dot turns the page.
  const beginPress = (e: ReactPointerEvent<HTMLButtonElement>, id: AppId, zone: 'grid' | 'dock') => {
    if (!reorderAllowed || e.button !== 0 || dragCleanup.current) return;
    const startX = e.clientX, startY = e.clientY;
    let active = false, over: AppId | null = null, timer: number | undefined;
    const activate = (byLongPress: boolean) => { active = true; if (byLongPress) suppressClick.current = true; setEditing(true); setDragId(id); setOverId(null); };
    const move = (ev: PointerEvent) => {
      const travelled = Math.hypot(ev.clientX - startX, ev.clientY - startY) > MOVE_TOLERANCE;
      if (!active) { if (travelled) end(false); return; }
      ev.preventDefault();
      if (travelled) suppressClick.current = true;
      const hit = document.elementFromPoint(ev.clientX, ev.clientY);
      const dot = hit?.closest<HTMLElement>('[data-home-page]');
      if (dot && zone === 'grid') setHomePage(Number(dot.dataset.homePage));
      const icon = hit?.closest<HTMLElement>('[data-app-id]');
      const next = icon && icon.dataset.zone === zone && icon.dataset.appId !== id ? icon.dataset.appId as AppId : null;
      if (next !== over) { over = next; setOverId(next); }
    };
    const up = () => end(true);
    const cancel = () => end(false);
    const end = (drop: boolean) => {
      window.clearTimeout(timer);
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
      dragCleanup.current = null;
      if (active) { if (drop && over) reorder(zone, id, over); setDragId(null); setOverId(null); }
      window.setTimeout(() => { suppressClick.current = false; }, 60);
    };
    window.addEventListener('pointermove', move, { passive: false });
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    dragCleanup.current = () => end(false);
    if (editing) activate(false); else timer = window.setTimeout(() => activate(true), LONG_PRESS_MS);
  };
  const iconClick = (id: AppId) => { if (suppressClick.current) { suppressClick.current = false; return; } if (editing) setEditing(false); else navigate(id); };
  useEffect(() => () => dragCleanup.current?.(), []);
  useEffect(() => { if (app !== 'home' || !reorderAllowed) { setEditing(false); setDragId(null); setOverId(null); } }, [app, reorderAllowed]);
  const toggleQuiet = () => {
    if (quiet && !data.settings.dnd) { notify(`Quiet hours are on until ${data.settings.dndTo}. Change them in Settings.`); return; }
    const settings = { ...data.settings, dnd: !data.settings.dnd };
    updateData({ ...data, settings });
    void run(async () => { updateData(await api('settings', settings)); });
  };
  const pageCount = Math.max(1, Math.ceil(homeApps.length / (fold && !folded ? 16 : 12)));
  const pageSize = fold && !folded ? 16 : 12;
  const visiblePage = Math.min(homePage, pageCount - 1);
  const phoneHeight = flip ? 820 : 780;
  const phoneWidth = fold && !folded ? 690 : 370;
  const scale = Math.min(data.settings.scale, (viewport.height - (isPreview ? (viewport.width > 760 ? 180 : 150) : 40)) / phoneHeight, (viewport.width - 28) / phoneWidth);
  useEffect(() => {
    if (isPreview) return;
    const width = phoneWidth * scale;
    const height = phoneHeight * scale;
    setPhonePosition(current => {
      if (!current) return current;
      const next = {
        x: Math.min(current.x, Math.max(0, viewport.width - width)),
        y: Math.min(current.y, Math.max(0, viewport.height - height)),
      };
      return next.x === current.x && next.y === current.y ? current : next;
    });
  }, [phoneHeight, phoneWidth, scale, viewport.height, viewport.width]);
  const startPhoneDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    if (isPreview || event.button !== 0 || !phoneStage.current) return;
    const bounds = phoneStage.current.getBoundingClientRect();
    phoneDrag.current = { x: event.clientX - bounds.left, y: event.clientY - bounds.top, width: bounds.width, height: bounds.height };
    setPhonePosition({ x: bounds.left, y: bounds.top });
    event.currentTarget.setPointerCapture(event.pointerId);
  };
  const movePhone = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = phoneDrag.current;
    if (!drag) return;
    setPhonePosition({
      x: Math.max(0, Math.min(event.clientX - drag.x, viewport.width - drag.width)),
      y: Math.max(0, Math.min(event.clientY - drag.y, viewport.height - drag.height)),
    });
  };
  const stopPhoneDrag = () => { phoneDrag.current = null; };
  const meta = appCopy(app);
  const active = call && ['ringing', 'active'].includes(call.status);
  const unread = (id: AppId) => notifications.filter(n => n.app === id).reduce((total, n) => total + (n.count ?? 1), 0);
  const notificationCard = (n: Notification) => <><NotificationIcon id={n.app} /><span><strong>{data.contacts.find(c => c.number === n.title)?.name ?? n.title}</strong><small>{n.body}</small></span>{n.count && n.count > 1 && <b className="notification-count">{n.count}</b>}{n.at && <time>{new Date(n.at).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' })}</time>}</>;
  const lock = () => run(async () => { const value = await api('lock', {}); setDevice(value); setPin(''); setApp('home'); });
  const unlock = (event: React.FormEvent) => { event.preventDefault(); void run(async () => { try { const value = await api('unlock', { pin }); setDevice(value); setPin(''); setLockError(''); } catch (e) { setLockError((e as Error).message); setPin(''); } }); };
  const content = () => {
    switch (app) {
      case 'custom': return <CustomAppScreen id={target} />;
      case 'phone': return <PhoneScreen target={target} />;
      case 'contacts': return <ContactsScreen />;
      case 'messages': return <MessagesScreen target={target} />;
      case 'mail': return <MailScreen target={target} />;
      case 'banking': return <BankScreen />;
      case 'social': return <PulseScreen />;
      case 'classifieds': return <FeedScreen />;
      case 'notes': return <NotesScreen />;
      case 'camera': return <GalleryScreen camera />;
      case 'gallery': return <GalleryScreen />;
      case 'gps': return <GPSScreen />;
      case 'services': return <ServicesScreen />;
      case 'property': return <PropertyScreen />;
      case 'vehicles': return <VehiclesScreen />;
      case 'flash': return <FlashScreen />;
      case 'music': return <MusicScreen />;
      case 'clock': return <ClockScreen />;
      case 'weather': return <WeatherScreen />;
      case 'calculator': return <CalculatorScreen />;
      case 'settings': return <SettingsScreen handsetPanel={view=><HandsetPanel view={view} onReload={reloadHandset} previewModel={model} onPreviewModel={choosePreviewModel} />} />;
      case 'store': return <StoreScreen />;
      case 'moderation': return <ModerationScreen />;
      default: return null;
    }
  };
  const toggleCoverMusic = () => {
    const existing = screenRef.current?.querySelector<HTMLAudioElement>('audio');
    const station = data.stations.find(item => /^https:\/\//i.test(item.url) && !/youtube\.com|youtu\.be|soundcloud\.com/i.test(item.url));
    const player = existing || coverAudio.current || (station ? new Audio(station.url) : undefined);
    if (!player) { notify('Save a direct HTTPS audio station in Sound first.'); return; }
    if (!existing) coverAudio.current = player;
    player.volume = data.settings.volume;
    if (player.paused) void player.play().then(() => setCoverPlaying(true)).catch(() => notify('This audio stream could not play.'));
    else { player.pause(); setCoverPlaying(false); }
  };
  const choosePreviewModel = useCallback((nextModel: 'standard' | 'flip' | 'fold') => {
    if (!isPreview) return;
    stopVideo(); setFolded(nextModel === 'fold'); setCoverCamera(false);
    setDevice(current => current ? { ...current, model: nextModel, data: { ...normalizeData(current.data), settings: { ...normalizeData(current.data).settings, phoneStyle:nextModel, name: nextModel === 'standard' ? 'Orchard One' : nextModel === 'flip' ? 'Circuit Flip' : 'Atlas Fold' } } } : current);
  },[stopVideo]);
  return <div className={isPreview ? 'preview' : 'game'} onPointerDown={enableAudio}>
    {isPreview && <><header className="preview-header"><a className="brand" href="#" onClick={e => { e.preventDefault(); navigate('home'); }}>THREE <span>( PHONE )</span></a><span className="preview-build"><i />THREE HANDSETS <span>/</span> 002</span></header><aside className="preview-intro"><p className="eyebrow"><span className="red-dot" />LESS NOISE. MORE LIFE.</p><h1>Your city.<br />Your people.<br /><span>Your phone.</span></h1><p className="intro-description">Everything you need to feel connected.<br />Nothing to get in the way.</p><div className="intro-rule" /><div className="preview-features"><div><span>01</span><p>Made for the moments<br />between the missions.</p></div><div><span>02</span><p>One device. Your number.<br />A whole city within reach.</p></div></div><div className="preview-handsets" aria-label="Preview handset model">{(['standard', 'flip', 'fold'] as const).map(value => <button key={value} aria-pressed={model === value} onClick={() => choosePreviewModel(value)}>{value === 'standard' ? 'Orchard One' : value === 'flip' ? 'Circuit Flip' : 'Atlas Fold'}</button>)}</div><div className="preview-controls"><button onClick={() => { if (!shown) apply(previewBootstrap()); else void lock(); }}><LockKeyhole size={15} />{shown ? 'Lock phone' : 'Open phone'}</button><button onClick={() => { if (!shown) apply(previewBootstrap()); previewIncoming(); }}><PhoneIncoming size={15} />Try a call</button><button onClick={resetPreview} aria-label="Reset preview data"><SlidersHorizontal size={15} />Reset</button></div><p className="demo-caption">INTERACTIVE PREVIEW / SAMPLE DATA</p></aside><footer className="preview-footer"><span>DESIGNED TO GET OUT OF YOUR WAY.</span><span>LOS SANTOS <ArrowUpRight size={13} /></span></footer></>}
    {(serviceRequest || serviceResult) && <div ref={serviceDialog} className="phone-service-consent" role="alertdialog" aria-modal="true" aria-label={serviceRequest ? 'Approve mobile service' : 'Mobile service result'}><div><ShieldCheck size={28} /><h2>{serviceRequest ? serviceRequest.label : 'Mobile service'}</h2>{serviceRequest ? <><p>A technician wants to perform <strong>{({buy:'a purchase',replaceSim:'a SIM replacement',recoverCloud:'cloud account recovery',resell:'handset resale',insertSim:'SIM insertion',removeSim:'SIM removal'} as Record<string,string>)[serviceRequest.operation] || serviceRequest.operation}</strong> for your character. The configured fee or resale payout applies.</p><div className="hs-actions"><button className="hs-button" autoFocus disabled={busy} onClick={() => void run(async () => { const id = serviceRequest.id; await nui('handset:action', { op: 'consent', id, accept: false }); setServiceRequest(undefined); if (!shown && !serviceOpen) void nui('close'); })}>Decline</button><button className="hs-button hs-primary" disabled={busy} onClick={() => void run(async () => { const id = serviceRequest.id; const reply = await nui<{ok:boolean;error?:string|{message?:string}}>('handset:action', { op: 'consent', id, accept: true }); if (!reply.ok) throw new Error(typeof reply.error === 'string' ? reply.error : reply.error?.message || 'Service could not complete'); setServiceRequest(undefined); })}>Accept service</button></div></> : <><p>{serviceResult?.message}</p>{serviceResult?.recoveryCode && <><p>Save these details now. Your old recovery code no longer works.</p><label>Cloud account<code tabIndex={0}>{serviceResult.accountId}</code></label><label>Recovery code<code tabIndex={0}>{serviceResult.recoveryCode}</code></label></>}<button className="hs-button hs-primary" onClick={() => { setServiceResult(undefined); if (!shown && !serviceOpen) void nui('close'); }}>Done</button></>}</div></div>}
    {serviceOpen && <div className="phone-service-overlay" role="dialog" aria-modal="true" aria-label="Mobile shop services"><header><span>MOBILE SERVICES</span><button className="icon-button" onClick={close} aria-label="Close mobile services"><X size={20} /></button></header><main><HandsetPanel onReload={() => undefined} /></main></div>}
    <div ref={phoneStage} className="phone-stage" style={!isPreview && phonePosition ? { left: phonePosition.x, top: phonePosition.y, right: 'auto', bottom: 'auto' } : undefined}>
      {!shown && isPreview && <button className="reopen" onClick={() => apply(previewBootstrap())}><Power size={24} />Open phone</button>}
      {shown && device && <div className="phone-scale" style={{ width: phoneWidth * scale, height: phoneHeight * scale }}><div ref={phoneRef} className={`phone handset-${model} ${flip ? 'style-flip' : ''} ${fold ? 'phone-fold' : ''} ${fold && !folded ? 'is-unfolded' : ''} ${fold && folded ? 'folded' : ''} ${flip && folded ? 'is-folded' : ''} ${unfolding ? 'is-unfolding' : ''} ${app === 'home' ? 'on-home' : ''} ${hiddenCapture ? 'capture-hidden' : ''} theme-${data.settings.theme || 'kora_core'}`} style={{ '--phone-scale': scale, '--handset-width': `${phoneWidth}px` } as CSSProperties}>
        <div className="side-key volume-up" /><div className="side-key volume-down" /><div className="side-key power-key" />
        <div ref={screenRef} inert={flip && folded} aria-hidden={flip && folded} style={handsetThemeTokens(handsetPalette,data.settings.wallpaper) as CSSProperties} className={`phone-screen ${!locked && !data.settings.setupComplete ? 'in-setup' : locked || app === 'home' ? 'show-wallpaper' : ''} ${handsetPalette.dark ? 'theme-dark' : ''} theme-${handsetPalette.id} wallpaper-${data.settings.wallpaper} icons-${handsetIconStyle(model,data.settings.iconStyle)}`}>
          {(locked || app === 'home') && data.settings.wallpaper === 'custom' && data.settings.wallpaperUrl && <PhotoImage src={data.settings.wallpaperUrl} className="custom-wallpaper" />}
          <div className="status-bar" onPointerDown={startPhoneDrag} onPointerMove={movePhone} onPointerUp={stopPhoneDrag} onPointerCancel={stopPhoneDrag}><span className="status-time">{time}</span><div className="camera-dot" /><span className="status-icons">{quiet && <Moon size={12} aria-label="Do Not Disturb is on" />}<Signal size={13} /><Wifi size={14} /><BatteryFull size={17} /></span></div>
          <PhoneContext.Provider value={{ device, data, updateData, navigate, notify, run, busy, setCall, setHasPin: value => setDevice(current => current ? { ...current, hasPin: value } : current), revision }}>
            {locked ? <div className="lock-screen"><LockKeyhole size={19} /><p>{date.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })}</p><div className={`handset-clock ${model === 'standard' ? 'nothing-clock' : ''}`} aria-label={model === 'standard' ? undefined : time}>{model === 'standard' ? <DotClock value={time} /> : time}</div><div className="handset-lock-brand"><Smartphone size={34} strokeWidth={1} /><span>{brand}</span></div>{active && <div className="locked-call"><PhoneIncoming size={19} /><div><strong>Incoming call</strong><small>{call.number} Â· Unlock to answer</small></div></div>}<form onSubmit={unlock} className="unlock-form">{device.hasPin && <input autoFocus type="password" aria-label="Phone PIN" inputMode="numeric" pattern="[0-9]{4,8}" maxLength={8} required placeholder="Enter PIN" autoComplete="off" value={pin} onChange={e => setPin(e.target.value)} />}{lockError && <p className="pin-error" role="alert">{lockError}</p>}<button className="unlock-button" disabled={busy}><Fingerprint size={28} /><span>{device.hasPin ? 'Unlock phone' : 'Make yourself at home'}</span><ArrowRight size={17} /></button></form><button type="button" className="face-unlock" disabled={busy} onClick={() => void run(async () => { const response = await nui<{ok:boolean;error?:string|{message?:string}}>('handset:action', { op: 'faceUnlock' }); if (!response.ok) throw new Error(typeof response.error === 'string' ? response.error : response.error?.message || 'Face ID did not recognise you'); await reloadHandset(); })}><Fingerprint size={18} />Use Face ID</button><small className="lock-bottom">{brand} / YOUR WORLD, CONNECTED</small></div>
              : !data.settings.setupComplete ? <SetupScreen /> : app === 'home' ? <main className="home-screen"><div className="home-top"><span className="eyebrow">{date.toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short' }).toUpperCase()}</span><div>{reorderAllowed && <button className={`icon-button ${editing ? 'active' : ''}`} aria-label={editing ? 'Done arranging apps' : 'Arrange apps'} onClick={() => { setEditing(!editing); setDragId(null); setOverId(null); }}>{editing ? <Check size={17} /> : <SlidersHorizontal size={16} />}</button>}<button className={`icon-button ${quiet ? 'active' : ''}`} aria-label={quiet ? 'Turn off Do Not Disturb' : 'Turn on Do Not Disturb'} aria-pressed={quiet} onClick={toggleQuiet}><Moon size={16} /></button><button className="icon-button" aria-label="Notifications" onClick={() => setShowNotifications(!showNotifications)}><Bell size={17} />{notifications.length > 0 && <i className="notification-dot" />}</button><button className="icon-button" aria-label="Lock phone" onClick={lock}><LockKeyhole size={16} /></button></div></div><div className={`handset-clock ${model === 'standard' ? 'nothing-clock' : ''}`} aria-label={model === 'standard' ? undefined : time}>{model === 'standard' ? <DotClock value={time} /> : time}</div><div className="home-widgets"><button className="city-widget" onClick={() => navigate(available('weather') ? 'weather' : 'gps')}><Sun size={31} strokeWidth={1.2} /><div><strong>Los Santos</strong><span>{available('weather') ? 'Your day, at a glance' : 'Find your way'}</span></div><ArrowUpRight size={14} /></button><button className="settings-widget" aria-label="Open Settings" onClick={() => navigate('settings')}><SettingsIcon size={25} strokeWidth={1.3} /><span>Make it yours</span></button></div><div className="home-section"><span>EVERYTHING, IN REACH.</span><span>( 01 )</span></div><div className="app-grid">{homeApps.slice(visiblePage * pageSize, visiblePage * pageSize + pageSize).map(item => <AppIcon key={item.id} id={item.id} badge={unread(item.id)} editing={editing} dragging={dragId === item.id} over={overId === item.id} onClick={() => iconClick(item.id)} onPointerDown={e => beginPress(e, item.id, 'grid')} />)}</div>{editing && <div className="home-edit-hint"><span>Press and drag to rearrange</span><button onClick={() => setEditing(false)}>Done</button></div>}<button className="home-note" onClick={() => navigate(notifications[0]?.app || 'messages')}><span className="note-symbol"><MessageCircle size={21} strokeWidth={1.5} /></span><span><strong>{(notifications[0] && (data.contacts.find(c => c.number === notifications[0].title)?.name ?? notifications[0].title)) || 'A little closer.'}</strong><small>{notifications[0]?.body || 'Good conversations start with hello.'}</small></span><ArrowUpRight size={16} /></button><div className="home-page-dots">{Array.from({ length: pageCount }, (_, i) => <button key={i} data-home-page={i} aria-label={`App page ${i + 1}`} aria-current={visiblePage === i ? 'page' : undefined} onClick={() => setHomePage(i)}><i /></button>)}</div><nav className="dock" aria-label="Favorite apps">{dockIds.map(id => <AppIcon key={id} id={id} dock badge={unread(id)} editing={editing} dragging={dragId === id} over={overId === id} onClick={() => iconClick(id)} onPointerDown={e => beginPress(e, id, 'dock')} />)}</nav></main>
                : <>{app !== 'social' && app !== 'flash' && <PageHeader title={meta?.label || ''} subtitle={meta?.subtitle} back={() => navigate('home')} />}<div className={`handset-app-layout ${fold && !folded && app === 'messages' ? 'expanded-messages' : ''}`}>{fold && !folded && app === 'messages' && <aside className="fold-message-list"><h3>Conversations</h3><button className="text-button" onClick={() => navigate('messages')}>New message</button>{foldInbox.map(conversation => { const number = (conversation.members || '').split(',').find(value => value !== device.number) || conversation.members || ''; return <button key={conversation.id} className={number === target ? 'selected' : ''} onClick={() => navigate('messages', number)}><strong>{data.contacts.find(contact => contact.number === number)?.name || number}</strong><small>{previewText(conversation.lastMessagePreview || conversation.last_body) || 'No messages yet'}</small></button>; })}{foldInboxMore && <button disabled={busy} onClick={()=>run(async()=>{
                  const last=foldInbox[foldInbox.length-1];const expected=device.id;
                  const rows=await api('conversations',{before:last.sortId??last.lastMessageId??last.id,cursorId:last.id});
                  if(notificationDevice.current===expected){setFoldInbox(current=>mergeConversations(current,rows));setFoldInboxMore(rows.length===50);}
                })}>Older conversations</button>}{!foldInbox.length && <p>Your conversations will appear here.</p>}</aside>}<main className={`app-content ${app === 'flash' || app === 'social' ? 'app-content-social' : ''}`} key={`${device.id}-${app}-${target}`}>{content()}</main></div></>}
            {showNotifications && !locked && <div className="notification-shade"><div className="section-heading"><h3>Notifications</h3><span className="shade-actions">{notifications.length > 0 && <button className="text-button" onClick={() => markRead(notifications)}>Clear all</button>}<button className="icon-button" aria-label="Close notifications" onClick={() => setShowNotifications(false)}><X size={18} /></button></span></div>{notifications.length ? notifications.map((notification, i) => <button key={i} className="notification-card" onClick={() => { navigate(notification.app); markRead([notification]); }}>{notificationCard(notification)}</button>) : <div className="notifications-empty"><Check size={27} /><h3>All caught up.</h3><p>A little quiet looks good on you.</p></div>}{earlier.length > 0 && <><div className="section-heading earlier-heading"><h3>Earlier</h3><button className="text-button" onClick={() => setEarlier([])}>Clear history</button></div>{earlier.map((notification, i) => <button key={i} className="notification-card is-earlier" onClick={() => navigate(notification.app)}>{notificationCard(notification)}</button>)}</>}</div>}
            {call && <div className={`call-screen ${videoOn || remoteVideo ? 'has-video' : ''}`}><p className="eyebrow">{brand} / PHONE</p><span className="call-avatar"><PhotoImage src={data.contacts.find(contact => contact.number === call.number)?.photo} className="call-photo" alt="Caller photo" /></span><h2>{data.contacts.find(contact => contact.number === call.number)?.name || call.number}</h2><p>{call.number}</p><span className="call-status"><i />{call.status === 'ringing' ? (call.direction === 'incoming' ? 'Incoming call' : 'Callingâ€¦') : call.status === 'active' ? muted ? 'Connected Â· Microphone muted' : 'Connected' : call.status}</span>
              {call.status === 'active' && (videoOn || remoteVideo) ? <div className="call-video"><video ref={remoteVideoRef} autoPlay playsInline className="remote-video" /><video ref={localVideoRef} autoPlay playsInline muted className="local-video" /></div> : <div className="call-orbits"><div /><div /><div /></div>}
              {videoRequest && <div className="video-invitation" role="alertdialog" aria-label="Video call invitation"><Video size={20} /><strong>Switch to video?</strong><p>Your game camera starts only if you accept.</p><button className="primary" disabled={busy} onClick={() => void run(() => videoControl('accept'))}>Accept video</button><button className="text-button" disabled={busy} onClick={() => void run(() => videoControl('decline'))}>Keep voice</button></div>}
              {videoPending && <p className="video-pending" role="status">Waiting for video acceptanceâ€¦</p>}
              <div className="call-controls">{call.status === 'ringing' && call.direction === 'incoming' && <button className="call-button accept" aria-label="Answer call" disabled={busy} onClick={() => run(async () => setCall(await api('answer', { id: call.id })))}><Phone size={26} /></button>}
              {call.status === 'active' && <button className={`icon-button ${muted ? 'active' : ''}`} aria-label={muted ? 'Unmute microphone' : 'Mute microphone'} aria-pressed={muted} disabled={busy} onClick={() => void run(() => videoControl('mute', !muted))}>{muted ? <MicOff size={22} /> : <Mic size={22} />}</button>}
              {call.status === 'active' && device.video && <button className="icon-button" aria-label={videoOn || videoPending ? 'Stop video' : 'Request video'} disabled={busy || videoRequest} onClick={() => void run(() => videoControl(videoOn || videoPending ? 'stop' : 'request'))}>{videoOn || videoPending ? <VideoOff size={22} /> : <Video size={22} />}</button>}
              {videoOn && <button className="icon-button" aria-label="Switch selfie or rear camera" disabled={busy} onClick={() => void run(async () => { await gameVideo.current?.flip(); })}><SwitchCamera size={22} /></button>}
              {active ? <button className="call-button" aria-label="End call" disabled={busy} onClick={() => run(async () => { await api('hangup', { id: call.id, reject: call.direction === 'incoming' && call.status === 'ringing' }); stopVideo(); setCall(undefined); })}><PhoneOff size={26} /></button> : <button className="primary" onClick={() => setCall(undefined)}>Done</button>}</div><small>{active ? 'YOUR WORLD, CONNECTED.' : 'CALL ENDED.'}</small></div>}
          </PhoneContext.Provider>
          {alert && !folded && !showNotifications && <HeadsUp key={alert.at} alert={{ ...alert, title: data.contacts.find(c => c.number === alert.title)?.name ?? alert.title }} locked={locked} onDismiss={() => setAlert(undefined)} onOpen={() => { if (!locked) { navigate(alert.app); markRead([alert]); } setAlert(undefined); }} />}
          {toast && <div className={`toast ${model === 'standard' ? 'nothing-status' : ''} ${locked ? 'toast-top' : app === 'home' ? 'toast-home' : ''}`} role="status"><span>{toast}</span><button aria-label="Dismiss notification" onClick={() => setToast('')}><X size={14} /></button></div>}
          {busy && <div className="busy-line" role="progressbar" aria-label="Working" />}
          <nav className="system-nav" aria-label="Phone navigation"><button aria-label="Back to home" onClick={() => !locked && navigate('home')}><ChevronLeft size={19} /></button><button className="home-indicator" aria-label="Home" onClick={() => !locked && navigate('home')}><span /></button><button aria-label="Close phone" onClick={close}><ArrowDown size={17} /></button></nav>
        </div>
        {flip && <><div className="flip-crease" aria-hidden="true" /><div className="flip-hinge left" /><div className="flip-hinge right" />
          {(folded || unfolding) && <div className={`flip-cover ${caseHasArt ? 'has-art' : ''} ${folded ? '' : 'unfolding'}`}><CoverBackdrop settings={data.settings} /><div className="cover-lenses"><i /><i /></div><span className="eyebrow">{'CIRCUIT / FLIP'}</span><div className="cover-display"><div className="handset-clock" aria-label={time}>{time}</div><p>{date.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' })}</p><div className="cover-notice"><Bell size={16} /><span>{active ? (call?.status === 'active' ? 'Call in progress' : call?.direction === 'incoming' ? 'Incoming call' : 'Callingâ€¦') : notifications.length ? `${notifications.length} notification${notifications.length === 1 ? '' : 's'}` : 'All caught up'}</span></div>{coverCamera && !active && <canvas ref={coverCanvas} className="cover-camera-preview" aria-label="Game camera preview" />}<div className="cover-quick-actions">{active ? <>{call?.status === 'ringing' && call.direction === 'incoming' && <button aria-label="Answer call on cover" onClick={() => void run(async () => setCall(await api('answer', { id: call.id })))}><Phone size={18} /></button>}{call?.status === 'active' && <button aria-label={muted ? 'Unmute call' : 'Mute call'} onClick={() => void run(() => videoControl('mute', !muted))}>{muted ? <MicOff size={18} /> : <Mic size={18} />}</button>}<button className="cover-hangup" aria-label="End call on cover" onClick={() => void run(async () => { if (!call) return; await api('hangup', { id: call.id, reject: call.status === 'ringing' && call.direction === 'incoming' }); stopVideo(); setCall(undefined); })}><PhoneOff size={18} /></button></> : <><button aria-label="Toggle cover camera preview" disabled={locked || isPreview} aria-pressed={coverCamera} onClick={() => setCoverCamera(value => !value)}><Camera size={18} /></button><button aria-label={coverPlaying ? 'Pause music' : 'Play music'} disabled={locked} onClick={toggleCoverMusic}>{coverPlaying ? <Pause size={18} /> : <Play size={18} />}</button></>}</div><small>{active && videoOn ? 'VIDEO PAUSED WHILE CLOSED' : `UNFOLD TO ${locked ? 'UNLOCK' : 'OPEN'}`}</small></div><button className="cover-open" onClick={unfold}>Unfold phone <ArrowUpRight size={17} /></button><button className="cover-close" onClick={close}>Put away</button></div>}
          <button className="fold-control" disabled={busy} aria-label={folded ? 'Unfold phone' : 'Fold phone'} onClick={() => { if (folded) unfold(); else { snapshotForFold(); setShowNotifications(false); setFolded(true); } }}>{folded ? 'OPEN' : 'FOLD'}</button>
        </>}
        {fold && <><div className="fold-spine" aria-hidden="true" /><button className="fold-control" disabled={busy} aria-label={folded ? 'Open fold into tablet' : 'Fold to outer screen'} onClick={() => setFolded(value => !value)}>{folded ? 'EXPAND' : 'FOLD'}</button></>}
      </div></div>}
      {isPreview && shown && <div className="phone-caption"><span><i /> CONNECTED TO YOUR WORLD</span><span>{brand} / {model.toUpperCase()}</span></div>}
    </div>
  </div>;
}
