import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Blocks } from 'lucide-react';
import { api, isPreview, nui } from '../../api';
import { usePhone } from '../../core/PhoneContext';
import { setSdkApps, useSdkApps } from '../../core/runtimeApps';
import type { SdkApp } from '../../core/runtimeApps';
import { isHostMessage } from '../../nuiEvents';
import '../../CustomApps.css';
import { SETTINGS_EVENT, legacyEvent } from '../../sdk/legacy';
import { appUrl, createRouter, buildTheme, permissionsOf, sameTheme, originOf, push, isRecord } from '../../sdk';
import type { HostTransport, Handset, ThemePayload } from '../../sdk';
type CustomApp = SdkApp;
function useCustomApps() {
  const apps = useSdkApps(); const [loaded, setLoaded] = useState(isPreview);
  useEffect(() => {
    if (isPreview) return;
    let mounted = true;
    const refresh = () => { void nui<CustomApp[]>('customList').then(list => { if (mounted) setSdkApps(Array.isArray(list) ? list : []); setLoaded(true); }).catch(() => { if (mounted) { setSdkApps([]); setLoaded(true); } }); };
    const handler = (e: MessageEvent) => { if (isHostMessage(e.source, window, window.parent) && e.data?.type === 'customRegistry') refresh(); };
    refresh(); window.addEventListener('message', handler);
    return () => { mounted = false; window.removeEventListener('message', handler); };
  }, []);
  return { apps, loaded };
}
export function CustomAppStore({ search, installedOnly }: { search: string; installedOnly: boolean }) {
  const { apps } = useCustomApps(); const { data, updateData, run, busy, navigate } = usePhone();
  const isInstalled = (app: CustomApp) => data.customApps?.[app.identifier] ?? app.defaultApp === true;
  const visible = apps.filter(app => (!installedOnly || isInstalled(app)) && `${app.name} ${app.description}`.toLowerCase().includes(search.toLowerCase()));
  if (!visible.length) return null;
  return <section><p className="section-label">COMMUNITY APPS</p>{visible.map(app => {
    const installed = isInstalled(app);
    const change = (value: boolean) => run(async () => { updateData(await api('customApp', { app: app.identifier, installed: value })); await nui('customLifecycle', { app: app.identifier, event: value ? 'onInstall' : 'onDelete' }); });
    return <article className="store-app" key={app.identifier}><div className="store-app-icon">{app.icon ? <img src={app.icon} alt="" /> : <Blocks size={22} strokeWidth={1.5} />}</div><div className="store-app-copy"><h3>{app.name}</h3><small>Community · Free</small><p>{app.description}</p>{installed && <button disabled={busy} className="store-remove" onClick={() => change(false)}>Remove</button>}</div><button className={`store-get ${installed ? 'installed' : ''}`} disabled={busy} onClick={() => installed ? navigate('custom', app.identifier) : change(true)}>{installed ? 'Open' : 'Get'}</button></article>;
  })}</section>;
}
const hostTransport: HostTransport = { request: (route, payload) => nui<unknown>(route, payload) };
const READY_TIMEOUT_MS = 10000;
const handsetOf = (model?: string): Handset => model === 'flip' || model === 'fold' ? model : 'standard';
const readRoot = (name: string) => getComputedStyle(document.documentElement).getPropertyValue(name);

type HostState = 'loading' | 'ready' | 'error';

interface HostMessage { type?: unknown; app?: unknown; name?: unknown; data?: unknown }

