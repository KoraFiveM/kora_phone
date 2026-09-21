#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const manifest = path.join(root, "fxmanifest.lua");

if (!fs.existsSync(manifest)) {
  console.log("SKIP web-contract: fxmanifest.lua does not exist yet");
  process.exit(0);
}

const text = fs.readFileSync(manifest, "utf8");
const match = text.match(/ui_page\s+["']([^"']+)["']/);
assert.ok(match, "fxmanifest.lua must declare ui_page");

const uiEntry = path.resolve(root, match[1]);
assert.ok(uiEntry.startsWith(root + path.sep), "ui_page must remain inside the resource");
if (!fs.existsSync(uiEntry)) {
  console.log(`SKIP web-contract: declared UI build entry does not exist yet (${match[1]})`);
  process.exit(0);
}

const html = fs.readFileSync(uiEntry, "utf8");
assert.match(html, /<meta[^>]+charset=/i, "UI entry should declare charset");
assert.match(html, /<meta[^>]+viewport/i, "UI entry should declare viewport");
assert.doesNotMatch(html, /<script[^>]+src=["']https?:\/\//i, "Remote scripts are not allowed in the phone entry page");
console.log("PASS web-contract: manifest and UI entry contract valid");
