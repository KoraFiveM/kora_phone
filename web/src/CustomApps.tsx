import { useEffect, useRef, useState } from 'react';
import { api, isPreview, nui } from './api';
import { usePhone } from './PhoneContext';
import { isHostMessage } from './nuiEvents';
interface CustomApp { identifier: string; name: string; description: string; resource: string; ui: string }
function useCustomApps() {
  const [apps, setApps] = useState<CustomApp[]>([]);
  useEffect(() => {
    if (isPreview) return;
    let mounted = true;
    const refresh = () => { void nui<CustomApp[]>('customList').then(list => { if (mounted) setApps(Array.isArray(list) ? list : []); }).catch(() => { if (mounted) setApps([]); }); };
    const handler = (e: MessageEvent) => { if (isHostMessage(e.source, window, window.parent) && e.data?.type === 'customRegistry') refresh(); };
    refresh(); window.addEventListener('message', handler);
    return () => { mounted = false; window.removeEventListener('message', handler); };
  }, []);
  return apps;
}
export function CustomAppStore({ search, installedOnly }: { search: string; installedOnly: boolean }) {
  const apps = useCustomApps(); const { data, updateData, run, busy, navigate } = usePhone();
  const visible = apps.filter(app => (!installedOnly || data.customApps?.[app.identifier]) && `${app.name} ${app.description}`.toLowerCase().includes(search.toLowerCase()));
  if (!visible.length) return null;
  return <section><p className="section-label">COMMUNITY APPS</p>{visible.map(app => {
    const installed = !!data.customApps?.[app.identifier];
    const change = (value: boolean) => run(async () => { updateData(await api('customApp', { app: app.identifier, installed: value })); await nui('customLifecycle', { app: app.identifier, event: value ? 'onInstall' : 'onDelete' }); });
    return <article className="store-app" key={app.identifier}><div className="store-app-copy"><h3>{app.name}</h3><small>Community · Free</small><p>{app.description}</p>{installed && <button disabled={busy} className="store-remove" onClick={() => change(false)}>Remove</button>}</div><button className="store-get" disabled={busy} onClick={() => installed ? navigate('custom', app.identifier) : change(true)}>{installed ? 'Open' : 'Get'}</button></article>;
  })}</section>;
}
export function CustomAppScreen({ id }: { id: string }) {
  const apps = useCustomApps(); const definition = apps.find(app => app.identifier === id);
  const { data, run, setCall, navigate } = usePhone();
  const frame = useRef<HTMLIFrameElement>(null); const [authorized, setAuthorized] = useState(false); const [error, setError] = useState('');
  const origin = definition ? `https://cfx-nui-${definition.resource}` : '';
  useEffect(() => {
    let mounted = true; setAuthorized(false);
    api('customApp', { app: id }).then(() => { if (mounted) setAuthorized(true); }).catch(e => { if (mounted) setError(e.message); });
    return () => { mounted = false; void nui('customLifecycle', { app: id, event: 'onClose' }); };
  }, [id]);
  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (!authorized || !definition) return;
      if (e.source === frame.current?.contentWindow && e.origin === origin && e.data?.app === id) {
        if (e.data.npBridge === 'ready') {
          frame.current?.contentWindow?.postMessage({ npBridge: 'settings', app: id, settings: data.settings }, origin);
          void nui('customLifecycle', { app: id, event: 'onOpen' });
        } else if (e.data.npBridge === 'dial' && typeof e.data.number === 'string') void run(async () => setCall(await api('dial', { number: e.data.number })));
      } else if (isHostMessage(e.source, window, window.parent) && e.data?.app === id) {
        if (e.data.type === 'customMessage') frame.current?.contentWindow?.postMessage({ npBridge: 'message', app: id, data: e.data.data }, origin);
        if (e.data.type === 'customClose') navigate('home');
      }
    };
    window.addEventListener('message', handler); return () => window.removeEventListener('message', handler);
  }, [authorized, definition, origin, id, data.settings, run, setCall, navigate]);
  if (error) return <p role="alert">{error}</p>;
  if (!definition) return <p>This app is unavailable. Its resource may have stopped.</p>;
  if (!authorized) return <p>Opening app…</p>;
  const query = new URLSearchParams({ npParent: location.origin, npResource: definition.resource, npApp: id });
  return <iframe ref={frame} className="custom-app-frame" title={definition.name} sandbox="allow-scripts allow-same-origin" src={`${origin}/${definition.ui}?${query}`} />;
}
