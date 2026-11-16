import { useCallback, useRef } from 'react';
import type { Dispatch, RefObject } from 'react';
import { api, isPreview, nui, sendSignal } from '../api';
import type { Bootstrap, Call } from '../types';
import type { GameVideo, VideoSignal } from '../gameVideo';
import type { PhoneAction } from './phoneState';

type Signal = VideoSignal & { id?: string; epoch?: string };
type ControlReply = { ok: boolean; error?: string | { message?: string } };

export interface CallVideoInput {
  dispatch: Dispatch<PhoneAction>;
  callRef: RefObject<Call | undefined>;
  device?: Bootstrap;
  /** True while a flip phone is shut: the camera pauses so the cover screen is not streaming. */
  paused: boolean;
}

/** In-call video: the WebRTC connection (lazy-loaded), its signalling and the invitation flow. */
export function useCallVideo({ dispatch, callRef, device, paused }: CallVideoInput) {
  const gameVideo = useRef<GameVideo | undefined>(undefined);
  const videoCallId = useRef<string | undefined>(undefined);
  const videoEpoch = useRef<string | undefined>(undefined);
  const pauseVideo = useRef(false); pauseVideo.current = paused;
  const videoReady = useRef(false);
  const pendingSignals = useRef<VideoSignal[]>([]);
  const localStream = useRef<MediaStream | undefined>(undefined);
  const remoteStream = useRef<MediaStream | undefined>(undefined);
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const toast = useCallback((message: string) => dispatch({ type: 'patch', patch: { toast: message } }), [dispatch]);

  const stopVideo = useCallback(() => {
    gameVideo.current?.stop(); gameVideo.current = undefined;
    videoReady.current = false; videoCallId.current = undefined; videoEpoch.current = undefined; pendingSignals.current = [];
    localStream.current = undefined; remoteStream.current = undefined;
    if (localVideoRef.current) localVideoRef.current.srcObject = null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null;
    dispatch({ type: 'video', patch: { on: false, remote: false, request: false, pending: false } });
  }, [dispatch]);

  const videoControl = useCallback(async (action: 'request' | 'accept' | 'decline' | 'stop' | 'mute', nextMuted?: boolean) => {
    const current = callRef.current;
    if (!current || current.status !== 'active') return;
    if (isPreview) { toast('Live video and voice controls are available in FiveM.'); return; }
    const reply = await nui<ControlReply>('calls:videoControl', { id: current.id, action, epoch: videoEpoch.current, ...(nextMuted === undefined ? {} : { muted: nextMuted }) });
    if (!reply.ok) throw new Error(typeof reply.error === 'string' ? reply.error : reply.error?.message || 'Call control failed');
    if (action === 'request') dispatch({ type: 'video', patch: { pending: true } });
    if (action === 'decline' || action === 'stop') stopVideo();
    if (action === 'mute' && nextMuted !== undefined) dispatch({ type: 'video', patch: { muted: nextMuted } });
  }, [callRef, dispatch, stopVideo, toast]);

  const beginVideo = useCallback(async () => {
    const current = callRef.current;
    if (!device?.video || !current || current.status !== 'active' || gameVideo.current) return;
    const id = current.id; const epoch = videoEpoch.current;
    if (!epoch) return;
    const { GameVideo } = await import('../gameVideo');
    if (gameVideo.current || callRef.current?.id !== id) return;
    const connection = new GameVideo(); gameVideo.current = connection;
    videoCallId.current = id; videoReady.current = false;
    dispatch({ type: 'video', patch: { request: false, pending: false, on: true } });
    const abort = (message: string) => { stopVideo(); toast(message); void nui('calls:videoControl', { id, epoch, action: 'stop' }).catch(() => undefined); };
    try {
      await connection.start(device.video.iceServers, current.direction === 'incoming',
        signal => { if (callRef.current?.id === id && gameVideo.current === connection) sendSignal({ id, epoch, ...signal }); },
        (stream, local) => {
          if (gameVideo.current !== connection || callRef.current?.id !== id) return;
          if (local) { connection.setPaused(pauseVideo.current); localStream.current = stream; if (localVideoRef.current) localVideoRef.current.srcObject = stream; }
          else { remoteStream.current = stream; dispatch({ type: 'video', patch: { remote: true } }); if (remoteVideoRef.current) remoteVideoRef.current.srcObject = stream; }
        },
        message => { if (gameVideo.current === connection) abort(message); });
      if (gameVideo.current !== connection || callRef.current?.id !== id) { connection.stop(); return; }
      connection.setPaused(pauseVideo.current);
      videoReady.current = true;
      for (const signal of pendingSignals.current.splice(0)) await connection.receive(signal);
    } catch (problem) {
      if (gameVideo.current === connection) abort(problem instanceof Error ? problem.message : 'Video failed. Voice remains connected.');
    }
  }, [callRef, device?.video, dispatch, stopVideo, toast]);

  const handleVideoSignal = useCallback(async (signal: Signal) => {
    if (!signal || typeof signal !== 'object' || signal.id !== callRef.current?.id || !signal.epoch || signal.epoch !== videoEpoch.current || callRef.current?.status !== 'active') return;
    if (!gameVideo.current || !videoReady.current) {
      if (pendingSignals.current.length < 128) pendingSignals.current.push(signal);
      return;
    }
    if (videoCallId.current === signal.id) await gameVideo.current.receive(signal);
  }, [callRef]);

  const hangUp = useCallback(async (call: Call) => {
    await api('hangup', { id: call.id, reject: call.direction === 'incoming' && call.status === 'ringing' });
    stopVideo(); dispatch({ type: 'patch', patch: { call: undefined } });
  }, [dispatch, stopVideo]);

  return { gameVideo, videoEpoch, localStream, remoteStream, localVideoRef, remoteVideoRef, stopVideo, videoControl, beginVideo, handleVideoSignal, hangUp };
}
export type CallVideo = ReturnType<typeof useCallVideo>;