export function CustomAppScreen({ id, transport = hostTransport }: { id: string; transport?: HostTransport }) {
  const { apps, loaded } = useCustomApps(); const definition = apps.find(app => app.identifier === id);
  const { data, device, run, setCall, navigate } = usePhone();
  const frame = useRef<HTMLIFrameElement>(null);
  const [authorized, setAuthorized] = useState(false); const [error, setError] = useState('');
  const [state, setState] = useState<HostState>('loading'); const [title, setTitle] = useState(''); const [attempt, setAttempt] = useState(0);
  const settings = useRef(data.settings); settings.current = data.settings;
  const resource = definition?.resource ?? '';
  const url = useMemo(() => definition ? appUrl(resource, definition.ui, { npParent: location.origin, npResource: resource, npApp: id }) : '', [definition, resource, id]);
  const origin = useMemo(() => definition ? (/^https?:\/\//.test(definition.ui) ? originOf(definition.ui) : `https://cfx-nui-${resource}`) : '', [definition, resource]);
  const permissions = useMemo(() => permissionsOf(definition), [definition]);
  const post = useCallback((message: unknown) => { frame.current?.contentWindow?.postMessage(message, origin); }, [origin]);
  const model = device?.model;

  useEffect(() => {
    let mounted = true; setAuthorized(false); setError(''); setState('loading');
    api('customApp', { app: id }).then(() => { if (mounted) setAuthorized(true); }).catch(e => { if (mounted) setError(e.message); });
    return () => { mounted = false; void nui('customLifecycle', { app: id, event: 'onClose' }); };
  }, [id, attempt]);

  useEffect(() => {
    if (!authorized || !definition) return;
    let lastTheme: ThemePayload | null = null;
    const currentTheme = () => { lastTheme = buildTheme(readRoot); return lastTheme; };
    const router = createRouter({
      appId: id, resource, origin, permissions, transport, post,
      handset: handsetOf(model), locale: document.documentElement.lang || navigator.language || 'en',
      getTheme: currentTheme,
      onReady: () => {
        setState('ready'); void nui('customLifecycle', { app: id, event: 'onOpen' });
        post(push('visibility', { visible: !document.hidden }));
        if (settings.current) post(push('event', { name: SETTINGS_EVENT, data: settings.current }));
      },
      onClose: () => navigate('home'),
      onSetTitle: setTitle,
    });
    const onMessage = (e: MessageEvent) => {
      const win = frame.current?.contentWindow;
      if (win && e.source === win && e.origin === origin) {
        const legacy: unknown = e.data;
        // Legacy dial request from pre-SDK addons; everything else goes through the router.
        if (isRecord(legacy) && legacy.npBridge === 'dial' && legacy.app === id && typeof legacy.number === 'string') {
          const number = legacy.number; void run(async () => setCall(await api('dial', { number }))); return;
        }
        void router.handle(e, win);
        return;
      }
      if (!isHostMessage(e.source, window, window.parent) || !isRecord(e.data)) return;
      const msg: HostMessage = e.data;
      if (msg.type === 'app:event' && msg.app === id && typeof msg.name === 'string') post(push('event', { name: msg.name, data: msg.data }));
      else if (msg.type === 'customMessage' && msg.app === id) { const ev = legacyEvent(msg.data); post(push('event', ev ?? { name: 'message', data: msg.data })); }
      else if (msg.type === 'customClose' && msg.app === id) navigate('home');
    };
    const observer = new MutationObserver(() => {
      const next = buildTheme(readRoot);
      if (!sameTheme(lastTheme, next) && router.isReady()) { lastTheme = next; post(push('theme', next)); }
    });
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['style', 'class', 'data-theme'] });
    const onVisibility = () => { if (router.isReady()) post(push('visibility', { visible: !document.hidden })); };
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('message', onMessage);
    const timer = window.setTimeout(() => { if (!router.isReady()) setState('error'); }, READY_TIMEOUT_MS);
    return () => {
      router.dispose(); observer.disconnect(); window.clearTimeout(timer);
      document.removeEventListener('visibilitychange', onVisibility); window.removeEventListener('message', onMessage);
    };
  }, [authorized, definition, origin, id, resource, permissions, transport, post, model, navigate, run, setCall]);

  useEffect(() => {
    if (state === 'ready' && frame.current?.contentWindow) post(push('event', { name: SETTINGS_EVENT, data: data.settings }));
  }, [data.settings, state, post]);

  if (error) return <p role="alert">{error}</p>;
  if (loaded && !definition) return <div className="app-host"><div className="app-host-state" role="status"><p>This app is offline. Its resource may have stopped.</p><button onClick={() => navigate('home')}>Home</button></div></div>;
  if (!definition || !authorized) return <div className="app-host"><div className="app-host-state" role="status"><p>Opening app…</p></div></div>;
  return <div className="app-host">
    {title && <div className="app-host-title">{title}</div>}
    <iframe key={attempt} ref={frame} className="app-host-frame" data-ready={state === 'ready'} title={definition.name} src={url}
      sandbox="allow-scripts allow-same-origin allow-forms" referrerPolicy="no-referrer" />
    {state === 'loading' && <div className="app-host-state" role="status"><p>Opening {definition.name}…</p></div>}
    {state === 'error' && <div className="app-host-state" data-tone="error" role="alert"><p>{definition.name} did not respond.</p><button onClick={() => setAttempt(n => n + 1)}>Try again</button></div>}
  </div>;
}

export function CustomAppRoute({ target }: { target: string }) { return <CustomAppScreen id={target} />; }
