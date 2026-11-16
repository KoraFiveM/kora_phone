/** Codes the game scripts return, in words a player can act on (pairs, so code names stay plain data). */
export const friendlyErrors: Readonly<Record<string, string>> = Object.fromEntries([
    ['SCREENSHOT_PROVIDER_UNAVAILABLE', 'The camera needs the screenshot-basic resource running'],
    ['MEDIA_DISABLED', 'Photo storage is not set up on this server'],
    ['CAMERA_NOT_OPEN', 'The camera is not ready. Try again.'],
    ['UPLOAD_FAILED', 'The photo could not be uploaded'],
    ['PLAYER_DEAD', 'You cannot use the camera right now'],
    ['SESSION_CHANGED', 'Your phone changed while that was working. Try again.'],
    ['EMPTY_SERVER_RESPONSE', 'The server did not answer. Try again.'],
    ['INVALID_SERVER_RESPONSE', 'The server sent something unexpected. Try again.'],
    ['MEDIA_TOO_LARGE', 'That file is too big'],
    ['UNSUPPORTED_MEDIA_TYPE', 'That kind of file is not supported'],
    ['VIDEO_UNSUPPORTED', 'This server does not take video clips yet'],
    ['PROVIDER_MISCONFIGURED', 'Uploads are not set up correctly on this server'],
    ['PROVIDER_BEGIN_FAILED', 'The media host would not start an upload. Try again later.'],
    ['UPLOAD_NOT_VERIFIED', 'The upload could not be verified'],
    ['UPLOAD_MISMATCH', 'The uploaded file did not match what was expected'],
    ['UPLOAD_NOT_BOUND', 'The upload could not be matched to this phone'],
    ['PUBLIC_HOST_DENIED', 'The media host is not on this server\'s allowlist'],
    ['UPLOAD_HOST_DENIED', 'The upload address is not on this server\'s allowlist'],
    ['UPLOAD_TOKEN_EXPIRED', 'That upload took too long. Try again.'],
    ['INVALID_UPLOAD_TOKEN', 'That upload is no longer valid. Try again.'],
    ['INVALID_RECEIPT', 'The upload receipt was not valid'],
] as const);

export type ServerError = string | { code?: string; message?: string };
export type ServerResult<T> = { ok: true; data: T } | { ok: false; error?: ServerError };

/** The text a player sees for a failed server reply. */
export function errorText(error: ServerError | undefined): string {
    const text = typeof error === 'string' ? error : error?.message || error?.code || 'Request failed';
    return friendlyErrors[text] ?? text;
}
