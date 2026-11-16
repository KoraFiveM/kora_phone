---
title: Acceptance tests
sidebar_position: 20
---

# v1 acceptance tests

A manual and automation plan for release testing. The scripted checks (`test/run.sh`, see `tests/README.md`) cover only part of it.

## Global release gates

- Every identity, money, job, permission, ownership and call-state decision is server-authoritative.
- Inputs are type checked, bounded, rate limited and safe to render.
- Resource/player disconnects do not leave NUI focus, call sessions or voice channels behind.
- Lists are paginated and private events target only relevant players.
- All critical flows pass with two real clients and after reconnect/restart.

## Phone shell

- Open is denied without the required item and succeeds with it.
- Lock, home, back, close and app switching work consistently.
- Notification taps open the exact referenced conversation, post, listing or job event.
- Character settings, badge counts and app state survive reconnect.
- Removing the item or switching character closes the phone safely.

## Calls and contacts

- Add/edit/delete/search contacts and dial a saved or raw number.
- Accept creates exactly one call; reject/cancel/busy/offline/blocked states are correct.
- Either party can hang up, and death/disconnect/resource restart cleans both endpoints.
- Simultaneous cross-calls cannot create duplicate sessions.
- Clients cannot spoof a number or join an arbitrary voice channel.

## Messages

- Online and offline messages arrive once and in order.
- Read state and badges agree after open, reconnect and pagination.
- Invalid recipients, blocked users, oversized text, malicious markup and spam are rejected.
- Image attachments render only from allowed sources.

## Camera and gallery

- Capture, preview, save, delete and attach complete successfully.
- Cancelled/failed uploads leave no database record.
- Credentials never appear in client/NUI assets.
- Unsupported URL protocols and unapproved hosts do not render.
- A 500-item gallery uses thumbnails/lazy loading without freezing.

## Banking and jobs

- Balance comes from kora_core and transfers run through kora_banking; history comes from `phone_bank_history`.
- Positive bounded transfers succeed once; insufficient, negative, replayed and forged transfers fail safely.
- A committed transfer still produces one result if the response is delayed or retried.
- Job, grade and duty come from kora_core (grades are one-based); management actions enforce grade server-side, and duty changes respect kora_multijob's duty lock.
- Missing optional job resources hide their actions without breaking the phone.

## Social and marketplace

- Handles are validated and unique under simultaneous claims.
- Feed/listing pagination has stable ordering and no duplicate rows.
- Like is idempotent; edit/delete/moderate operations enforce ownership/permission.
- Blocking removes content/interactions in both directions.
- Listing contact opens the correct seller conversation.
- Sold, deleted or expired listings reject replayed edits.

## Performance budgets

- Closed phone: no permanent zero-wait polling loop.
- Open idle client time: average below 0.10 ms; preferred below 0.05 ms.
- Warm open-to-interactive below 500 ms; cold below 1.5 s.
- Local app navigation below 100 ms.
- Server callback p95 below 250 ms excluding external uploads.
- Initial compressed NUI bundle target below 2 MB, excluding user media.
- Initial list requests return at most 50 records.
- At 64 active players, idle work does not scale through global broadcasts.

## Compatibility matrix

Test a fresh database and a restart on an existing one (tables are only added to, never migrated); 1, 2, 32, 64 and target-max players; the kora_core, kora_inventory, kora_banking and kora_voice versions you run; 16:9, 16:10 and 21:9; 50–200 ms simulated latency; resource restart, server restart, reconnect, character switch, phone removal and player death.

