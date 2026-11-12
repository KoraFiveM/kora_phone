---
title: Community security
sidebar_position: 16
---

# Community security model

The community module treats NUI and client payloads as untrusted requests. It derives the acting device and character from `source`; callers cannot supply an owner, author, seller, reporter or moderator identity.

## Social controls

- Handles are normalized to lowercase and restricted to 3–24 ASCII letters, numbers or underscores. Database uniqueness is authoritative.
- Posts and comments require bounded text and an 8–64 character client request ID. Unique database constraints make retrying creation idempotent.
- Post deletion is scoped to the authenticated profile. Likes and follows are represented by unique relationship rows.
- Feed and comment queries exclude both directions of a block. Private profiles appear in feeds only to the owner or an existing follower.
- Blocking removes follows in both directions. Profiles, posts and comments behind either direction of a block respond as not found to avoid leaking relationship state.
- Suspended profiles cannot create or interact with content and are excluded from feeds.

## Marketplace controls

- Listings are contact-only in v1. No purchase callback, inventory transfer, debit or payout exists.
- Price is a bounded display integer and does not authorize a financial transaction.
- Create operations require an idempotency key. Updates, removal and sold state are scoped to the server-resolved owner and active listing.
- Listing queries exclude sellers blocked in either direction.
- Contacting a seller reuses the normal messaging service, including its server-side recipient resolution, persistence and idempotency. Seller phone numbers are never returned by listing APIs.

## Reports and moderation

- Reports use allowlisted target types and reasons, bounded details, and a database uniqueness constraint against repeated reports of the same target by one device.
- A sanitized snapshot is stored at report time so later deletion does not erase evidence.
- Queue access and resolution require either the `kora.phone.moderate` ACE or QBCore `admin`/`god` permission. Opening a staff UI grants no authority.
- Resolution actions are allowlisted. Each successful action creates an append-only audit record containing actor, action, target, reason and report ID.
- Configure ACE access explicitly, for example `add_ace group.admin kora.phone.moderate allow` (see [Permissions](./permissions.md)).

## Operational requirements

- `server/modules/community_callbacks.lua` registers these callbacks and is loaded by the manifest after repositories, services, rate limits and permissions.
- Map NUI routes only to the named callbacks; unknown routes must receive a bounded error response.
- Add stricter per-action rate rules in server configuration for production. Callback keys are isolated (`community.post`, `community.comment`, `community.listing`, `community.report`, and others), each with its own bucket in `Config.Server.RateLimits`.
- Retain moderation audit records independently of user-generated content retention. Do not log post, message or report bodies in server console output.
