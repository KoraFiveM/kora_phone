import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Blocks } from 'lucide-react';
import { api, nui } from '../../api';
import { usePhone } from '../../core/PhoneContext';
import { isSdkInstalled, refreshSdkApps, useRuntimeApps } from '../../core/runtimeApps';
import type { SdkApp } from '../../core/runtimeApps';
import { isHostMessage } from '../../nuiEvents';
import '../../CustomApps.css';
import { SETTINGS_EVENT, legacyEvent } from '../../sdk/legacy';
import { appUrl, createRouter, buildTheme, permissionsOf, sameTheme, originOf, push, isRecord } from '../../sdk';
import { buildLbDocument } from '../../sdk';
import type { HostTransport, Handset, ThemePayload } from '../../sdk';
import { lbAction } from './lbActions';
import type { AppId } from '../../types';
type CustomApp = SdkApp;
function useCustomApps() { return useRuntimeApps(); }
const maskUrl = (icon: string) => `url("${icon.replace(/^nui:\/\//, 'https://cfx-nui-')}")`;

/** An app's icon: a themed mask for an .svg shipped with the app, an image for other URLs, a generic block otherwise. */
export function SdkIcon({ icon, size = 25 }: { icon?: string; size?: number }) {
  if (icon && /^(nui:\/\/|https:\/\/)/.test(icon) && /\.svg(\?|$)/.test(icon)) return <span className="sdk-icon" style={{ width: size, height: size, maskImage: maskUrl(icon), WebkitMaskImage: maskUrl(icon) }} aria-hidden="true" />;
  if (icon && /^https:\/\//.test(icon)) return <img src={icon} alt="" width={size} height={size} />;
  return <Blocks size={size} strokeWidth={1.5} />;
}

const CATEGORY_LABEL: Record<string, string> = { tools: 'Tools', life: 'Life', social: 'Social' };

export function CustomAppStore({ search, installedOnly, category = 'All' }: { search: string; installedOnly: boolean; category?: string }) {
  const { apps } = useCustomApps(); const { data, updateData, run, busy, navigate } = usePhone();
  const isInstalled = (app: CustomApp) => isSdkInstalled(app, data.customApps);
  const visible = apps.filter(app => (!installedOnly || isInstalled(app))
    && (category === 'All' || CATEGORY_LABEL[app.category ?? 'tools'] === category)
    && `${app.name} ${app.description}`.toLowerCase().includes(search.toLowerCase()));
  if (!visible.length) return null;
  return <section><p className="section-label">MORE APPS</p>{visible.map(app => {
    const installed = isInstalled(app);
    const change = (value: boolean) => run(async () => {
      updateData(await api('customApp', { app: app.identifier, installed: value }));
      await nui('customLifecycle', { app: app.identifier, event: value ? 'onInstall' : 'onDelete' });
      await refreshSdkApps();
    });
    return <article className="store-app" key={app.identifier}><div className="store-app-icon"><SdkIcon icon={app.icon} size={22} /></div><div className="store-app-copy"><h3>{app.name}</h3><small>{app.source === 'server' ? (CATEGORY_LABEL[app.category ?? 'tools'] ?? 'Apps') : 'Community'} · Free</small><p>{app.description}</p>{installed && !app.system && <button disabled={busy} className="store-remove" onClick={() => change(false)}>Remove</button>}</div><button className={`store-get ${installed ? 'installed' : ''}`} disabled={busy} onClick={() => installed ? navigate('custom', app.identifier) : change(true)}>{installed ? 'Open' : 'Get'}</button></article>;
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
  const dataRef = useRef(data); dataRef.current = data;
  const resource = definition?.resource ?? '';
  // lb-phone style apps (registered from a resource's client script) get the compatibility layer injected into their own
  // page, which the phone then loads as a document of its own origin. null = not loaded yet, '' = load it plainly.
  const compat = definition?.source === 'client' && !/^https?:\/\//.test(definition.ui);
  const [compatDoc, setCompatDoc] = useState<string | null>(null);
  const url = useMemo(() => definition ? appUrl(resource, definition.ui, { npParent: location.origin, npResource: resource, npApp: id }) : '', [definition, resource, id]);
  const origin = useMemo(() => definition ? (compat && compatDoc ? location.origin : /^https?:\/\//.test(definition.ui) ? originOf(definition.ui) : `https://cfx-nui-${resource}`) : '', [definition, resource, compat, compatDoc]);
  const permissions = useMemo(() => permissionsOf(definition), [definition]);
  const post = useCallback((message: unknown) => { frame.current?.contentWindow?.postMessage(message, origin); }, [origin]);
  const model = device?.model;

  useEffect(() => {
    let mounted = true; setAuthorized(false); setError(''); setState('loading');
    api('customApp', { app: id }).then(() => { if (mounted) setAuthorized(true); }).catch(e => { if (mounted) setError(e.message); });
    return () => { mounted = false; void nui('customLifecycle', { app: id, event: 'onClose' }); };
  }, [id, attempt]);

  useEffect(() => {
    if (!authorized || !definition || !compat) { setCompatDoc(compat ? null : ''); return; }
    let mounted = true; setCompatDoc(null);
    Promise.all([nui<{ html?: string }>('apps:html', { app: id }), fetch('lb-shim.js').then(response => response.text())])
      .then(([page, shim]) => { if (mounted) setCompatDoc(page?.html ? buildLbDocument(page.html, { resource, ui: definition.ui, app: id, name: definition.name, hostOrigin: location.origin }, shim) : ''); })
      .catch(() => { if (mounted) setCompatDoc(''); });
    return () => { mounted = false; };
  }, [authorized, definition, compat, id, resource, attempt]);

  useEffect(() => {
    if (!authorized || !definition || compatDoc === null) return;
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
      onOpen: app => navigate(app as AppId),
      onLb: compat ? (action, payload) => lbAction(action, payload, { data: dataRef.current, navigate, run: work => run(work), setCall }) : undefined,
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
      else if (msg.type === 'customMessage' && msg.app === id) { const ev = legacyEvent(msg.data); post(push('event', ev ?? { name: 'message', data: msg.data })); if (compat) post(push('event', { name: 'kora:raw', data: msg.data })); }
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
  }, [authorized, definition, compat, compatDoc, origin, id, resource, permissions, transport, post, model, navigate, run, setCall]);

  useEffect(() => {
    if (state === 'ready' && frame.current?.contentWindow) post(push('event', { name: SETTINGS_EVENT, data: data.settings }));
  }, [data.settings, state, post]);

  if (error) return <p role="alert">{error}</p>;
  if (loaded && !definition) return <div className="app-host"><div className="app-host-state" role="status"><p>This app is offline. Its resource may have stopped.</p><button onClick={() => navigate('home')}>Home</button></div></div>;
  if (!definition || !authorized || compatDoc === null) return <div className="app-host"><div className="app-host-state" role="status"><p>Opening app…</p></div></div>;
  return <div className="app-host">
    {title && <div className="app-host-title">{title}</div>}
    <iframe key={attempt} ref={frame} className="app-host-frame" data-ready={state === 'ready'} title={definition.name} {...(compat && compatDoc ? { srcDoc: compatDoc } : { src: url })}
      sandbox="allow-scripts allow-same-origin allow-forms" referrerPolicy="no-referrer" />
    {state === 'loading' && <div className="app-host-state" role="status"><p>Opening {definition.name}…</p></div>}
    {state === 'error' && <div className="app-host-state" data-tone="error" role="alert"><p>{definition.name} did not respond.</p><button onClick={() => setAttempt(n => n + 1)}>Try again</button></div>}
  </div>;
}

export function CustomAppRoute({ target }: { target: string }) { return <CustomAppScreen id={target} />; }
