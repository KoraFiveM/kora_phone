import { useEffect } from 'react';
import { adaptBootstrap, adaptLiveCall, api, nui } from '../api';
import { previewText } from '../chatTokens';
import { remember } from '../lastScreen';
import { isHostMessage } from '../nuiEvents';
import type { Call } from '../types';
import { parseShareRequest } from './ShareRequest';
import type { PhoneStore } from './storeContext';

type Message = { action?: unknown; type?: unknown; app?: unknown; hidden?: unknown; data?: unknown };
/** The union of fields the game client sends across all message types; each handler reads only its own. */
interface HostData {
  id?: string; label?: string; operation?: string; status?: string; action?: string; epoch?: string; muted?: boolean;
  result?: HostData; data?: HostData; ok?: boolean; error?: string | { message?: string }; accountId?: string; recoveryCode?: string;
  state?: { activeCall?: Parameters<typeof adaptLiveCall>[0] }; isMine?: boolean; deviceId?: string; senderNumber?: string;
  body?: string; sender?: string; subject?: string; title?: string; number?: string;
}

/**
 * NUI messages from the game client (and the browser preview). Embedded apps are children of this
 * window and must never be able to spoof them, so every message is checked against the host frame.
 * `app:event` and `customMessage` are not handled here: the app host (apps/custom) listens for those
 * itself and forwards them into the matching iframe.
 */
