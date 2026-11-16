import { ArrowDown, ChevronLeft, MessageCircle, Power, X } from 'lucide-react';
import { useEffect } from 'react';
import type { CSSProperties } from 'react';
import { api, isDemo, isEmbed, isPreview, nui } from '../api';
import { PhotoImage } from '../Images';
import { previewBootstrap } from '../mock';
import { handsetIconStyle } from '../themes';
import { SetupScreen } from '../apps/setup/Setup';
import { CallOverlay } from './CallOverlay';
import { FlipCover } from './FlipCover';
import { snapshotForFold, snapshotForUnfold } from './foldAnimation';
import { HeadsUp } from './HeadsUp';
import { HomeScreen } from './home/HomeScreen';
import { LockScreen } from './LockScreen';
import { NotificationShade } from './NotificationShade';
import { PhoneContext } from './PhoneContext';
import { PreviewChrome } from './PreviewChrome';
import { ScreenRouter } from './ScreenRouter';
import { ServiceDialogs } from './ServiceDialogs';
import { ShareRequestSheet } from './ShareRequest';
import { StatusBar } from './StatusBar';
import { usePhoneStore } from './storeContext';
import { usePhoneStage } from './usePhoneStage';

/** Escape closes the topmost thing: a service request, the service panel, the open app, then the phone. */
function useEscapeKey() {
  const { state, actions } = usePhoneStore();
  const { app, shown, serviceOpen, serviceRequest, serviceResult } = state;
  const { close, navigate, patch } = actions;
  useEffect(() => {
    const key = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.key !== 'Escape') return;
      if (serviceRequest) {
        void nui('handset:action', { op: 'consent', id: serviceRequest.id, accept: false });
        patch({ serviceRequest: undefined });
        if (!shown && !serviceOpen) void nui('close');
        return;
      }
      if (serviceOpen || serviceResult) { close(); return; }
      if (shown) { if (app !== 'home') navigate('home'); else close(); }
    };
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [app, shown, serviceOpen, serviceRequest, serviceResult, close, navigate, patch]);
}

