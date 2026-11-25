import { useCallback } from 'react';
import type { Dispatch } from 'react';
import { api, isPreview, nui } from '../api';
import { isQuiet } from '../quiet';
import type { AppId, Bootstrap, DeviceData, Notification } from '../types';
import { normalizeData } from '../types';
import { handsetIdentity } from '../themes';
import type { HandsetModel } from '../themes';
import { appDefinition, canLaunch, restoreApp } from './appRegistry';
import { sdkApp } from './runtimeApps';
import type { PhoneAction, PhoneState } from './phoneState';
import type { PhoneRefs } from './storeContext';
import type { CallVideo } from './useCallVideo';

export interface ActionInput {
  state: PhoneState;
  dispatch: Dispatch<PhoneAction>;
  refs: PhoneRefs;
  video: CallVideo;
}

type Incoming = Partial<Record<'deviceId' | 'title' | 'body' | 'message' | 'app', unknown>> & { urgent?: unknown };

/** Everything that changes the phone: navigation, notifications, locking, opening and closing. */
export function usePhoneActions({ state, dispatch, refs, video }: ActionInput) {
  const device = state.device;
  const { stopVideo } = video;
  const patch = useCallback((value: Partial<PhoneState>) => dispatch({ type: 'patch', patch: value }), [dispatch]);

  const notify = useCallback((message: string) => patch({ toast: message }), [patch]);
  const run = useCallback(async (work: () => Promise<void>) => {
    if (refs.busy.current) return;
    refs.busy.current = true; patch({ busy: true });
    try { await work(); } catch (e) { notify(e instanceof Error ? e.message : 'Something went wrong'); }
    finally { refs.busy.current = false; patch({ busy: false }); }
  }, [refs, patch, notify]);

  const navigate = useCallback((requested: AppId, destination = '') => {
    // The id of a folder app (a Mail notification, the weather shortcut) opens through the app host.
    if (requested !== 'home' && requested !== 'custom' && !appDefinition(requested) && sdkApp(requested)) { destination = requested; requested = 'custom'; }
    const customAllowed = requested === 'custom' && destination !== '' && device?.capabilities.store !== false;
    dispatch({ type: 'navigate', app: customAllowed || canLaunch(requested, device) ? requested : 'home', target: destination });
  }, [device, dispatch]);

  // The stale-device guard: an update from a handset that has since been swapped is dropped.
  const deviceId = device?.id;
  const updateData = (value: DeviceData) => dispatch({ type: 'data', value, deviceId });
  const setCall = useCallback((call?: PhoneState['call']) => patch({ call }), [patch]);
  const setHasPin = useCallback((value: boolean) => dispatch({ type: 'device', update: current => ({ ...current, hasPin: value }) }), [dispatch]);
  const markRead = useCallback((items: Notification[]) => dispatch({ type: 'markRead', items }), [dispatch]);

  const apply = useCallback((value: Bootstrap) => dispatch({ type: 'apply', value, app: restoreApp(value) }), [dispatch]);
  const close = useCallback(() => {
    stopVideo(); refs.coverAudio.current?.pause();
    const current = refs.call.current;
    if (current && ['active', 'ringing'].includes(current.status)) void api('hangup', { id: current.id, reject: current.direction === 'incoming' && current.status === 'ringing' }).catch(() => undefined);
    void nui('close');
    dispatch({ type: 'close', source: 'ui' });
  }, [dispatch, refs, stopVideo]);

  const reloadHandset = useCallback(async () => {
    if (isPreview) { dispatch({ type: 'bump' }); return; }
    const next = await api('refresh', {});
    dispatch({ type: 'patch', patch: { device: next } }); dispatch({ type: 'bump' });
  }, [dispatch]);

  // With the phone closed nothing on screen can show a notification, so ask the game for one (silenced by Do Not Disturb).
  const closedAlert = useCallback((title: string, body: string) => {
    if (refs.shown.current || isQuiet(refs.quietConfig.current)) return;
    void nui('notify', { title: refs.contactNames.current.get(title) ?? title, body });
  }, [refs]);

  const pushNotification = useCallback((incoming: Incoming) => {
    const notification: Notification = {
      deviceId: String(incoming.deviceId || refs.notificationDevice.current || ''), title: String(incoming.title || 'Notification'),
      body: String(incoming.body || incoming.message || ''), app: (incoming.app || 'messages') as AppId, at: Date.now(),
    };
    const owner = refs.notificationDevice.current;
    if (!notification.deviceId || (owner && owner !== notification.deviceId)) return;
    // Do Not Disturb still collects the notification, it just doesn't pop up (unless it's urgent).
    // No pop-up for a text while you're already looking at your chats.
    const reading = incoming.app === 'messages' && refs.shown.current && (refs.app.current === 'messages' || refs.app.current === 'social');
    const popup = !reading && (incoming.urgent === true || !isQuiet(refs.quietConfig.current));
    dispatch({ type: 'notification', notification, popup });
  }, [dispatch, refs]);

  const lock = useCallback(() => run(async () => {
    const value = await api('lock', {});
    dispatch({ type: 'patch', patch: { device: value, pin: '', app: 'home' } });
  }), [dispatch, run]);

  // Browser preview only: switch the handset model the demo shows.
  const choosePreviewModel = useCallback((nextModel: HandsetModel) => {
    if (!isPreview) return;
    stopVideo();
    dispatch({ type: 'patch', patch: { folded: nextModel === 'fold', coverCamera: false } });
    dispatch({
      type: 'device',
      update: current => {
        const data = normalizeData(current.data);
        const name = handsetIdentity(nextModel).name;
        return { ...current, model: nextModel, data: { ...data, settings: { ...data.settings, phoneStyle: nextModel, name } } };
      },
    });
  }, [dispatch, stopVideo]);

  return { notify, run, navigate, updateData, setCall, setHasPin, markRead, apply, close, reloadHandset, closedAlert, pushNotification, lock, patch, choosePreviewModel };
}
export type PhoneActions = ReturnType<typeof usePhoneActions>;
