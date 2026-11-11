#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");
const storage = read("server/integrations/storage.lua");
const service = read("server/services/media.lua");
const camera = read("client/camera.lua");
const repository = read("server/repositories/media.lua");
const callbacks = read("server/modules/media_callbacks.lua");

for (const provider of ["disabled", "local-development", "external", "fivemanage"]) {
  assert(storage.includes(`'${provider}'`), `missing storage provider: ${provider}`);
}

assert.match(service, /ticket\.source\s*~=\s*source/, "upload ticket must be source-bound");
assert.match(service, /device\.id\s*~=\s*ticket\.deviceId/, "upload ticket must be device-bound");
assert.match(service, /Media\.tickets\[token\]\s*=\s*nil/, "upload tokens must be consumed or expired");
assert.match(storage, /AllowedMimeTypes/, "MIME allowlist missing");
assert.match(storage, /MaxBytes/, "size limit missing");
assert.match(storage, /MaxWidth/, "image width limit missing");
assert.match(storage, /MaxHeight/, "image height limit missing");
assert.match(storage, /#encoded > math\.ceil\(ticket\.byteSize \* 4 \/ 3\)/,
  "local capture must reject oversized base64 before decoding");
assert.match(storage, /hostAllowed\(response\.publicUrl/, "verified public URL host allowlist missing");
assert.match(repository, /referenceCount/, "reference-safe deletion check missing");
assert.match(camera, /instruction\.uploadUrl/, "client must consume server-issued upload URL");
assert.doesNotMatch(camera, /payload\.(?:url|uploadUrl)/, "client payload must not provide an upload URL");
assert.doesNotMatch(service, /payload\.(?:url|publicUrl|storageKey)/, "server must not persist client-provided storage locations");
assert.match(callbacks, /'requestMediaUpload', 'mediaUpload'/, "media tickets need a dedicated rate limit");

console.log("PASS media-contract: provider, token, ownership, allowlist and deletion boundaries present");
