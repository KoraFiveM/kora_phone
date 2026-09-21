import { useEffect, useRef, useState } from 'react';
import { Aperture, ArrowUpRight, Camera, Heart, ImageOff, MessageCircle, Plus, RefreshCw, Send, Share2, Trash2, Video, Volume2, VolumeX } from 'lucide-react';
import { useClipRecorder } from './useClipRecorder';
import { api, isPreview, nui } from './api';
import { asList } from './types';
import type { Conversation, MediaKind, Post } from './types';
import { dateLabel, Empty } from './components';
import { Comments } from './SocialBank';
import { LoadState, useLoad, usePhone } from './PhoneContext';
import { SocialAvatar, SocialHeader, SocialSheet } from './SocialUI';
export function FlashScreen() {
  const { device, data, run, busy, notify, navigate } = usePhone();
  const feed = useLoad(() => api('feed', { kind: 'flash' }), []);
  const [older, setOlder] = useState<Post[]>([]);
  const posts = [...asList<Post>(feed.value), ...older].filter((post, i, all) => all.findIndex(x => x.id === post.id) === i);
  const [expanded, setExpanded] = useState<number>(); const [remove, setRemove] = useState<number>();
  const [sharing, setSharing] = useState<Post>();
  const shareList = useLoad(() => sharing && data.installedApps?.includes('social') ? api('conversations', {}) : Promise.resolve([]), [sharing?.id]);
  const [tab, setTab] = useState<'Explore' | 'Your posts'>('Explore');
  const [failedMedia, setFailedMedia] = useState<number[]>([]);
  const [muted, setMuted] = useState(true);
  const [composing, setComposing] = useState(false);
  const [mediaKind, setMediaKind] = useState<MediaKind>('photo');
  const [caption, setCaption] = useState('');
  const [progress, setProgress] = useState(0);
  // First time in Flash: the server has no profile for this phone yet, so ask for a handle and a name.
  const needsProfile = /social profile/i.test(feed.error);
  const [profile, setProfile] = useState(() => ({ handle: (device.characterName ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 20) + Math.floor(10 + Math.random() * 90), name: device.characterName ?? '' }));
  const { recording, clip, discardClip, stopRecording, start } = useClipRecorder(device.flash ? device.flash.maxSeconds : 15);
  const startRecording = () => run(start);
  const videos = useRef(new Map<number, HTMLVideoElement>());
  useEffect(() => {
    const observer = new IntersectionObserver(entries => {
      for (const entry of entries) {
        const video = entry.target as HTMLVideoElement;
        if (!composing && !sharing && expanded === undefined && remove === undefined && entry.isIntersecting && entry.intersectionRatio > 0.6) void video.play().catch(() => undefined);
        else video.pause();
      }
    }, { threshold: [0, 0.6, 1] });
    for (const video of videos.current.values()) observer.observe(video);
    return () => observer.disconnect();
  }, [posts.map(post => post.id).join(','), composing, sharing, expanded, remove, tab, failedMedia.join(',')]);
  const closeComposer = () => { discardClip(); setCaption(''); setMediaKind('photo'); setComposing(false); };
  const postClip = () => run(async () => {
    if (!clip) return;
    if (device.flash && device.flash.maxBytes && clip.blob.size > device.flash.maxBytes) throw new Error('That clip is too big. Try a shorter one.');
    setProgress(0);
    try {
      const media = await api('uploadMedia', { blob: clip.blob, onProgress: setProgress });
      await api('post', { kind: 'flash', body: caption, price: 0, mediaKind: 'video', media: media.url, mediaId: media.id });
      closeComposer(); feed.refresh(); notify('Posted to Flash');
    } finally { setProgress(0); }
  });
  const postPhoto = () => run(async () => {
    try {
      if (isPreview) await api('post', { kind: 'flash', body: caption, price: 0, mediaKind: 'photo' });
      else {
        const shot = (await api('capture', {})).photos[0];
        if (!shot) throw new Error('The photo was not saved');
        await api('post', { kind: 'flash', body: caption, price: 0, mediaKind: 'photo', media: shot.url, mediaId: Number(shot.id) });
      }
      closeComposer(); feed.refresh(); notify('Posted to Flash');
    } finally { await nui('captureDone'); }
  });
  const visible = tab === 'Your posts' ? posts.filter(post => !!post.mine) : posts;
  const author = (post: Post) => post.number === device.number ? 'You' : data.contacts.find(c => c.number === post.number)?.name || post.number;
  const refresh = () => { setOlder([]); setFailedMedia([]); feed.refresh(); };
  return <div className="flash-app">
    <SocialHeader name="Flash" mark={<Aperture size={24} />} actions={<button className="icon-button" aria-label="Refresh feed" disabled={busy} onClick={refresh}><RefreshCw size={17} /></button>} />
    <div className="flash-discover-bar"><div className="social-filter">{(['Explore','Your posts'] as const).map(value => <button key={value} aria-pressed={tab === value} onClick={() => setTab(value)}>{value}</button>)}</div><span className="flash-city-label"><i />LOS SANTOS</span></div>
    <div className="flash-scroll">
      <div className="flash-editorial"><span className="social-kicker">A DIFFERENT POINT OF VIEW</span><h2>{tab === 'Explore' ? 'Life, in a flash.' : 'Your point of view.'}</h2><p>{tab === 'Explore' ? 'Little moments. A whole city.' : 'The moments you put out into the world.'}</p></div>
      <LoadState {...feed} error={needsProfile ? '' : feed.error} retry={refresh} />
      {needsProfile && <form className="panel form flash-profile" onSubmit={e => { e.preventDefault(); run(async () => { await api('createProfile', { handle: profile.handle, displayName: profile.name }); refresh(); }); }}>
        <h3>Set up your Flash profile</h3><p className="muted">Your handle and name show on everything you post.</p>
        <label>Handle<input required pattern="[A-Za-z0-9_]{3,24}" maxLength={24} value={profile.handle} onChange={e => setProfile({ ...profile, handle: e.target.value })} /></label>
        <label>Display name<input required maxLength={64} value={profile.name} onChange={e => setProfile({ ...profile, name: e.target.value })} /></label>
        <button className="primary" disabled={busy}>Create profile</button>
      </form>}
      {device.capabilities.flash === false ? <Empty title="The camera is resting." detail="Media uploads have not been configured on this server." /> : visible.map(post => <article className="flash-card" key={post.id}>
        <div className="flash-media-wrap">
          {failedMedia.includes(post.id) ? <div className="flash-media-error"><ImageOff size={32} /><p>This moment couldn’t load.</p><button onClick={() => setFailedMedia(list => list.filter(id => id !== post.id))}>Try again</button></div> : post.media_kind === 'video'
            ? <video ref={el => { if (el) videos.current.set(post.id, el); else videos.current.delete(post.id); }} src={post.media_url} loop muted={muted} playsInline preload="metadata" onError={() => setFailedMedia(list => [...list, post.id])} />
            : <img src={post.media_url} alt={post.body || 'Photo shared on Flash'} referrerPolicy="no-referrer" loading="lazy" onError={() => setFailedMedia(list => [...list, post.id])} />}
          <span className="flash-format">{post.media_kind === 'video' ? <Video size={12} /> : <Camera size={12} />}{post.media_kind === 'video' ? 'CLIP' : 'MOMENT'}</span>
          {post.media_kind === 'video' && <button className="flash-sound" aria-label={muted ? 'Unmute clip' : 'Mute clip'} onClick={() => setMuted(value => !value)}>{muted ? <VolumeX size={18} /> : <Volume2 size={18} />}</button>}
          <span className="flash-media-signature">f.</span>
        </div>
        <div className="flash-card-body">
          <div className="flash-author"><SocialAvatar name={author(post)} photo={data.contacts.find(c => c.number === post.number)?.photo} /><div><strong>{author(post)}</strong><small>{dateLabel(post.created_at)} · Los Santos</small></div>{(!!post.mine || device.admin) && <button className="icon-button" aria-label="Remove post" onClick={() => setRemove(post.id)}><Trash2 size={16} /></button>}</div>
          {post.body && <p className="flash-caption-text">{post.body}</p>}
          <div className="flash-reactions">
            <button className={post.liked ? 'liked' : ''} aria-label={post.liked ? 'Unlike post' : 'Like post'} disabled={busy} onClick={() => run(async () => {
              await api('like', { id: post.id, liked: !post.liked }); feed.refresh();
              setOlder(list => list.map(item => item.id === post.id ? { ...item, liked: !post.liked, likes: item.likes + (post.liked ? -1 : 1) } : item));
            })}><Heart size={21} fill={post.liked ? 'currentColor' : 'none'} /><span>{post.likes}</span></button>
            <button aria-label="View comments" onClick={() => setExpanded(post.id)}><MessageCircle size={21} /><span>{post.comments}</span></button>
            <button className="flash-share" aria-label="Share to Pulse" onClick={() => setSharing(post)}><Share2 size={18} /><span>Send</span></button>
          </div>
        </div>
      </article>)}
      {!visible.length && !feed.loading && !feed.error && device.capabilities.flash !== false && <Empty title={tab === 'Your posts' ? 'Make your first moment.' : 'The city is yours.'} detail={tab === 'Your posts' ? 'Capture something worth sharing.' : 'Be the first to show your side of Los Santos.'} />}
      {posts.length >= 30 && <button className="text-button centered" disabled={busy} onClick={() => run(async () => { const rows = await api('feed', { kind: 'flash', before: Math.min(...posts.map(post => post.id)) }); setOlder(previous => [...previous, ...asList<Post>(rows)]); })}>Explore older moments</button>}
      <p className="social-endnote">LOOK UP. THERE’S A CITY OUT THERE.</p>
    </div>
    <div className="flash-capture-dock"><button disabled={busy || device.capabilities.flash === false} aria-label="Post to Flash" onClick={() => setComposing(true)}><Plus size={20} />Capture a moment<Aperture size={19} /></button></div>
    {expanded !== undefined && <SocialSheet title="The conversation." detail="A little love goes a long way." onClose={() => { setExpanded(undefined); feed.refresh(); }}>{posts.find(post => post.id === expanded) && <Comments post={posts.find(post => post.id === expanded)!} />}</SocialSheet>}
    {remove !== undefined && <SocialSheet title="Remove this moment?" detail="It will disappear from the public feed." onClose={() => setRemove(undefined)}><button className="primary" disabled={busy} onClick={() => run(async () => { await api('removePost', { id: remove, kind: 'flash' }); setOlder(list => list.filter(post => post.id !== remove)); feed.refresh(); setRemove(undefined); })}>Remove post</button></SocialSheet>}
    {composing && <SocialSheet title="Make it a moment." detail="Something worth sharing with the city." onClose={closeComposer}>
      <div className="social-filter capture-tabs">{device.capabilities.camera !== false && <button aria-pressed={mediaKind === 'photo'} onClick={() => { discardClip(); setMediaKind('photo'); }}><Camera size={16} />Photo</button>}{device.flash && <button aria-pressed={mediaKind === 'video'} onClick={() => { discardClip(); setMediaKind('video'); }}><Video size={16} />Video</button>}</div>
      <div className="social-record-stage">
        {clip ? <video src={clip.url} controls playsInline /> : <><Aperture size={60} strokeWidth={.9} /><p>{recording ? 'Recording…' : mediaKind === 'photo' ? 'Find your angle.' : 'Your moment. Your voice.'}</p><small>{mediaKind === 'photo' ? isPreview ? 'A sample photo in browser preview' : 'Captures your game view' : 'Uses your real webcam & microphone'}</small><div className="capture-corner tl" /><div className="capture-corner br" /></>}
      </div>
      <label className="flash-caption-field">A few words<textarea aria-label="Caption" rows={2} maxLength={2000} placeholder="What’s the story?" value={caption} onChange={e => setCaption(e.target.value)} /><span>{caption.length}/2000</span></label>
      {mediaKind === 'photo' ? <button className="primary flash-publish" disabled={busy} onClick={postPhoto}><Camera size={18} />Capture & publish</button> : clip ? <><button className="primary flash-publish" disabled={busy} onClick={postClip}><Send size={17} />Publish clip</button><button className="text-button centered" onClick={discardClip}>Retake clip</button></> : <button className="primary flash-publish" disabled={busy} onClick={recording ? stopRecording : startRecording}>{recording ? 'Stop recording' : 'Record webcam clip'}</button>}
      {progress > 0 && progress < 1 && <div className="upload-progress" role="progressbar" aria-label="Uploading" aria-valuenow={Math.round(progress * 100)} aria-valuemin={0} aria-valuemax={100}><i style={{ width: `${Math.round(progress * 100)}%` }} /></div>}
      <p className="social-publish-note">Posts are public and stay until removed.</p>
    </SocialSheet>}
    {sharing && <SocialSheet title="Pass it on." detail="Send this moment to a Pulse conversation." onClose={() => setSharing(undefined)}>
      <div className="flash-share-preview"><Aperture size={23} /><div><strong>{author(sharing)} on Flash</strong><p>{sharing.body || 'A moment worth sharing.'}</p></div></div>
      {data.installedApps?.includes('social') ? <><LoadState {...shareList} retry={shareList.refresh} /><div className="pulse-picker">{asList<Conversation>(shareList.value).map(conversation => {
        const name = conversation.kind === 'group' ? conversation.name || 'Group' : data.contacts.find(c => c.number === (conversation.members || '').split(',')[0])?.name || (conversation.members || '').split(',')[0];
        return <button key={conversation.id} disabled={busy} onClick={() => run(async () => { await api('shareToChat', { conversationId: conversation.id, postId: sharing.id, body: sharing.body, mediaUrl: sharing.media_url, mediaKind: sharing.media_kind }); setSharing(undefined); notify('Shared to Pulse'); })}><SocialAvatar name={name} group={conversation.kind === 'group'} /><span><strong>{name}</strong><small>{conversation.kind === 'group' ? 'Group' : 'Direct conversation'}</small></span><Send size={17} /></button>;
      })}</div>{!shareList.loading && !asList(shareList.value).length && <button className="primary" onClick={() => navigate('social')}>Start a Pulse chat<ArrowUpRight size={17} /></button>}</> : <button className="primary" onClick={() => navigate('store')}>Get Pulse from the App Store<ArrowUpRight size={17} /></button>}
    </SocialSheet>}
  </div>;
}
