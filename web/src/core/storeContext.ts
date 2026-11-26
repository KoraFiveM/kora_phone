import { createContext, useContext } from 'react';
import type { Dispatch, RefObject } from 'react';
import type { AppId, Call, DeviceData } from '../types';
import type { HandsetModel, Appearance } from '../themes';
import type { Quiet } from '../quiet';
import type { PhoneAction, PhoneState } from './phoneState';
import type { CallVideo } from './useCallVideo';
import type { PhoneActions } from './usePhoneActions';

/** Mutable values the event handlers need to read without re-subscribing on every render. */
export interface PhoneRefs {
  call: RefObject<Call | undefined>;
  shown: RefObject<boolean>;
  app: RefObject<AppId>;
  busy: RefObject<boolean>;
  notificationDevice: RefObject<string | undefined>;
  quietConfig: RefObject<Quiet>;
  /** Contact names, kept while the phone is closed so a game notification can say who it's from (memory only). */
  contactNames: RefObject<Map<string, string>>;
  audio: RefObject<AudioContext | undefined>;
  coverAudio: RefObject<HTMLAudioElement | undefined>;
  peekTimer: RefObject<ReturnType<typeof setTimeout> | undefined>;
  phone: RefObject<HTMLDivElement | null>;
  screen: RefObject<HTMLDivElement | null>;
}

/** Values derived from the device, computed once per render. */
export interface PhoneView {
  data: DeviceData;
  locked: boolean;
  model: HandsetModel;
  flip: boolean;
  fold: boolean;
  brand: string;
  appearance: Appearance;
  quiet: boolean;
  date: Date;
  time: string;
}

export interface PhoneStore {
  state: PhoneState;
  dispatch: Dispatch<PhoneAction>;
  refs: PhoneRefs;
  video: CallVideo;
  actions: PhoneActions;
  view: PhoneView;
}

export const PhoneStoreContext = createContext<PhoneStore>(null!);
/** The shell's store: reducer state, derived view values and every action. Screens use `usePhone()` instead. */
export const usePhoneStore = () => useContext(PhoneStoreContext);