export function useHostEvents({ state, dispatch, refs, video, actions }: PhoneStore) {
  const { stopVideo, handleVideoSignal, beginVideo, videoEpoch } = video;
  const { apply, navigate, pushNotification, closedAlert } = actions;
  const locked = state.device?.locked ?? true;

  useEffect(() => {
    const patch = dispatch;
    const toast = (message: string) => patch({ type: 'patch', patch: { toast: message } });
    const startCall = (data: unknown, adapt: boolean) => {
      if ((data as Call | undefined)?.id !== refs.call.current?.id) { stopVideo(); patch({ type: 'video', patch: { muted: false } }); }
      patch({ type: 'patch', patch: { call: adapt ? adaptLiveCall(data as Parameters<typeof adaptLiveCall>[0]) : data as Call | undefined } });
    };
    const sameDevice = (deviceId: unknown) => !(deviceId && refs.notificationDevice.current && String(deviceId) !== refs.notificationDevice.current);
    const closeFromHost = () => {
      patch({ type: 'close', source: 'host' }); stopVideo();
      refs.coverAudio.current?.pause();
    };

    const handler = (event: MessageEvent) => {
      const message = event.data as Message | null;
      if (!message || typeof message !== 'object') return;
      if (!isHostMessage(event.source, window, window.parent)) return;
      const type = message.action || message.type;
      const data = message.data as HostData | undefined;
      if (type === 'service:request' && data?.id) { patch({ type: 'patch', patch: { serviceRequest: { id: String(data.id), label: String(data.label || 'Mobile shop'), operation: String(data.operation || 'service') } } }); return; }
      if (type === 'service:result' && data) {
        const result = data.result || data; const details = result.data || result; const problem = result.error;
        patch({ type: 'patch', patch: {
          serviceRequest: undefined,
          serviceResult: { message: result.ok === false ? (typeof problem === 'string' ? problem : problem?.message || 'Service could not complete') : 'Mobile service completed.', accountId: details.accountId, recoveryCode: details.recoveryCode },
        } });
        return;
      }
      if (type === 'share:request') { const request = parseShareRequest(data); if (request) patch({ type: 'patch', patch: { shareRequest: request } }); return; }
      if (type === 'service:open') { stopVideo(); patch({ type: 'patch', patch: { shown: false, serviceOpen: true } }); return; }
      if (type === 'customOpen' && !locked) navigate('custom', String(message.app));
      if (type === 'phone:open' || type === 'open') {
        const live = data?.state?.activeCall;
        void api('refresh', {}).then(value => apply(live ? { ...value, call: adaptLiveCall(live) } : value)).catch(error => { void nui('close', { error: error instanceof Error ? error.message : 'Could not open phone' }); });
      } else if (type === 'bootstrap' && data) patch({ type: 'patch', patch: { device: adaptBootstrap(data as unknown as Parameters<typeof adaptBootstrap>[0]) } });
      else if (type === 'phone:close' || type === 'phone:reset' || type === 'close') {
        if (type === 'phone:reset') {
          refs.notificationDevice.current = undefined; patch({ type: 'reset' });
          refs.alarms.current = []; refs.quietConfig.current = {}; refs.contactNames.current.clear();
          remember('alarms', '[]'); remember('quiet', '{}');
        }
        closeFromHost();
      }
      else if (type === 'content:cleared') patch({ type: 'clearNotifications' });
      else if (type === 'capture') patch({ type: 'patch', patch: { hiddenCapture: !!message.hidden } });
      else if (type === 'phone:visibility') patch({ type: 'patch', patch: { hiddenCapture: message.data === false } });
      else if (type === 'camera:closed') patch({ type: 'patch', patch: { hiddenCapture: false } });
      else if (type === 'call') startCall(message.data, false);
      else if (type === 'calls:incoming' || type === 'calls:outgoing' || type === 'calls:accepted') startCall(message.data, true);
      else if (type === 'calls:ended') {
        // An incoming call nobody answered leaves a note, even if the phone is closed.
        const ringing = refs.call.current;
        if (ringing && ringing.direction === 'incoming' && ringing.id === data?.id && ['missed', 'cancelled'].includes(data?.status ?? '')) {
          pushNotification({ title: ringing.number, body: 'Missed call', app: 'phone' }); closedAlert(ringing.number, 'Missed call');
        }
        patch({ type: 'callEnded', id: data?.id });
      }
      else if (type === 'videoSignal') void handleVideoSignal(message.data as Parameters<typeof handleVideoSignal>[0]);
      else if (type === 'videoControl' && data && data.id === refs.call.current?.id) {
        const action = data.action;
        if (action === 'pending') { videoEpoch.current = data.epoch; patch({ type: 'video', patch: { pending: true } }); }
        else if (action === 'request' || action === 'requested') { if (typeof data.epoch === 'string') { videoEpoch.current = data.epoch; patch({ type: 'video', patch: { request: true } }); } }
        else if (action === 'accept' || action === 'accepted') { if (typeof data.epoch === 'string') { videoEpoch.current = data.epoch; void beginVideo(); } }
        else if (action === 'stop' || action === 'decline' || action === 'declined') { stopVideo(); if (action !== 'stop') toast('Video invitation declined.'); }
        else if (action === 'mute' && typeof data.muted === 'boolean') patch({ type: 'video', patch: { muted: data.muted } });
      }
      else if (type === 'video:stopped') { stopVideo(); toast('Camera stopped. Voice remains connected.'); }
      else if (type === 'messages:read' || type === 'mail:activity') patch({ type: 'bump' });
      else if (type === 'messages:new' && data && !data.isMine) {
        if (!sameDevice(data.deviceId)) return;
        const sender = String(data.senderNumber || 'New message');
        pushNotification({ deviceId: data.deviceId, title: sender, body: previewText(data.body), app: 'messages' }); closedAlert(sender, previewText(data.body));
      }
      else if (type === 'mail:new' && data) {
        if (!sameDevice(data.deviceId)) return;
        const sender = String(data.sender || 'New mail'); const subject = String(data.subject || 'New mail');
        pushNotification({ deviceId: data.deviceId, title: sender, body: subject, app: 'mail' }); closedAlert(sender, subject);
      }
      else if (type === 'phone:peek' && data && !refs.shown.current) {
        clearTimeout(refs.peekTimer.current);
        patch({ type: 'patch', patch: { peek: { title: String(data.title || 'Message'), body: String(data.body || '') } } });
        refs.peekTimer.current = setTimeout(() => patch({ type: 'patch', patch: { peek: undefined } }), 3500);
      }
      else if (type === 'notification' || type === 'notification:push') pushNotification(data ?? {});
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, [apply, state.device?.id, locked, navigate, handleVideoSignal, beginVideo, stopVideo, dispatch, refs, videoEpoch, pushNotification, closedAlert]);
}
