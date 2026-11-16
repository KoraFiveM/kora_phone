import type { MediaKind } from '../../types';

/** Server timestamps are unix seconds; the screens want ISO strings. */
export const stamp = (value?: number | string | null): string =>
    typeof value === 'number' ? new Date(value * 1000).toISOString() : String(value || new Date().toISOString());

/** Photo or video, from the media's mime type. Undefined when there is no media at all. */
export const kindOf = (mime?: string | null, url?: string | null): MediaKind | undefined =>
    url ? (String(mime || '').startsWith('video/') ? 'video' : 'photo') : undefined;

export const items = <T>(page: { items?: T[] } | T[] | null | undefined): T[] =>
    Array.isArray(page) ? page : page?.items ?? [];
