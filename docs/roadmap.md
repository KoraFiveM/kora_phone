# Phased roadmap

## Phase 1 — foundation

- QBCore bridge, declarative SQL schema and phone identity
- Inventory ownership check and phone open/close lifecycle
- NUI shell, app routing, settings and reusable notifications
- Shared validation, rate limiting, logging and pagination conventions

Exit: two characters retain unique numbers and settings across reconnects; NUI focus never becomes trapped.

## Phase 2 — communications

- Contacts and recent calls
- Ringing, accept/reject, hang-up and voice routing
- One-to-one messages, unread counts, offline delivery and pagination
- Block list and disconnect/resource-restart cleanup

Exit: two real clients pass the complete call/message and failure-path suite without duplicate state.

## Phase 3 — media

- Camera capture, upload adapter and gallery
- Preview/delete, thumbnails, lazy loading and media picker
- Image attachments for Messages

Exit: failed/cancelled uploads create no broken records; 500 gallery records remain responsive.

## Phase 4 — economy and jobs

- Balance/history and idempotent player transfers
- Job/grade display, duty state, colleagues and configurable job notices/actions

Exit: replayed transfers cannot duplicate money movement and job permissions cannot be forged.

## Phase 5 — community

- Shared profiles, handles, blocking and moderation primitives
- One social feed with text/images, likes and comments
- Contact-only marketplace with listings, search and seller deep links

Exit: ownership, block and pagination tests pass with 10,000 seeded listings/posts.

## Phase 6 — hardening and release

- Security, accessibility, localisation and compatibility passes
- Two-client end-to-end tests, target-player load test and restart recovery
- Clean-install/upgrade documentation and release packaging

## Deliberate v1 cuts

Defer group/video calls, voicemail audio, group/disappearing chats, stories, livestreaming, multiple social networks, marketplace escrow/auctions, crypto/stocks/loans, and a third-party app store. The v1 marketplace connects buyers and sellers; it does not move items or money.

