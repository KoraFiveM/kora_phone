import { kindOf } from './adapters/common';
import type { RawSavedMedia, RawUploadTicket } from './raw';
import { server } from './transport';
import type { MediaKind } from '../types';

const fileName = (blob: Blob): string =>
    blob.type.startsWith('video/mp4') ? 'clip.mp4' : blob.type.startsWith('video/') ? 'clip.webm' : 'photo.jpg';

/** One file straight to the media host's presigned URL. XHR (not fetch) so the UI can show progress. */
function sendFile(url: string, field: string, blob: Blob, tag: string, onProgress?: (fraction: number) => void): Promise<string> {
    return new Promise((resolve, reject) => {
        const form = new FormData();
        form.append(field, blob, fileName(blob));
        if (tag) form.append('metadata', JSON.stringify({ koraPhoneTicket: tag }));
        const xhr = new XMLHttpRequest();
        xhr.open('POST', url);
        xhr.timeout = 90000;
        xhr.upload.onprogress = e => { if (e.lengthComputable) onProgress?.(e.loaded / e.total); };
        xhr.onload = () => {
            try {
                const reply = JSON.parse(xhr.responseText) as { data?: { id?: unknown }; receipt?: unknown } | null;
                const id = reply?.data?.id ?? reply?.receipt;
                if (xhr.status >= 200 && xhr.status < 300 && typeof id === 'string') return resolve(id);
            } catch { /* fall through */ }
            reject(new Error('The media host did not accept the upload'));
        };
        xhr.onerror = () => reject(new Error('The upload could not reach the media host'));
        xhr.ontimeout = () => reject(new Error('The upload took too long'));
        xhr.send(form);
    });
}

/** The server hands out a one-use upload ticket, the phone uploads the file, then the server checks what arrived. */
export async function uploadMedia(p: { blob: Blob; onProgress?: (fraction: number) => void }): Promise<{ id: number; url: string; kind: MediaKind }> {
    const ticket = await server<RawUploadTicket>('media:request', {
        mimeType: (p.blob.type || '').split(';')[0],
        byteSize: p.blob.size,
    });
    const up = ticket?.upload;
    if (!up || !['direct-upload', 'multipart-upload'].includes(up.mode ?? '') || typeof up.uploadUrl !== 'string') {
        throw new Error('This server cannot take uploads from the phone');
    }
    const receipt = await sendFile(up.uploadUrl, String(up.field || 'file'), p.blob, typeof up.tag === 'string' ? up.tag : '', p.onProgress);
    const saved = await server<RawSavedMedia>('media:complete', { token: up.token, receipt });
    return { id: Number(saved.id), url: String(saved.publicUrl), kind: kindOf(saved.mimeType, saved.publicUrl) || 'photo' };
}
