import { Mic, MicOff, Phone, PhoneOff, SwitchCamera, Video, VideoOff } from 'lucide-react';
import { api } from '../api';
import { PhotoImage } from '../Images';
import { usePhoneStore } from './storeContext';

const statusText = (call: { status: string; direction: string }, muted: boolean) =>
  call.status === 'ringing' ? (call.direction === 'incoming' ? 'Incoming call' : 'Calling…')
    : call.status === 'active' ? muted ? 'Connected · Microphone muted' : 'Connected' : call.status;

export function CallOverlay() {
  const { state, actions, video, view } = usePhoneStore();
  const { call, device, busy } = state;
  const { on, remote, request, pending, muted } = state.video;
  if (!call || !device) return null;
  const { data, brand } = view;
  const { run } = actions;
  const contact = data.contacts.find(item => item.number === call.number);
  const live = ['ringing', 'active'].includes(call.status);
  const incomingRing = call.status === 'ringing' && call.direction === 'incoming';
  const videoOn = on || pending;
  return <div className={`call-screen ${on || remote ? 'has-video' : ''}`}><p className="eyebrow">{brand} / PHONE</p><span className="call-avatar"><PhotoImage src={contact?.photo} className="call-photo" alt="Caller photo" /></span><h2>{contact?.name || call.number}</h2><p>{call.number}</p><span className="call-status"><i />{statusText(call, muted)}</span>
    {call.status === 'active' && (on || remote) ? <div className="call-video"><video ref={video.remoteVideoRef} autoPlay playsInline className="remote-video" /><video ref={video.localVideoRef} autoPlay playsInline muted className="local-video" /></div> : <div className="call-orbits"><div /><div /><div /></div>}
    {request && <div className="video-invitation" role="alertdialog" aria-label="Video call invitation"><Video size={20} /><strong>Switch to video?</strong><p>Your game camera starts only if you accept.</p><button className="primary" disabled={busy} onClick={() => void run(() => video.videoControl('accept'))}>Accept video</button><button className="text-button" disabled={busy} onClick={() => void run(() => video.videoControl('decline'))}>Keep voice</button></div>}
    {pending && <p className="video-pending" role="status">Waiting for video acceptance…</p>}
    <div className="call-controls">{incomingRing && <button className="call-button accept" aria-label="Answer call" disabled={busy} onClick={() => run(async () => actions.setCall(await api('answer', { id: call.id })))}><Phone size={26} /></button>}
      {call.status === 'active' && <button className={`icon-button ${muted ? 'active' : ''}`} aria-label={muted ? 'Unmute microphone' : 'Mute microphone'} aria-pressed={muted} disabled={busy} onClick={() => void run(() => video.videoControl('mute', !muted))}>{muted ? <MicOff size={22} /> : <Mic size={22} />}</button>}
      {call.status === 'active' && device.video && <button className="icon-button" aria-label={videoOn ? 'Stop video' : 'Request video'} disabled={busy || request} onClick={() => void run(() => video.videoControl(videoOn ? 'stop' : 'request'))}>{videoOn ? <VideoOff size={22} /> : <Video size={22} />}</button>}
      {on && <button className="icon-button" aria-label="Switch selfie or rear camera" disabled={busy} onClick={() => void run(async () => { await video.gameVideo.current?.flip(); })}><SwitchCamera size={22} /></button>}
      {live ? <button className="call-button" aria-label="End call" disabled={busy} onClick={() => run(() => video.hangUp(call))}><PhoneOff size={26} /></button> : <button className="primary" onClick={() => actions.setCall(undefined)}>Done</button>}</div><small>{live ? 'YOUR WORLD, CONNECTED.' : 'CALL ENDED.'}</small></div>;
}
