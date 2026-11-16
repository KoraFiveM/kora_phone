import { ArrowUpRight, Bell, Camera, Mic, MicOff, Pause, Phone, PhoneOff, Play } from 'lucide-react';
import { useEffect, useRef } from 'react';
import { api, isPreview, nui } from '../api';
import { CoverBackdrop } from './CoverArt';
import { imageUrl } from '../Images';
import { usePhoneStore } from './storeContext';

/** The flip phone's outer screen: clock, call controls and quick actions while folded shut. */
export function FlipCover({ onUnfold }: { onUnfold: () => void }) {
  const { state, dispatch, refs, actions, video, view } = usePhoneStore();
  const { call, coverCamera, coverPlaying, folded, shown, notifications } = state;
  const { data, time, date, locked, flip } = view;
  const { muted, on } = state.video;
  const canvas = useRef<HTMLCanvasElement>(null);
  const patch = (value: Partial<typeof state>) => dispatch({ type: 'patch', patch: value });

  const phoneCase = data.settings.phoneCase ?? 'default';
  const hasArt = phoneCase !== 'default' && (phoneCase !== 'custom' || imageUrl(data.settings.phoneCaseUrl ?? ''));
  const active = !!call && ['ringing', 'active'].includes(call.status);

  // Live game camera on the cover screen (lazy-loads the renderer).
  useEffect(() => {
    if (!coverCamera || !flip || !folded || !shown || !canvas.current) return;
    let cancelled = false; let animation = 0; let renderer: { render(): void; dispose(): void } | undefined;
    void nui<{ ok: boolean; error?: string }>('camera:coverStart', { active: true }).then(async result => {
      if (!result.ok) throw new Error(result.error || 'Camera unavailable');
      if (cancelled || !canvas.current) return;
      const { createGameView } = await import('../gameVideo');
      if (cancelled || !canvas.current) return;
      const created = createGameView(canvas.current); created.resize(280, 150); renderer = created;
      let previous = 0;
      const draw = (now: number) => { if (cancelled) return; animation = requestAnimationFrame(draw); if (now - previous > 66) { renderer?.render(); previous = now; } };
      animation = requestAnimationFrame(draw);
    }).catch(problem => { if (!cancelled) patch({ coverCamera: false, toast: problem instanceof Error ? problem.message : 'Camera unavailable' }); });
    return () => { cancelled = true; cancelAnimationFrame(animation); renderer?.dispose(); void nui('camera:coverStart', { active: false }); };
    // patch only dispatches; the camera restarts when one of these changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [coverCamera, flip, folded, shown]);

  const toggleMusic = () => {
    const existing = refs.screen.current?.querySelector<HTMLAudioElement>('audio');
    const station = data.stations.find(item => /^https:\/\//i.test(item.url) && !/youtube\.com|youtu\.be|soundcloud\.com/i.test(item.url));
    const player = existing || refs.coverAudio.current || (station ? new Audio(station.url) : undefined);
    if (!player) { actions.notify('Save a direct HTTPS audio station in Sound first.'); return; }
    if (!existing) refs.coverAudio.current = player;
    player.volume = data.settings.volume;
    if (player.paused) void player.play().then(() => patch({ coverPlaying: true })).catch(() => actions.notify('This audio stream could not play.'));
    else { player.pause(); patch({ coverPlaying: false }); }
  };

  const callLine = !active ? (notifications.length ? `${notifications.length} notification${notifications.length === 1 ? '' : 's'}` : 'All caught up')
    : call?.status === 'active' ? 'Call in progress' : call?.direction === 'incoming' ? 'Incoming call' : 'Calling…';
  return <div className={`flip-cover ${hasArt ? 'has-art' : ''} ${folded ? '' : 'unfolding'}`}><CoverBackdrop settings={data.settings} /><div className="cover-lenses"><i /><i /></div><span className="eyebrow">{'CIRCUIT / FLIP'}</span><div className="cover-display"><div className="handset-clock" aria-label={time}>{time}</div><p>{date.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' })}</p><div className="cover-notice"><Bell size={16} /><span>{callLine}</span></div>{coverCamera && !active && <canvas ref={canvas} className="cover-camera-preview" aria-label="Game camera preview" />}<div className="cover-quick-actions">{active && call ? <>{call.status === 'ringing' && call.direction === 'incoming' && <button aria-label="Answer call on cover" onClick={() => void actions.run(async () => actions.setCall(await api('answer', { id: call.id })))}><Phone size={18} /></button>}{call.status === 'active' && <button aria-label={muted ? 'Unmute call' : 'Mute call'} onClick={() => void actions.run(() => video.videoControl('mute', !muted))}>{muted ? <MicOff size={18} /> : <Mic size={18} />}</button>}<button className="cover-hangup" aria-label="End call on cover" onClick={() => void actions.run(() => video.hangUp(call))}><PhoneOff size={18} /></button></> : <><button aria-label="Toggle cover camera preview" disabled={locked || isPreview} aria-pressed={coverCamera} onClick={() => patch({ coverCamera: !coverCamera })}><Camera size={18} /></button><button aria-label={coverPlaying ? 'Pause music' : 'Play music'} disabled={locked} onClick={toggleMusic}>{coverPlaying ? <Pause size={18} /> : <Play size={18} />}</button></>}</div><small>{active && on ? 'VIDEO PAUSED WHILE CLOSED' : `UNFOLD TO ${locked ? 'UNLOCK' : 'OPEN'}`}</small></div><button className="cover-open" onClick={onUnfold}>Unfold phone <ArrowUpRight size={17} /></button><button className="cover-close" onClick={actions.close}>Put away</button></div>;
}