export function Phone() {
  const { state, refs, actions, view } = usePhoneStore();
  const { device, shown, app, toast, alert, shareRequest, folded, unfolding, busy, hiddenCapture, peek, showNotifications } = state;
  const { data, locked, model, flip, fold, appearance, brand, time } = view;
  const stage = usePhoneStage();
  useEscapeKey();

  const patch = actions.patch;
  const unfold = () => {
    if (flip) {
      snapshotForUnfold(refs.phone.current, refs.screen.current);
      patch({ unfolding: true }); window.setTimeout(() => patch({ unfolding: false }), 800);
    }
    patch({ folded: false, coverCamera: false });
  };
  const foldFlip = () => { snapshotForFold(refs.phone.current, refs.screen.current); patch({ showNotifications: false, folded: true }); };
  const enableAudio = () => { refs.audio.current ??= new AudioContext(); void refs.audio.current.resume(); };

  const setup = !locked && !data.settings.setupComplete;
  const wallpaper = locked || app === 'home';
  const rootClass = isDemo ? (isEmbed ? 'demo embed' : 'demo') : isPreview ? 'preview' : 'game';
  const phoneClass = `phone handset-${model} ${flip ? 'style-flip' : ''} ${fold ? 'phone-fold' : ''} ${fold && !folded ? 'is-unfolded' : ''} ${fold && folded ? 'folded' : ''} ${flip && folded ? 'is-folded' : ''} ${unfolding ? 'is-unfolding' : ''} ${app === 'home' ? 'on-home' : ''} ${hiddenCapture ? 'capture-hidden' : ''} theme-${data.settings.theme || 'kora_core'}`;
  const screenClass = `phone-screen ${setup ? 'in-setup' : wallpaper ? 'show-wallpaper' : ''} appearance-${appearance} wallpaper-${data.settings.wallpaper} icons-${handsetIconStyle(model, data.settings.iconStyle)}`;

  return <div className={rootClass} onPointerDown={enableAudio}>
    <PreviewChrome />
    <ServiceDialogs />
    <div ref={stage.stage} className="phone-stage" style={stage.stageStyle}>
      {!shown && isPreview && <button className="reopen" onClick={() => actions.apply(previewBootstrap())}><Power size={24} />Open phone</button>}
      {shown && device && <div className="phone-scale" style={{ width: stage.width * stage.scale, height: stage.height * stage.scale }}><div ref={refs.phone} className={phoneClass} style={{ '--phone-scale': stage.scale, '--handset-width': `${stage.width}px` } as CSSProperties}>
        <div className="side-key volume-up" /><div className="side-key volume-down" /><div className="side-key power-key" />
        <div ref={refs.screen} inert={flip && folded} aria-hidden={flip && folded} className={screenClass}>
          {wallpaper && data.settings.wallpaper === 'custom' && data.settings.wallpaperUrl && <PhotoImage src={data.settings.wallpaperUrl} className="custom-wallpaper" />}
          <StatusBar time={time} quiet={view.quiet} drag={stage.handlers} />
          <PhoneContext.Provider value={{ device, data, updateData: actions.updateData, navigate: actions.navigate, notify: actions.notify, run: actions.run, busy, setCall: actions.setCall, setHasPin: actions.setHasPin, revision: state.revision }}>
            {locked ? <LockScreen /> : setup ? <SetupScreen /> : app === 'home' ? <HomeScreen /> : <ScreenRouter />}
            {showNotifications && !locked && <NotificationShade />}
            <CallOverlay />
          </PhoneContext.Provider>
          {shareRequest && <ShareRequestSheet key={shareRequest.id} request={shareRequest} onClose={() => patch({ shareRequest: undefined })} onMessage={message => patch({ toast: message })} onSaved={() => { void api('refresh', {}).then(refreshed => { if (refreshed.data) actions.updateData(refreshed.data); }).catch(() => undefined); }} />}
          {alert && !folded && !showNotifications && <HeadsUp key={alert.at} alert={{ ...alert, title: data.contacts.find(c => c.number === alert.title)?.name ?? alert.title }} locked={locked} onDismiss={() => patch({ alert: undefined })} onOpen={() => { if (!locked) { actions.navigate(alert.app); actions.markRead([alert]); } patch({ alert: undefined }); }} />}
          {toast && <div className={`toast ${model === 'standard' ? 'nothing-status' : ''} ${locked ? 'toast-top' : app === 'home' ? 'toast-home' : ''}`} role="status"><span>{toast}</span><button aria-label="Dismiss notification" onClick={() => patch({ toast: '' })}><X size={14} /></button></div>}
          {busy && <div className="busy-line" role="progressbar" aria-label="Working" />}
          <nav className="system-nav" aria-label="Phone navigation"><button aria-label="Back to home" onClick={() => !locked && actions.navigate('home')}><ChevronLeft size={19} /></button><button className="home-indicator" aria-label="Home" onClick={() => !locked && actions.navigate('home')}><span /></button><button aria-label="Close phone" onClick={actions.close}><ArrowDown size={17} /></button></nav>
        </div>
        {flip && <><div className="flip-crease" aria-hidden="true" /><div className="flip-hinge left" /><div className="flip-hinge right" />
          {(folded || unfolding) && <FlipCover onUnfold={unfold} />}
          <button className="fold-control" disabled={busy} aria-label={folded ? 'Unfold phone' : 'Fold phone'} onClick={() => { if (folded) unfold(); else foldFlip(); }}>{folded ? 'OPEN' : 'FOLD'}</button>
        </>}
        {fold && <><div className="fold-spine" aria-hidden="true" /><button className="fold-control" disabled={busy} aria-label={folded ? 'Open fold into tablet' : 'Fold to outer screen'} onClick={() => patch({ folded: !folded })}>{folded ? 'EXPAND' : 'FOLD'}</button></>}
      </div></div>}
      {isPreview && !isDemo && shown && <div className="phone-caption"><span><i /> CONNECTED TO YOUR WORLD</span><span>{brand} / {model.toUpperCase()}</span></div>}
    </div>
    {peek && !shown && <div className="phone-peek" onAnimationEnd={e => { if (e.animationName === 'peekOut') patch({ peek: undefined }); }}><div className="peek-card"><MessageCircle size={18} /><div><strong>{peek.title}</strong><small>{peek.body}</small></div></div></div>}
  </div>;
}
