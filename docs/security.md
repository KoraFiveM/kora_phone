---
title: Security checklist
sidebar_position: 18
---

# Security checklist

- Derive the acting character and source on the server; ignore client-supplied sender identity.
- Validate event payload shape, type, length, range and ownership before database or framework calls.
- Use allowlists for media protocols/hosts and escape all user-controlled text at render time.
- Keep database, upload, webhook and moderation credentials out of shared/client/NUI files.
- Rate limit calls (one sliding window per player and rate key, shared by all routes of that key; the phone's own limiter in `server/rate_limits.lua` is used for phone routes because kora_lib's per-callback `rateLimit` cannot share a window across callbacks; SDK app callbacks `app:<id>:<name>` do use kora_lib's `rateLimit`), messages, uploads, transfers, posts, comments, likes and listings independently.
- Make transfers, likes, accepts and other retryable actions idempotent.
- Use database transactions and uniqueness constraints for numbers, handles and money-related records.
- Never dynamically execute user data or build SQL by concatenation.
- Avoid `window.open`, unrestricted navigation, `eval`, `new Function`, and raw `innerHTML` with variable content.
- Log security rejections using identifiers and reason codes, not private content or credentials.
- Treat third-party apps as untrusted: the sandboxed iframe only reaches the server through `apps:*` routes that re-check the registered manifest permissions, the unlocked phone and the install state on the server ([App SDK](./apps.md)).
