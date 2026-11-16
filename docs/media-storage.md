---
title: Media storage
sidebar_position: 14
---

# Media storage

The gallery never accepts a URL or storage key chosen by a player. The server issues a short-lived, one-use upload token bound to the current source and owned phone device. Only the configured storage adapter may turn that token into a persisted media record.

## Provider modes

`Config.Server.Media` is a server-scoped config branch (`config/server.lua`), so it is never sent to a client. Change it in game with `/config` or in `config.local.lua` (see [Configuration](./configuration.md)). Secrets (`External.Secret`, `Fivemanage.Token`) are `sensitive`: they never show in `/config`. Put the Fivemanage token in the `kora_fivemanage_token` convar; `External.Secret` belongs in `config.local.lua`, never in a tracked file.

```lua
-- config.local.lua: only the values that differ from the defaults
return {
    Server = {
        Media = {
            Provider = 'external', -- disabled | local-development | external | fivemanage
            TokenTtlSeconds = 120,
            MaxBytes = 8 * 1024 * 1024,
            AllowedMimeTypes = { 'image/jpeg', 'image/png', 'image/webp' },
            AllowedPublicHosts = { 'uploads.example.com', 'media.example.com' },
            External = {
                BrokerUrl = 'https://uploads.example.com/v1/begin',
                VerifyUrl = 'https://uploads.example.com/v1/verify',
                DeleteUrl = 'https://uploads.example.com/v1/delete',
                Secret = 'replace-from-server-secret-store',
            },
        },
    },
}
```

Other fields: `MaxWidth`, `MaxHeight`, `AllowedVideoMimeTypes`, `MaxVideoBytes`, `MaxVideoSeconds`, `MaxImagesPerDevice`, `MaxVideosPerDay`, `LocalDirectory`, `CleanupIntervalMinutes`, `DeletedRetentionHours`, `CleanupBatchSize` and the `Fivemanage` branch. The ticket lifetime and limits are live; the provider needs a restart.

- `disabled` makes capture requests fail closed. It is also what the code falls back to when `Provider` is missing or not one of the four known values. The shipped `config/server.lua` sets `Provider = 'fivemanage'`, so set it to `disabled` if you do not want uploads.
- `local-development` asks the player's client for a screenshot (`server/integrations/storage.lua`), writes it beneath the resource, and records a resource-owned URL. It is intended only for local development. The server-side capture is requested through `Kora.screenshot.requestClient` (kora_lib validates the image bytes and returns a data URI that the phone size-checks and saves). A failed capture returns `CAPTURE_FAILED`; `SCREENSHOT_PROVIDER_UNAVAILABLE` only appears if kora_lib's screenshot module is not loaded. The default directory `local-media` is already in the manifest `files` list; another directory must be added there. FiveM lacks a portable file-delete API, so orphaned development files require manual maintenance.
- `external` asks a trusted broker for a signed multipart destination. The client receives that destination but cannot replace it. Completion persists nothing until the server calls the broker's verification endpoint and validates MIME, actual byte size, object key and final public host.

The broker's begin response must contain `uploadUrl`, `objectKey`, and optionally `field`. The upload response returned to the client must contain an opaque `receipt`. The verify response must contain:

```json
{
  "verified": true,
  "publicUrl": "https://media.example.com/object.jpg",
  "mimeType": "image/jpeg",
  "byteSize": 123456,
  "width": 1920,
  "height": 1080,
  "checksum": "sha256:..."
}
```

Provider endpoints must use HTTPS and exact hostname allowlists; the broker, verify and delete hosts must appear in `AllowedProviderHosts` or `AllowedPublicHosts`, and the upload URL host in `AllowedUploadHosts` or `AllowedPublicHosts`. The lists are merged, so putting every host in `AllowedPublicHosts` still works. Redirect destinations should be disabled or revalidated by the broker. Rotate the provider secret periodically.

## Fivemanage, and video clips

`Provider = 'fivemanage'` is the ready-made way to turn on **photos, Flash and video clips in chat** without writing a broker. Put your Fivemanage Media API token in `server.cfg` (never in a shared or client file):

```cfg
set kora_fivemanage_token "your-media-token"
```

and switch the provider on:

```lua
-- Defaults shipped in config/server.lua; override any of them in /config or config.local.lua
Config.Server.Media = {
    Provider = 'fivemanage',
    MaxVideoBytes = 24 * 1024 * 1024, -- ceiling; a 15 second clip is about 3 MB
    MaxVideoSeconds = 15,
    MaxImagesPerDevice = 300,         -- delete a photo to take more
    MaxVideosPerDay = 20,
    Fivemanage = { RequireTag = false }
}
```

How a clip gets from the phone to a post:

1. The phone records the clip (webm, capped in length and bitrate) and asks the server for an upload ticket, declaring the type and size. The server refuses anything unsupported, oversized, or over the phone's daily allowance.
2. The **server** calls Fivemanage with the API token and gets back a short-lived presigned upload URL for one file. Only that URL is sent to the phone; the token never leaves the server. The URL's host must be on the allowlist (`api.fivemanage.com`, `fmapi.net`).
3. The phone uploads the file straight to that URL, so video bytes never pass through the game server. The upload carries a random tag for this ticket.
4. The phone gives the server the file id. The server asks Fivemanage what actually arrived (its real size, type and public URL) and only then records it: size within the ticket, type matching, public host allowlisted (`r2.fivemanage.com` plus anything in `AllowedPublicHosts`, e.g. your custom CDN domain), and the tag matching. Nothing the phone reports about the file is trusted.
5. A post or message then references the stored media by id; the server checks the media belongs to the sender.

Notes and limits:

- Fivemanage's API has no delete call. Removing a photo or clip forgets it on the phone; the file stays in Fivemanage until your retention settings remove it.
- `RequireTag = true` rejects any upload that does not carry its ticket tag. It works for uploads made from the phone itself (clips), but Camera app photos, captured and uploaded by kora_lib's `Kora.screenshot.requestScreenshotUpload`, cannot carry the tag, so leave it `false` if you use the Camera app. If Fivemanage does not echo the metadata back, tag checks are skipped unless `RequireTag` is on.
- Videos are hidden from the Gallery (they live in the posts and messages that use them) and count against `MaxVideosPerDay`, not the photo limit.
- Flash and Pulse clips use the player's real webcam and microphone through the browser's recorder. Camera app clips record the game view plus, with `Config.Camera.micAudio`, the player's own microphone (see [Features](./features.md)).

## Loading and schema

The media tables (`phone_media` and `phone_gallery_links` in `server/schema.lua`) and the columns that let Flash posts and chat messages carry media (`media_id` on `phone_social_posts`/`phone_messages` in `server/schema.lua`) are created automatically at start. `server/modules/media_callbacks.lua` registers the media callbacks and is loaded by the manifest after the integrations, repositories, services, rate limits and permissions.

Gallery reads use descending ID cursors. Deletion requires device ownership and refuses media referenced by a contact or live message. Records are first soft-deleted; external objects are then deleted and the row is removed only after provider confirmation. Failed provider deletion leaves a tombstone for later cleanup rather than exposing the media again.

## Cleanup

Expired upload tickets are removed from memory every minute and all tickets disappear on resource restart. Every `CleanupIntervalMinutes` the service retries provider deletion for up to `CleanupBatchSize` tombstoned records older than `DeletedRetentionHours`. Never hard-delete the database row before provider deletion is confirmed.
