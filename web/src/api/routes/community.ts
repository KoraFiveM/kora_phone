import type { HandlerSet } from '../routeTypes';
import { uploadMedia } from '../upload';

/** Media upload is the one request left here: Camera, Pulse and Flash reach it through phone.media.upload. */
export const communityRoutes: HandlerSet<'uploadMedia'> = {
    uploadMedia: p => uploadMedia(p),
};
