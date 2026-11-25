// Shared locations and photos travel in the normal text body as a small token, so they work with the server's
// text-only message contract. Anything that does not parse stays ordinary text.
export function parseToken(body) {
    const place = /^\[\[loc:(-?\d{1,5}(?:\.\d)?),(-?\d{1,5}(?:\.\d)?)\|([^\]|]{0,60})\]\]$/.exec(body || '');
    if (place) return { kind: 'location', x: Number(place[1]), y: Number(place[2]), label: place[3] };
    const media = /^\[\[(photo|video):(https:\/\/[^\s\]]{1,1900})\]\]$/.exec(body || '');
    return media ? { kind: media[1], url: media[2] } : null;
}

/** One-line summary for lists. */
export function previewText(body) {
    const token = parseToken(body);
    if (!token) return body || '';
    return token.kind === 'location' ? 'Shared a location' : token.kind === 'video' ? 'Sent a clip' : 'Sent a photo';
}

const clean = label => String(label).replace(/[[\]|]/g, '').trim().slice(0, 60);
export const locationBody = place => `[[loc:${place.x},${place.y}|${clean(place.label)}]]`;
export const photoBody = url => `[[photo:${url}]]`;
export const videoBody = url => `[[video:${url}]]`;
