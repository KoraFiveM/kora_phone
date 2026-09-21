// Shared locations and photos travel in the normal text body as a small token, so they work with the
// server's text-only message contract. Anything that does not parse stays ordinary text.
export type Token = { kind: 'location'; x: number; y: number; label: string } | { kind: 'photo'; url: string } | { kind: 'video'; url: string };
const clean = (label: string) => label.replace(/[[\]|]/g, '').trim().slice(0, 60);
export const locationBody = (place: { x: number; y: number; label: string }) => `[[loc:${place.x},${place.y}|${clean(place.label)}]]`;
export const photoBody = (url: string) => `[[photo:${url}]]`;
export const videoBody = (url: string) => `[[video:${url}]]`;
export function parseToken(body: string): Token | null {
  const place = /^\[\[loc:(-?\d{1,5}(?:\.\d)?),(-?\d{1,5}(?:\.\d)?)\|([^\]|]{0,60})\]\]$/.exec(body);
  if (place) return { kind: 'location', x: Number(place[1]), y: Number(place[2]), label: place[3] };
  const media = /^\[\[(photo|video):(https:\/\/[^\s\]]{1,1900})\]\]$/.exec(body);
  return media ? { kind: media[1] as 'photo' | 'video', url: media[2] } : null;
}
/** One-line summary for lists and notifications. */
export function previewText(body?: string | null): string {
  const token = body ? parseToken(body) : null;
  return token ? (token.kind === 'location' ? 'Shared a location' : token.kind === 'video' ? 'Sent a clip' : 'Sent a photo') : body || '';
}
