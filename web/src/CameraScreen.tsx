import { useEffect, useRef, useState } from 'react';
import { Camera, SwitchCamera } from 'lucide-react';
import { api, isPreview, nui } from './api';
import { createGameView } from './gameVideo';
import { recordGameClip } from './gameRecording';
import { usePhone } from './PhoneContext';

export function CameraScreen() {
  const { device, updateData, navigate, run, busy, notify } = usePhone();
  const canvas = useRef<HTMLCanvasElement>(null);
  const recording = useRef<ReturnType<typeof recordGameClip> | undefined>(undefined);
  const mounted = useRef(false);
  const closeRequest = useRef<Promise<unknown>>(Promise.resolve());
  const [ready, setReady] = useState(false);
  const [error, setError] = useState('');
  const [front, setFront] = useState(false);
  const [mode, setMode] = useState<'photo' | 'video'>('photo');
  const [capturing, setCapturing] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [attempt, setAttempt] = useState(0);
  const [zoom, setZoom] = useState(false);

  useEffect(() => {
    mounted.current = true;
    let cancelled = false, animation = 0;
    let view: ReturnType<typeof createGameView> | undefined;
    setReady(false); setError(''); setZoom(false);
    void (async () => {
      if (isPreview) { setReady(true); return; }
      await closeRequest.current;
      if (cancelled) return;
      const reply = await nui<{ok:boolean;error?:string;zoom?:boolean}>('camera:open', { preview: true, front });
      if (!reply.ok) throw new Error(reply.error || 'The game camera is unavailable.');
      if (!cancelled) setZoom(reply.zoom === true);
      if (cancelled || !canvas.current) return;
      view = createGameView(canvas.current, { preserveDrawingBuffer: true, onContextLost: () => {
        recording.current?.cancel('The game camera stopped. Please reopen Camera.');
        setReady(false); setError('The game camera stopped. Please reopen Camera.');
      } });
      view.resize(540, 960);
      let previous = 0;
      const draw = (now: number) => {
        if (cancelled) return;
        animation = requestAnimationFrame(draw);
        if (now - previous >= 50) { view?.render(); previous = now; }
      };
      view.render(); animation = requestAnimationFrame(draw); setReady(true);
    })().catch(problem => { if (!cancelled) setError(problem instanceof Error ? problem.message : 'Camera unavailable.'); });
    return () => {
      cancelled = true; mounted.current = false;
      recording.current?.cancel(); recording.current = undefined;
      cancelAnimationFrame(animation); view?.dispose();
      closeRequest.current = nui('camera:close').catch(() => undefined);
    };
    // Facing is changed on the existing native camera, without restarting its renderer.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [device.id, attempt]);

  // While the phone cursor is up the game never sees the mouse wheel, so the preview forwards it to the native camera.
  useEffect(() => {
    if (!ready || !zoom) return;
    let last = -Infinity;
    const wheel = (event: WheelEvent) => {
      event.preventDefault();
      if (!event.deltaY || event.timeStamp - last < 40) return;
      last = event.timeStamp;
      void nui('camera:zoom', { dir: event.deltaY < 0 ? 1 : -1 }).catch(() => undefined);
    };
    window.addEventListener('wheel', wheel, { passive: false });
    return () => window.removeEventListener('wheel', wheel);
  }, [ready, zoom]);

  useEffect(() => {
    if (!capturing) return;
    const timer = setInterval(() => setSeconds(value => value + 1), 1000);
    return () => clearInterval(timer);
  }, [capturing]);

  const takePhoto = () => run(async () => {
    try { updateData(await api('capture', { front })); navigate('gallery'); }
    finally {
      await nui('captureDone');
      if (mounted.current) setAttempt(value => value + 1);
    }
  });
  const takeVideo = () => run(async () => {
    if (isPreview) throw new Error('In-game recording is available inside FiveM.');
    if (!canvas.current || !device.flash) return;
    const current = recordGameClip(canvas.current, device.flash.maxSeconds, device.flash.maxBytes || 24 * 1024 * 1024);
    recording.current = current; setSeconds(0); setCapturing(true);
    try {
      const blob = await current.result;
      if (!mounted.current) return;
      setCapturing(false);
      await api('uploadMedia', { blob });
      if (!mounted.current) return;
      const refreshed = await api('refresh', {});
      if (!mounted.current) return;
      if (refreshed.data) updateData(refreshed.data);
      navigate('gallery');
    } catch (problem) { if (mounted.current) throw problem; }
    finally { recording.current = undefined; if (mounted.current) setCapturing(false); }
  });

  return <>
    <div className="camera-viewfinder live-camera">
      <canvas ref={canvas} aria-label={front ? 'Selfie camera preview' : 'Rear camera preview'} />
      {isPreview && <span className="camera-preview-label"><Camera size={32} />In-game camera preview</span>}
      {capturing && <span className="camera-recording" role="status">● REC {seconds}s</span>}
    </div>
    {error && <p role="alert">{error} <button className="text-button" onClick={() => setAttempt(value => value + 1)}>Try again</button></p>}
    <div className="camera-controls">
      <button className="text-button" aria-pressed={mode === 'photo'} disabled={busy} onClick={() => setMode('photo')}>Photo</button>
      <button className="text-button" aria-pressed={mode === 'video'} disabled={busy || !device.flash} onClick={() => setMode('video')}>Video</button>
      <button className="icon-button" aria-label={front ? 'Switch to rear camera' : 'Switch to selfie camera'} disabled={!ready || busy} onClick={() => void run(async () => {
        const next = !front;
        const reply = await nui<{ok:boolean}>('camera:facing', { front: next });
        if (!reply.ok) throw new Error('The camera could not switch.');
        setFront(next);
      })}><SwitchCamera size={22} /></button>
    </div>
    <p className="muted camera-caption">{mode === 'video' ? `Silent clips · up to ${device.flash ? device.flash.maxSeconds : 15}s` : front ? 'Selfie camera' : 'Rear camera'}</p>
    <button className={`shutter ${mode === 'video' ? 'video-shutter' : ''}`} aria-label={capturing ? 'Stop recording' : mode === 'video' ? 'Record video' : 'Take photo'} disabled={!ready || (busy && !capturing)} onClick={() => {
      if (capturing) { recording.current?.stop(); return; }
      void (mode === 'video' ? takeVideo() : takePhoto());
    }}><span /></button>
    {!device.flash && <p className="muted">Video recording requires video storage to be configured.</p>}
    <button className="text-button centered" disabled={busy} onClick={() => { if (capturing) notify('Stop recording first.'); else navigate('gallery'); }}>Open gallery</button>
  </>;
}
