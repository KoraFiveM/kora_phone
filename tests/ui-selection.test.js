#!/usr/bin/env node
"use strict";
// Phone UI text must not be selectable, except in fields the player types into.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
const css = fs.readFileSync(path.join(root, "web/src/style.css"), "utf8");
const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m => ({ selector: m[1].replace(/\/\*[\s\S]*?\*\//g, "").trim(), body: m[2] }));
const find = (text, predicate) => rules.find(rule => rule.selector.includes(text) && predicate(rule.body));

assert.ok(find("#root", b => /(^|[;\s])user-select:\s*none/.test(b) && /-webkit-user-select:\s*none/.test(b)), "root disables text selection");
assert.ok(find("img", b => /-webkit-user-drag:\s*none/.test(b)), "images cannot be dragged out");
for (const selector of ["input", "textarea", "[contenteditable]"]) {
  assert.ok(find(selector, b => /(^|[;\s])user-select:\s*text/.test(b) && /-webkit-user-select:\s*text/.test(b)), `${selector} stays selectable`);
}
console.log("PASS ui-selection");
