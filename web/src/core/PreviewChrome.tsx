import { ArrowUpRight, LockKeyhole, PhoneIncoming, SlidersHorizontal } from 'lucide-react';
import { isDemo, isEmbed, isPreview } from '../api';
import { previewBootstrap, previewIncoming, resetPreview } from '../mock';
import { handsetIdentity } from '../themes';
import type { HandsetModel } from '../themes';
import { usePhoneStore } from './storeContext';

const MODELS: readonly HandsetModel[] = ['standard', 'flip', 'fold'];

function ModelSwitch() {
  const { actions, view } = usePhoneStore();
  return <div className="preview-handsets" aria-label="Preview handset model">{MODELS.map(value => <button key={value} aria-pressed={view.model === value} onClick={() => actions.choosePreviewModel(value)}>{handsetIdentity(value).name}</button>)}</div>;
}

/** Browser-only page furniture around the phone (the demo handset switch, or the full marketing preview). It never ships in game. */
export function PreviewChrome() {
  const { state, actions } = usePhoneStore();
  if (isDemo) return isEmbed ? null : <ModelSwitch />;
  if (!isPreview) return null;
  const { shown } = state;
  return <><header className="preview-header"><a className="brand" href="#" onClick={e => { e.preventDefault(); actions.navigate('home'); }}>THREE <span>( PHONE )</span></a><span className="preview-build"><i />THREE HANDSETS <span>/</span> 002</span></header><aside className="preview-intro"><p className="eyebrow"><span className="red-dot" />LESS NOISE. MORE LIFE.</p><h1>Your city.<br />Your people.<br /><span>Your phone.</span></h1><p className="intro-description">Everything you need to feel connected.<br />Nothing to get in the way.</p><div className="intro-rule" /><div className="preview-features"><div><span>01</span><p>Made for the moments<br />between the missions.</p></div><div><span>02</span><p>One device. Your number.<br />A whole city within reach.</p></div></div><ModelSwitch /><div className="preview-controls"><button onClick={() => { if (!shown) actions.apply(previewBootstrap()); else void actions.lock(); }}><LockKeyhole size={15} />{shown ? 'Lock phone' : 'Open phone'}</button><button onClick={() => { if (!shown) actions.apply(previewBootstrap()); previewIncoming(); }}><PhoneIncoming size={15} />Try a call</button><button onClick={resetPreview} aria-label="Reset preview data"><SlidersHorizontal size={15} />Reset</button></div><p className="demo-caption">INTERACTIVE PREVIEW / SAMPLE DATA</p></aside><footer className="preview-footer"><span>DESIGNED TO GET OUT OF YOUR WAY.</span><span>LOS SANTOS <ArrowUpRight size={13} /></span></footer></>;
}
