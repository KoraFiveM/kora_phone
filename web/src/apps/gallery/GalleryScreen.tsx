import { Camera,Maximize2,Trash2,X } from 'lucide-react';
import { useEffect,useState } from 'react';
import { createPortal } from 'react-dom';
import { api } from '../../api';
import { Empty } from '../../components';
import { usePhone } from '../../core/PhoneContext';
import { PhotoImage } from '../../Images';
import type { Photo } from '../../types';

function GalleryItem({ item, controls = false }: { item: Photo; controls?: boolean }) {
  return item.kind === 'video' ? <video src={item.url} controls={controls} muted={!controls} playsInline preload="metadata" aria-label={controls ? 'Saved phone video' : 'Video thumbnail'} /> : <PhotoImage src={item.url} alt={controls ? 'Saved phone photograph' : 'Gallery thumbnail'} />;
}
function MediaLightbox({ item, onClose }: { item: Photo; onClose: () => void }) {
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.key !== 'Escape') return; event.preventDefault(); event.stopImmediatePropagation(); onClose(); };
    window.addEventListener('keydown', key, true);
    return () => window.removeEventListener('keydown', key, true);
  }, [onClose]);
  return createPortal(<div className="media-lightbox" role="dialog" aria-modal="true" aria-label={item.kind === 'video' ? 'Full screen video' : 'Full screen photo'} onClick={onClose}>
    <button className="media-lightbox-close" aria-label="Close full screen viewer" autoFocus onClick={onClose}><X size={26} /></button>
    <div className="media-lightbox-body" onClick={event => event.stopPropagation()}>
      {item.kind === 'video' ? <video src={item.url} controls autoPlay playsInline aria-label="Saved phone video" /> : <PhotoImage src={item.url} alt="Saved phone photograph" />}
    </div>
  </div>, document.body);
}
export function GalleryScreen() {
  const { data, updateData, run, busy, device, navigate } = usePhone();
  const [selected, setSelected] = useState<string>();
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [enlarged, setEnlarged] = useState(false);
  const photo = data.photos.find(item => item.id === selected);
  const viewer = device.galleryViewer !== false;
  return <>{photo ? <div className="photo-view"><button className="text-button" onClick={() => { setSelected(undefined); setConfirmDelete(false); setEnlarged(false); }}>← All photos</button>{viewer ? <><button className="media-expand" aria-label="Open full screen viewer" onClick={() => setEnlarged(true)}><GalleryItem item={photo} /><span><Maximize2 size={16} />Full screen</span></button>{enlarged && <MediaLightbox item={photo} onClose={() => setEnlarged(false)} />}</> : <GalleryItem item={photo} controls />}<button className="text-button danger" onClick={() => setConfirmDelete(true)}><Trash2 size={16} />Delete photo</button>{confirmDelete && <div className="panel"><p>Remove this item from the phone gallery?</p><button className="primary" disabled={busy} onClick={() => run(async () => { updateData(await api('deletePhoto', { id: photo.id })); setSelected(undefined); setConfirmDelete(false); })}>Delete from gallery</button><button className="text-button" onClick={() => setConfirmDelete(false)}>Cancel</button></div>}</div> : <><div className="section-heading"><span className="section-label">YOUR MOMENTS / {data.photos.length}</span>{device.capabilities.camera && <button className="icon-button" aria-label="Open camera" onClick={() => navigate('camera')}><Camera size={20} /></button>}</div><div className="gallery-grid">{data.photos.map(item => <button key={item.id} onClick={() => setSelected(item.id)} aria-label="View photo"><GalleryItem item={item} /></button>)}</div>{!data.photos.length && <Empty title="Collect a moment" detail={device.capabilities.camera ? 'Photos and videos you take will appear here.' : 'Camera uploads have not been configured on this server.'} />}</>}</>;
}
