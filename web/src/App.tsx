import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { CSSProperties, ComponentType, DragEvent } from 'react';
import { AlarmClock, Aperture, ArrowDown, ArrowRight, ArrowUpRight, BatteryFull, Bell, Calculator, Camera, Car, Check, ChevronLeft, CloudSun, ContactRound, CreditCard, Fingerprint, House, Image, LockKeyhole, Mail, MapPin, MessageCircle, Moon, Music, Phone, PhoneIncoming, PhoneOff, Power, Radio, Settings as SettingsIcon, ShieldAlert, ShieldCheck, Signal, SlidersHorizontal, StickyNote, Store as StoreIcon, Sun, Tag, Video, VideoOff, Wifi, X } from 'lucide-react';
import { adaptBootstrap, adaptLiveCall, api, isPreview, nui, sendSignal } from './api';
import { previewBootstrap, previewIncoming, resetPreview } from './mock';
import { normalizeData } from './types';
import type { Alarm, AppId, Bootstrap, Call, DeviceData, Notification } from './types';
import { DotClock, PageHeader } from './components';
import { LockLogo, QbMark } from './LockLogo';
import { CoverBackdrop } from './CoverArt';
import { imageUrl } from './Images';
import { PhoneContext, usePhone } from './PhoneContext';
import { appCopy } from './locales';
import { StoreScreen } from './Store';
import { PhotoImage } from './Images';
import { isDarkTheme } from './themes';
import { SetupScreen } from './Setup';
import { isHostMessage } from './nuiEvents';
import { CustomAppScreen } from './CustomApps';
import { isOptional } from './catalog';
import { recall, remember } from './lastScreen';
import { isQuiet } from './quiet';
import type { Quiet } from './quiet';
import { previewText } from './chatTokens';
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
  if (!apps.some(item => item.id === id) || value?.capabilities[id] === false) return 'home';
  return isOptional(id) && !normalizeData(value?.data).installedApps?.includes(id) ? 'home' : id;
};
function AppIcon({ id, onClick, dock = false, badge = 0, editing = false, dragging = false, over = false, onDragStart, onDragOver, onDrop, onDragEnd }: {
  id: AppId; onClick: () => void; dock?: boolean; badge?: number; editing?: boolean; dragging?: boolean; over?: boolean;
  onDragStart?: (e: DragEvent<HTMLButtonElement>) => void; onDragOver?: (e: DragEvent<HTMLButtonElement>) => void; onDrop?: (e: DragEvent<HTMLButtonElement>) => void; onDragEnd?: (e: DragEvent<HTMLButtonElement>) => void;
}) {
  const { device } = usePhone();
  const { icon: Icon } = iconOf(id);
  const { label } = appCopy(id, device.locale);
  return <button draggable={editing} onDragStart={onDragStart} onDragOver={onDragOver} onDrop={onDrop} onDragEnd={onDragEnd} onClick={onClick} className={`app-icon ${dock ? 'dock-icon' : ''} app-${id} ${editing ? 'jiggle' : ''} ${dragging ? 'dragging' : ''} ${over ? 'drop-target' : ''}`} aria-label={`Open ${label}`}><span><Icon size={25} strokeWidth={1.6} /></span>{badge > 0 && <b className="app-badge" aria-label={`${badge} new`}>{badge > 9 ? '9+' : badge}</b>}{!dock && <small>{label}</small>}{editing && <i className="edit-handle" aria-hidden="true" />}</button>;
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
  const [folded, setFolded] = useState(false);
  const [unfolding, setUnfolding] = useState(false);
  // Keep the cover mounted while it swings open, so unfolding plays the fold in reverse.
  const unfold = () => { snapshotForUnfold(); setFolded(false); setUnfolding(true); window.setTimeout(() => setUnfolding(false), 800); };
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
  const peerConnection = useRef<RTCPeerConnection | undefined>(undefined); const localStream = useRef<MediaStream | undefined>(undefined);
  const localVideoRef = useRef<HTMLVideoElement>(null); const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const date = useTime();
  const callRef = useRef<Call | undefined>(undefined); callRef.current = call;
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
  const navigate = useCallback((requested: AppId, destination = '') => { const id: AppId = requested === 'home' || requested === 'custom' || apps.some(item => item.id === requested) ? requested : 'home'; setApp(isOptional(id) && !data.installedApps?.includes(id) ? 'store' : id); setTarget(destination); setShowNotifications(false); setHomePage(0); setEditing(false); setDragId(null); setOverId(null); }, [data.installedApps]);
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
    const mine = (n: Notification) => !n.deviceId || n.deviceId === value.id;
    setFolded(false);
    setDevice(value); setShown(true); setApp(lastApp(value)); setTarget(''); setPin(''); setLockError(''); setNotifications(list => list.filter(mine)); setEarlier(list => list.filter(mine)); setToast(''); setAlert(undefined); setCall(value.call); setHiddenCapture(false); setShowNotifications(false); setEditing(false); setDragId(null); setOverId(null);
  }, []);
  const close = useCallback(() => { void nui('close'); setAlert(undefined); setShown(false); setDevice(undefined); setPin(''); setEditing(false); setDragId(null); setOverId(null); }, []);
  const stopVideo = useCallback(() => {
    peerConnection.current?.close(); peerConnection.current = undefined;
    localStream.current?.getTracks().forEach(track => track.stop()); localStream.current = undefined;
    if (localVideoRef.current) localVideoRef.current.srcObject = null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null;
    setVideoOn(false); setRemoteVideo(false);
  }, []);
  const ensurePeer = useCallback((iceServers: RTCIceServer[]) => {
    if (peerConnection.current) return peerConnection.current;
    const connection = new RTCPeerConnection({ iceServers });
    connection.onicecandidate = event => { if (event.candidate && callRef.current?.id) sendSignal({ id: callRef.current.id, kind: 'ice', candidate: event.candidate.toJSON() }); };
    connection.ontrack = event => { setRemoteVideo(true); if (remoteVideoRef.current) remoteVideoRef.current.srcObject = event.streams[0]; };
    connection.onconnectionstatechange = () => { if (['failed', 'closed', 'disconnected'].includes(connection.connectionState)) stopVideo(); };
    peerConnection.current = connection;
    return connection;
  }, [stopVideo]);
  const startVideo = useCallback(() => run(async () => {
    if (!device?.video || !callRef.current?.id) return;
    const connection = ensurePeer(device.video.iceServers);
    const stream = await navigator.mediaDevices.getUserMedia({ video: true });
    localStream.current = stream;
    stream.getTracks().forEach(track => connection.addTrack(track, stream));
    if (localVideoRef.current) localVideoRef.current.srcObject = stream;
    setVideoOn(true);
    const offer = await connection.createOffer();
    await connection.setLocalDescription(offer);
    sendSignal({ id: callRef.current.id, kind: 'offer', sdp: offer });
  }), [device?.video, ensurePeer, run]);
  const handleVideoSignal = useCallback(async (signal: { kind?: string; sdp?: RTCSessionDescriptionInit; candidate?: RTCIceCandidateInit }) => {
    if (!device?.video || !signal || typeof signal !== 'object') return;
    if (signal.kind === 'offer' && signal.sdp) {
      const connection = ensurePeer(device.video.iceServers);
      await connection.setRemoteDescription(signal.sdp);
      const stream = localStream.current ?? await navigator.mediaDevices.getUserMedia({ video: true }).catch(() => undefined);
      if (stream) {
        localStream.current = stream;
        stream.getTracks().forEach(track => { if (!connection.getSenders().some(sender => sender.track === track)) connection.addTrack(track, stream); });
        if (localVideoRef.current) localVideoRef.current.srcObject = stream;
      }
      const answer = await connection.createAnswer();
      await connection.setLocalDescription(answer);
      if (callRef.current?.id) sendSignal({ id: callRef.current.id, kind: 'answer', sdp: answer });
      setVideoOn(true);
    } else if (signal.kind === 'answer' && signal.sdp) {
      await peerConnection.current?.setRemoteDescription(signal.sdp);
    } else if (signal.kind === 'ice' && signal.candidate) {
      await peerConnection.current?.addIceCandidate(signal.candidate).catch(() => undefined);
    }
  }, [device?.video, ensurePeer]);
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
      if (type === 'customOpen' && !locked) navigate('custom', message.app);
      if (type === 'phone:open' || type === 'open') {
        const live = message.data?.state?.activeCall;
        void api('refresh', {}).then(value => apply(live ? { ...value, call: adaptLiveCall(live) } : value)).catch(error => { void nui('close', { error: error instanceof Error ? error.message : 'Could not open phone' }); });
      }
      else if (type === 'bootstrap' && message.data) setDevice(adaptBootstrap(message.data));
      else if (type === 'phone:close' || type === 'phone:reset' || type === 'close') { setShown(false); setDevice(undefined); setPin(''); }
      else if (type === 'capture') setHiddenCapture(!!message.hidden);
      else if (type === 'phone:visibility') setHiddenCapture(message.data === false);
      else if (type === 'camera:closed') setHiddenCapture(false);
      else if (type === 'call') setCall(message.data);
      else if (type === 'calls:incoming' || type === 'calls:outgoing' || type === 'calls:accepted') setCall(adaptLiveCall(message.data));
      else if (type === 'calls:ended') {
        // An incoming call nobody answered leaves a note, even if the phone is closed.
        const ringing = callRef.current;
        if (ringing && ringing.direction === 'incoming' && ringing.id === message.data?.id && ['missed', 'cancelled'].includes(message.data?.status)) { push({ title: ringing.number, body: 'Missed call', app: 'phone' }); closedAlert(ringing.number, 'Missed call'); }
        setCall(current => current && current.id === message.data?.id ? { ...current, status: 'ended' } : current);
      }
      else if (message.type === 'videoSignal') void handleVideoSignal(message.data);
      else if (type === 'messages:read') setRevision(v => v + 1);
      else if (type === 'messages:new' && message.data && !message.data.isMine) { const sender = String(message.data.senderNumber || 'New message'); push({ title: sender, body: previewText(message.data.body), app: 'messages' }); closedAlert(sender, previewText(message.data.body)); }
      else if (type === 'mail:new' && message.data) { const sender = String(message.data.sender || 'New mail'); push({ title: sender, body: String(message.data.subject || 'New mail'), app: 'mail' }); closedAlert(sender, String(message.data.subject || 'New mail')); }
      else if (type === 'notification' || type === 'notification:push') push(message.data || {});
    };
    // With the phone closed nothing on screen can show a notification, so ask the game for one (silenced by Do Not Disturb).
    const closedAlert = (title: string, body: string) => {
      if (shownRef.current || isQuiet(quietConfig.current)) return;
      void nui('notify', { title: contactNames.current.get(title) ?? title, body });
    };
    const push = (incoming: Record<string, any>) => {
      const notification = { deviceId: String(incoming.deviceId || device?.id || ''), title: String(incoming.title || 'Notification'), body: String(incoming.body || incoming.message || ''), app: (incoming.app || 'messages') as AppId, at: Date.now() } as Notification;
      if (!incoming.deviceId || device?.id === notification.deviceId) {
        setNotifications(previous => {
          const matching = previous.find(item => item.app === notification.app && item.title === notification.title);
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
  }, [apply, device?.id, locked, navigate, handleVideoSignal]);
  useEffect(() => { if (call?.status !== 'active') stopVideo(); }, [call?.status, stopVideo]);
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.key === 'Escape' && shown) { if (app !== 'home') navigate('home'); else close(); } };
    window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key);
  }, [app, shown, close, navigate]);
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
    // mid-registration at that exact moment — retry the handshake instead of failing once.
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
  const available = (id: AppId) => device?.capabilities[id] !== false && (!isOptional(id) || !!data.installedApps?.includes(id));
  const gridEligible = (item: { id: AppId }) => item.id !== 'store' && item.id !== 'phone' && item.id !== 'messages' && item.id !== 'contacts' && item.id !== 'camera' && item.id !== 'settings';
  const gridBase = apps.filter(gridEligible).filter(item => available(item.id));
  const savedOrder = (data.settings.appOrder ?? []).filter(id => gridBase.some(item => item.id === id));
  const homeApps = [iconOf('store'), ...savedOrder.map(id => iconOf(id)), ...gridBase.filter(item => !savedOrder.includes(item.id))];
  const reorder = (from: AppId, to: AppId) => {
    if (from === to) return;
    const list = homeApps.filter(item => item.id !== 'store');
    const sourceIndex = list.findIndex(item => item.id === from);
    const targetIndex = list.findIndex(item => item.id === to);
    if (sourceIndex < 0 || targetIndex < 0) return;
    const next = [...list];
    const [moved] = next.splice(sourceIndex, 1);
    next.splice(targetIndex, 0, moved);
    const appOrder = next.map(item => item.id);
    updateData({ ...data, settings: { ...data.settings, appOrder } });
    void run(async () => { updateData(await api('settings', { ...data.settings, appOrder })); });
  };
  const toggleQuiet = () => {
    if (quiet && !data.settings.dnd) { notify(`Quiet hours are on until ${data.settings.dndTo}. Change them in Settings.`); return; }
    const settings = { ...data.settings, dnd: !data.settings.dnd };
    updateData({ ...data, settings });
    void run(async () => { updateData(await api('settings', settings)); });
  };
  const pageCount = Math.ceil(homeApps.length / 12);
  const visiblePage = Math.min(homePage, pageCount - 1);
  const flip = data.settings.phoneStyle === 'flip';
  // The flip style is the form factor; color theme stays independent.
  const phoneHeight = flip ? 820 : 780;
  const scale = Math.min(data.settings.scale, (viewport.height - (isPreview ? (viewport.width > 760 ? 180 : 150) : 40)) / phoneHeight, (viewport.width - 28) / 370);
  useEffect(() => {
    if (isPreview) return;
    const width = 370 * scale;
    const height = phoneHeight * scale;
    setPhonePosition(current => {
      if (!current) return current;
      const next = {
        x: Math.min(current.x, Math.max(0, viewport.width - width)),
        y: Math.min(current.y, Math.max(0, viewport.height - height)),
      };
      return next.x === current.x && next.y === current.y ? current : next;
    });
  }, [phoneHeight, scale, viewport.height, viewport.width]);
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
  const meta = appCopy(app, device?.locale);
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
      case 'settings': return <SettingsScreen />;
      case 'store': return <StoreScreen />;
      case 'moderation': return <ModerationScreen />;
      default: return null;
    }
  };
  return <div className={isPreview ? 'preview' : 'game'} onPointerDown={enableAudio}>
    {isPreview && <><header className="preview-header"><a className="brand" href="#" onClick={e => { e.preventDefault(); navigate('home'); }}>NOTHING <span>( PHONE )</span></a><span className="preview-build"><i />QBCORE EDITION <span>/</span> 001</span></header><aside className="preview-intro"><p className="eyebrow"><span className="red-dot" />LESS NOISE. MORE LIFE.</p><h1>Your city.<br />Your people.<br /><span>Your phone.</span></h1><p className="intro-description">Everything you need to feel connected.<br />Nothing to get in the way.</p><div className="intro-rule" /><div className="preview-features"><div><span>01</span><p>Made for the moments<br />between the missions.</p></div><div><span>02</span><p>One device. Your number.<br />A whole city within reach.</p></div></div><div className="preview-controls"><button onClick={() => { if (!shown) apply(previewBootstrap()); else void lock(); }}><LockKeyhole size={15} />{shown ? 'Lock phone' : 'Open phone'}</button><button onClick={() => { if (!shown) apply(previewBootstrap()); previewIncoming(); }}><PhoneIncoming size={15} />Try a call</button><button onClick={resetPreview} aria-label="Reset preview data"><SlidersHorizontal size={15} />Reset</button></div><p className="demo-caption">INTERACTIVE PREVIEW / SAMPLE DATA</p></aside><footer className="preview-footer"><span>DESIGNED TO GET OUT OF YOUR WAY.</span><span>LOS SANTOS <ArrowUpRight size={13} /></span></footer></>}
    <div ref={phoneStage} className="phone-stage" style={!isPreview && phonePosition ? { left: phonePosition.x, top: phonePosition.y, right: 'auto', bottom: 'auto' } : undefined}>
      {!shown && isPreview && <button className="reopen" onClick={() => apply(previewBootstrap())}><Power size={24} />Open phone</button>}
      {shown && device && <div className="phone-scale" style={{ width: 370 * scale, height: phoneHeight * scale }}><div ref={phoneRef} className={`phone ${flip ? 'style-flip' : ''} ${flip && folded ? 'is-folded' : ''} ${unfolding ? 'is-unfolding' : ''} ${app === 'home' ? 'on-home' : ''} ${app === 'gps' ? 'map-open' : ''} ${hiddenCapture ? 'capture-hidden' : ''} theme-${data.settings.theme || 'qbcore'}`} style={{ '--phone-scale': scale } as CSSProperties}>
        <div className="side-key volume-up" /><div className="side-key volume-down" /><div className="side-key power-key" />
        <div ref={screenRef} inert={flip && folded} aria-hidden={flip && folded} className={`phone-screen ${!locked && !data.settings.setupComplete ? 'in-setup' : locked || app === 'home' ? 'show-wallpaper' : ''} ${isDarkTheme(data.settings.theme || 'qbcore') ? 'theme-dark' : ''} theme-${data.settings.theme || 'qbcore'} wallpaper-${data.settings.wallpaper} icons-${data.settings.iconStyle ?? 'circle'}`}>
          {(locked || app === 'home') && data.settings.wallpaper === 'custom' && data.settings.wallpaperUrl && <PhotoImage src={data.settings.wallpaperUrl} className="custom-wallpaper" />}
          <div className="status-bar" onPointerDown={startPhoneDrag} onPointerMove={movePhone} onPointerUp={stopPhoneDrag} onPointerCancel={stopPhoneDrag}><span className="status-time">{time}{data.settings.theme === 'qbcore' && <QbMark size={10} />}</span><div className="camera-dot" /><span className="status-icons">{quiet && <Moon size={12} aria-label="Do Not Disturb is on" />}<Signal size={13} /><Wifi size={14} /><BatteryFull size={17} /></span></div>
          <PhoneContext.Provider value={{ device, data, updateData, navigate, notify, run, busy, setCall, setHasPin: value => setDevice(current => current ? { ...current, hasPin: value } : current), revision }}>
            {locked ? <div className="lock-screen"><LockKeyhole size={19} /><p>{date.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' })}</p><DotClock value={time} /><LockLogo brand={data.settings.theme === 'qbcore' ? 'qbcore' : 'nothing'} />{active && <div className="locked-call"><PhoneIncoming size={19} /><div><strong>Incoming call</strong><small>{call.number} · Unlock to answer</small></div></div>}<form onSubmit={unlock} className="unlock-form">{device.hasPin && <input autoFocus type="password" aria-label="Phone PIN" inputMode="numeric" pattern="[0-9]{4,8}" maxLength={8} required placeholder="Enter PIN" autoComplete="off" value={pin} onChange={e => setPin(e.target.value)} />}{lockError && <p className="pin-error" role="alert">{lockError}</p>}<button className="unlock-button" disabled={busy}><Fingerprint size={28} /><span>{device.hasPin ? 'Unlock phone' : 'Make yourself at home'}</span><ArrowRight size={17} /></button></form><small className="lock-bottom">NOTHING / EVERYTHING YOU NEED</small></div>
              : !data.settings.setupComplete ? <SetupScreen /> : app === 'home' ? <main className="home-screen"><div className="home-top"><span className="eyebrow">{data.settings.theme === 'qbcore' && <QbMark size={11} />}{date.toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short' }).toUpperCase()}</span><div><button className={`icon-button ${editing ? 'active' : ''}`} aria-label={editing ? 'Done arranging apps' : 'Arrange apps'} onClick={() => { setEditing(!editing); setDragId(null); setOverId(null); }}>{editing ? <Check size={17} /> : <SlidersHorizontal size={16} />}</button><button className={`icon-button ${quiet ? 'active' : ''}`} aria-label={quiet ? 'Turn off Do Not Disturb' : 'Turn on Do Not Disturb'} aria-pressed={quiet} onClick={toggleQuiet}><Moon size={16} /></button><button className="icon-button" aria-label="Notifications" onClick={() => setShowNotifications(!showNotifications)}><Bell size={17} />{notifications.length > 0 && <i className="notification-dot" />}</button><button className="icon-button" aria-label="Lock phone" onClick={lock}><LockKeyhole size={16} /></button></div></div><DotClock value={time} /><div className="home-widgets"><button className="city-widget" onClick={() => navigate(available('weather') ? 'weather' : 'gps')}><Sun size={31} strokeWidth={1.2} /><div><strong>Los Santos</strong><span>{available('weather') ? 'Your day, at a glance' : 'Find your way'}</span></div><ArrowUpRight size={14} /></button><button className="settings-widget" aria-label="Open Settings" onClick={() => navigate('settings')}><SettingsIcon size={25} strokeWidth={1.3} /><span>Make it yours</span></button></div><div className="home-section"><span>EVERYTHING, IN REACH.</span><span>( 01 )</span></div><div className="app-grid">{homeApps.slice(visiblePage * 12, visiblePage * 12 + 12).map(item => <AppIcon key={item.id} id={item.id} badge={unread(item.id)} editing={editing} dragging={dragId === item.id} over={overId === item.id} onClick={() => editing ? setEditing(false) : navigate(item.id)} onDragStart={() => setDragId(item.id)} onDragOver={e => { if (editing && dragId && dragId !== item.id) { e.preventDefault(); setOverId(item.id); } }} onDrop={e => { e.preventDefault(); if (dragId) reorder(dragId, item.id); setDragId(null); setOverId(null); }} onDragEnd={() => { setDragId(null); setOverId(null); }} />)}</div>{editing && <p className="home-edit-hint">Drag to rearrange · tap check to finish</p>}<button className="home-note" onClick={() => navigate(notifications[0]?.app || 'messages')}><span className="note-symbol"><MessageCircle size={21} strokeWidth={1.5} /></span><span><strong>{(notifications[0] && (data.contacts.find(c => c.number === notifications[0].title)?.name ?? notifications[0].title)) || 'A little closer.'}</strong><small>{notifications[0]?.body || 'Good conversations start with hello.'}</small></span><ArrowUpRight size={16} /></button><div className="home-page-dots">{Array.from({ length: pageCount }, (_, i) => <button key={i} aria-label={`App page ${i + 1}`} aria-current={visiblePage === i ? 'page' : undefined} onClick={() => setHomePage(i)}><i /></button>)}</div><nav className="dock" aria-label="Favorite apps">{(['phone', 'messages', 'contacts', available('camera') ? 'camera' : 'gallery'] as AppId[]).map(id => <AppIcon key={id} id={id} dock badge={unread(id)} onClick={() => navigate(id)} />)}</nav></main>
                : <>{app !== 'social' && app !== 'flash' && <PageHeader title={meta?.label || ''} subtitle={meta?.subtitle} back={() => navigate('home')} />}<main className={`app-content ${app === 'flash' || app === 'social' ? 'app-content-social' : ''}`} key={`${device.id}-${app}-${target}`}>{content()}</main></>}
            {showNotifications && !locked && <div className="notification-shade"><div className="section-heading"><h3>Notifications</h3><span className="shade-actions">{notifications.length > 0 && <button className="text-button" onClick={() => markRead(notifications)}>Clear all</button>}<button className="icon-button" aria-label="Close notifications" onClick={() => setShowNotifications(false)}><X size={18} /></button></span></div>{notifications.length ? notifications.map((notification, i) => <button key={i} className="notification-card" onClick={() => { navigate(notification.app); markRead([notification]); }}>{notificationCard(notification)}</button>) : <div className="notifications-empty"><Check size={27} /><h3>All caught up.</h3><p>A little quiet looks good on you.</p></div>}{earlier.length > 0 && <><div className="section-heading earlier-heading"><h3>Earlier</h3><button className="text-button" onClick={() => setEarlier([])}>Clear history</button></div>{earlier.map((notification, i) => <button key={i} className="notification-card is-earlier" onClick={() => navigate(notification.app)}>{notificationCard(notification)}</button>)}</>}</div>}
            {call && <div className="call-screen"><p className="eyebrow">NOTHING / PHONE</p><span className="call-avatar"><PhotoImage src={data.contacts.find(c => c.number === call.number)?.photo} className="call-photo" alt="Caller photo" /></span><h2>{data.contacts.find(contact => contact.number === call.number)?.name || call.number}</h2><p>{call.number}</p><span className="call-status"><i />{call.status === 'ringing' ? (call.direction === 'incoming' ? 'Incoming call' : 'Calling…') : call.status === 'active' ? 'Connected' : call.status}</span>{call.status === 'active' && (videoOn || remoteVideo) && <div className="call-video"><video ref={remoteVideoRef} autoPlay playsInline className="remote-video" /><video ref={localVideoRef} autoPlay playsInline muted className="local-video" /></div>}{!(call.status === 'active' && (videoOn || remoteVideo)) && <div className="call-orbits"><div /><div /><div /></div>}<div className="call-controls">{call.status === 'ringing' && call.direction === 'incoming' && <button className="call-button accept" aria-label="Answer call" disabled={busy} onClick={() => run(async () => setCall(await api('answer', { id: call.id })))}><Phone size={26} /></button>}{call.status === 'active' && device?.video && <button className="icon-button" aria-label={videoOn ? 'Turn off camera' : 'Start video'} disabled={busy} onClick={() => (videoOn ? stopVideo() : startVideo())}>{videoOn ? <VideoOff size={22} /> : <Video size={22} />}</button>}{active ?<button className="call-button" aria-label="End call" disabled={busy} onClick={() => run(async () => { await api('hangup', { id: call.id, reject: call.direction === 'incoming' && call.status === 'ringing' }); stopVideo(); setCall(undefined); })}><PhoneOff size={26} /></button> : <button className="primary" onClick={() => setCall(undefined)}>Done</button>}</div><small>{active ? 'KEEP THE CONVERSATION GOING.' : 'A LITTLE QUIET, FOR NOW.'}</small></div>}
          </PhoneContext.Provider>
          {alert && !folded && !showNotifications && <HeadsUp key={alert.at} alert={{ ...alert, title: data.contacts.find(c => c.number === alert.title)?.name ?? alert.title }} locked={locked} onDismiss={() => setAlert(undefined)} onOpen={() => { if (!locked) { navigate(alert.app); markRead([alert]); } setAlert(undefined); }} />}
          {toast && <div className={`toast ${locked ? 'toast-top' : app === 'home' ? 'toast-home' : ''}`} role="status"><span>{toast}</span><button aria-label="Dismiss notification" onClick={() => setToast('')}><X size={14} /></button></div>}
          {busy && <div className="busy-line" role="progressbar" aria-label="Working" />}
          <nav className="system-nav" aria-label="Phone navigation"><button aria-label="Back to home" onClick={() => !locked && navigate('home')}><ChevronLeft size={19} /></button><button className="home-indicator" aria-label="Home" onClick={() => !locked && navigate('home')}><span /></button><button aria-label="Close phone" onClick={close}><ArrowDown size={17} /></button></nav>
        </div>
        {flip && <><div className="flip-crease" aria-hidden="true" /><div className="flip-hinge left" /><div className="flip-hinge right" />
          {(folded || unfolding) && <div className={`flip-cover ${caseHasArt ? 'has-art' : ''} ${folded ? '' : 'unfolding'}`}><CoverBackdrop settings={data.settings} /><div className="cover-lenses"><i /><i /></div><span className="eyebrow">{data.settings.theme === 'qbcore' ? <><QbMark size={10} /> QBCORE / FLIP</> : 'NOTHING / FLIP'}</span><div className="cover-display"><DotClock value={time} /><p>{date.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' })}</p><div className="cover-notice"><Bell size={16} /><span>{active ? (call?.status === 'active' ? 'Call in progress' : call?.direction === 'incoming' ? 'Incoming call' : 'Calling…') : notifications.length ? `${notifications.length} notification${notifications.length === 1 ? '' : 's'}` : 'All caught up'}</span></div><small>UNFOLD TO {locked ? 'UNLOCK' : 'OPEN'}</small></div><button className="cover-open" onClick={unfold}>Unfold phone <ArrowUpRight size={17} /></button><button className="cover-close" onClick={close}>Put away</button></div>}
          <button className="fold-control" disabled={busy} aria-label={folded ? 'Unfold phone' : 'Fold phone'} onClick={() => folded ? unfold() : void run(async () => { const value = await api('lock', {}); snapshotForFold(); setDevice(value); setPin(''); setApp('home'); setShowNotifications(false); setFolded(true); })}>{folded ? 'OPEN' : 'FOLD'}</button>
        </>}
      </div></div>}
      {isPreview && shown && <div className="phone-caption"><span><i /> CONNECTED TO YOUR WORLD</span><span>NOTHING (1)</span></div>}
    </div>
  </div>;
}
