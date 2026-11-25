/** Shapes the server sends, before the adapters rename them for the screens. */
export type Flag = boolean | 0 | 1 | undefined | null;

export interface Page<T> { items?: T[] }

export interface RawContact { id: number | string; displayName?: string; phoneNumber?: string; photo?: string; isFavorite?: Flag }
export interface RawMedia { id: number | string; publicUrl: string; mimeType?: string; createdAt?: number }
export interface RawCall { id: number | string; status: string; remoteNumber?: string; direction?: 'incoming' | 'outgoing' }
export interface RawConversation {
    type?: string; title?: string | null; peerPhoneNumber?: string | null; lastMessagePreview?: string | null;
    lastMediaMime?: string | null; lastMessageAt?: number | string | null; [key: string]: unknown;
}
export interface RawMessage {
    senderNumber?: string; createdAt?: number | string; mediaUrl?: string | null; mediaMime?: string | null; [key: string]: unknown;
}
export interface RawListing { id: number; sellerHandle?: string; sellerName?: string; title: string; description?: string; price: number; createdAt?: number | string; isOwner?: boolean }
export interface RawPost {
    id: number; handle?: string; displayName?: string; body: string; createdAt?: number | string; likeCount?: number;
    commentCount?: number; liked?: Flag; mine?: Flag; mediaUrl?: string | null; mediaMime?: string | null;
}
export interface RawComment { id: number; handle?: string; displayName?: string; body: string; createdAt?: number | string }
export interface RawMail { id: number; peer: string; subject: string; body: string; hasAction?: Flag; unread?: Flag; createdAt?: number | string }
export interface RawSdkApp {
    id: string; name?: string; description?: string; icon?: string; entry?: string; version?: string; resource?: string; url?: string;
    permissions?: unknown; job?: unknown; defaultInstalled?: Flag; price?: number; installed?: Flag;
}
export interface RawUpload { mode?: string; uploadUrl?: unknown; field?: unknown; tag?: unknown; token?: unknown }
export interface RawUploadTicket { upload?: RawUpload }
export interface RawSavedMedia { id: number | string; publicUrl: string; mimeType?: string }

export interface RawBootstrap {
    device?: { id?: string | number; model?: 'standard' | 'flip' | 'fold'; phoneNumber?: string | number; settings?: Record<string, unknown> };
    contacts?: RawContact[];
    items?: { stations?: unknown[] };
    apps?: Record<string, boolean>;
    appStore?: boolean;
    security?: { locked?: boolean; hasPin?: boolean };
    moderator?: boolean;
    admin?: boolean;
    character?: { firstName?: string; lastName?: string };
    locations?: unknown[];
    features?: {
        homeReorder?: boolean; galleryViewer?: boolean; transfers?: boolean; media?: boolean; maps?: boolean;
        property?: boolean; garage?: boolean;
        video?: { iceServers?: unknown[] };
        flash?: { maxSeconds?: number | string; maxBytes?: number | string };
    };
}

/** Same as `Boolean(value)` but spelled for the server's `0 | 1 | true | false` convention. */
export const isFlag = (value: Flag): boolean => value === 1 || value === true;
