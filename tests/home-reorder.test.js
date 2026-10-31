#!/usr/bin/env node
"use strict";
// Home-screen arranging: list helpers, pointer-event wiring (no HTML5 drag-and-drop in NUI) and the
// optional-app list shared with the server validation.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(process.argv[2] || path.join(__dirname, ".."));
const read = file => fs.readFileSync(path.join(root, file), "utf8");

let ts;
try { ts = require(path.join(root, "web/node_modules/typescript")); }
catch { console.log("SKIP home-reorder: web/node_modules/typescript is not installed"); process.exit(0); }

const { outputText } = ts.transpileModule(read("web/src/homeReorder.ts"), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } });
const mod = { exports: {} };
new Function("module", "exports", outputText)(mod, mod.exports);
const { mergeOrder, moveItem, LONG_PRESS_MS, MOVE_TOLERANCE } = mod.exports;

assert.deepEqual(mergeOrder(undefined, ["a", "b", "c"]), ["a", "b", "c"], "no saved order keeps the default");
assert.deepEqual(mergeOrder(["c", "a"], ["a", "b", "c"]), ["c", "a", "b"], "new apps append at the end");
assert.deepEqual(mergeOrder(["c", "x", "a", "c"], ["a", "c"]), ["c", "a"], "removed and repeated apps drop out");
assert.deepEqual(moveItem(["a", "b", "c", "d"], "a", "c"), ["b", "c", "a", "d"], "moving forward takes the target slot");
assert.deepEqual(moveItem(["a", "b", "c", "d"], "d", "b"), ["a", "d", "b", "c"], "moving back takes the target slot");
assert.deepEqual(moveItem(["a", "b"], "a", "a"), ["a", "b"], "dropping on itself changes nothing");
assert.deepEqual(moveItem(["a", "b"], "a", "z"), ["a", "b"], "unknown target changes nothing");
assert.ok(LONG_PRESS_MS >= 300 && LONG_PRESS_MS <= 800 && MOVE_TOLERANCE > 0, "long-press timing is sane");

const app = read("web/src/App.tsx");
assert.doesNotMatch(app, /onDragStart|onDragOver|onDrop|DragEvent/, "arranging must not rely on HTML5 drag events");
assert.match(app, /onPointerDown=\{e => beginPress\(e, item\.id, 'grid'\)\}/, "grid icons start arranging from pointer events");
assert.match(app, /onPointerDown=\{e => beginPress\(e, id, 'dock'\)\}/, "dock icons can be arranged too");
assert.match(app, /Done<\/button>/, "arranging has a Done button");
assert.match(app, /reorderAllowed &&/, "the arrange control follows Config.HomeScreen.allowReorder");
assert.match(read("web/src/api.ts"), /homeReorder:raw\.features\?\.homeReorder!==false/, "bootstrap carries the server option");

// shared/validation.lua keeps its own copy of the optional apps; it must match the catalog.
const catalog = read("web/src/catalog.ts").match(/optionalApps = \[([^\]]*)\]/)[1].match(/'([a-z]+)'/g).map(v => v.slice(1, -1)).sort();
const server = read("shared/validation.lua").match(/OPTIONAL_APPS = \{([^}]*)\}/)[1].match(/([a-z]+)=true/g).map(v => v.split("=")[0]).sort();
assert.deepEqual(server, catalog, "server OPTIONAL_APPS matches web/src/catalog.ts optionalApps");

console.log("PASS home-reorder");
