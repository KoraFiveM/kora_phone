import { useEffect, useRef, useState } from 'react';
import { ImagePlus, UserRound } from 'lucide-react';
import type { Photo } from './types';
export function imageUrl(value: string): boolean {
  if (!value || value.length > 2048) return false;
  try { const url = new URL(value); return url.protocol === 'https:' && !!url.hostname && !url.username && !url.password; } catch { return false; }
}
export function PhotoImage({ src, className = '', alt = '' }: { src?: string; className?: string; alt?: string }) {
  const [failed, setFailed] = useState('');
  return src && imageUrl(src) && src !== failed ? <img className={className} src={src} alt={alt} referrerPolicy="no-referrer" loading="lazy" onError={() => setFailed(src)} /> : <UserRound className={className} aria-label={alt || 'No photo'} />;
}
export function ImagePicker({ label, value, onChange, photos, galleryOnly = false }: { label: string; value: string; onChange: (value: string) => void; photos: Photo[]; galleryOnly?: boolean }) {
  const input = useRef<HTMLInputElement>(null);
  const valid = !value || imageUrl(value) || photos.some(photo => photo.url === value);
  useEffect(() => { input.current?.setCustomValidity(valid ? '' : 'Use a complete HTTPS image link.'); }, [valid]);
  return <fieldset className="image-picker"><legend>{label}</legend><div className="image-picker-preview">{value && valid ? <PhotoImage src={value} alt={`${label} preview`} /> : <ImagePlus size={28} />}</div>{!galleryOnly && <label>Image link<input ref={input} aria-label={`${label} URL`} type="text" maxLength={2048} placeholder="https://…" value={value.startsWith('data:') ? '' : value} onChange={e => onChange(e.target.value.trim())} /></label>}{!valid && <p role="alert" className="pin-error">Use a complete HTTPS image link.</p>}{photos.length > 0 && <><p className="muted">{galleryOnly ? 'Choose from your gallery' : 'Or choose from your gallery'}</p><div className="image-picker-gallery">{photos.map(photo => <button type="button" key={photo.id} aria-label={`Select gallery photo ${photo.id}`} aria-pressed={value === photo.url} onClick={() => onChange(photo.url)}><PhotoImage src={photo.url} alt="Gallery photo" /></button>)}</div></>}{value && <button type="button" className="text-button" onClick={() => onChange('')}>Remove image</button>}</fieldset>;
}
