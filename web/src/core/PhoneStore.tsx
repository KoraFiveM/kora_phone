import { useEffect, useMemo, useReducer, useState } from 'react';
import type { ReactNode } from 'react';
import { isPreview } from '../api';
import { recall } from '../lastScreen';
import { previewBootstrap } from '../mock';
import { isQuiet } from '../quiet';
import type { Quiet } from '../quiet';
import { appearanceOf } from '../themes';
import type { HandsetModel } from '../themes';
import { normalizeData } from '../types';
import { restoreApp } from './appRegistry';
import { initialPhoneState, phoneReducer } from './phoneState';
import { PhoneStoreContext } from './storeContext';
import type { PhoneRefs, PhoneStore } from './storeContext';
import { storedAlarms, useBackgroundEffects } from './useBackgroundEffects';
import { useCallVideo } from './useCallVideo';
import { useHostEvents } from './useHostEvents';
import { usePhoneActions } from './usePhoneActions';

function useTime() {
  const [date, setDate] = useState(new Date());
  useEffect(() => { const timer = setInterval(() => setDate(new Date()), 1000); return () => clearInterval(timer); }, []);
  return date;
}

const storedQuiet = (): Quiet => { try { return JSON.parse(recall('quiet') ?? '{}') as Quiet; } catch { return {}; } };
const brandOf = (model: HandsetModel) => model === 'standard' ? 'ORCHARD' : model === 'flip' ? 'CIRCUIT' : 'ATLAS';

/** Owns the phone: reducer state, refs for event handlers, the NUI listener and the background timers. */
export function PhoneStoreProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(phoneReducer, undefined, () => {
    const device = isPreview ? previewBootstrap() : undefined;
    return initialPhoneState(device, isPreview, restoreApp(device));
  });
  const { device } = state;
  const date = useTime();

  const [refs] = useState<PhoneRefs>(() => ({
    call: { current: undefined }, shown: { current: state.shown }, app: { current: state.app }, busy: { current: false },
    notificationDevice: { current: device?.id }, quietConfig: { current: storedQuiet() },
    contactNames: { current: new Map<string, string>() }, alarms: { current: storedAlarms() }, firedAlarms: { current: new Set<string>() },
    audio: { current: undefined }, coverAudio: { current: undefined }, peekTimer: { current: undefined },
    phone: { current: null }, screen: { current: null },
  }));
  refs.call.current = state.call; refs.shown.current = state.shown; refs.app.current = state.app;
  if (device) refs.notificationDevice.current = device.id;

  const data = useMemo(() => {
    const normalized = normalizeData(device?.data);
    if (device?.preferences && !device.data) normalized.settings = device.preferences;
    return normalized;
  }, [device?.data, device?.preferences]);
  const model: HandsetModel = device?.model || 'standard';
  const { dnd, dndFrom, dndTo } = data.settings;
  const quiet = isQuiet(device ? { dnd, dndFrom, dndTo } : refs.quietConfig.current, date);
  const flip = model === 'flip';
  const view: PhoneStore['view'] = {
    data, locked: device?.locked ?? true, model, flip, fold: model === 'fold', brand: brandOf(model),
    appearance: appearanceOf(device?.data?.settings.theme || device?.preferences?.theme), quiet, date,
    time: date.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }),
  };

  const video = useCallVideo({ dispatch, callRef: refs.call, device, paused: flip && state.folded });
  const actions = usePhoneActions({ state, dispatch, refs, video });
  const store: PhoneStore = { state, dispatch, refs, video, actions, view };
  useBackgroundEffects(store);
  useHostEvents(store);
  return <PhoneStoreContext.Provider value={store}>{children}</PhoneStoreContext.Provider>;
}
