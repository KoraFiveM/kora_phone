#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const webRoots = ["web", "ui", "html", "nui"].map((p) => path.join(root, p));
const allowedExtensions = new Set([".js", ".jsx", ".ts", ".tsx", ".html", ".vue", ".svelte"]);
const ignoredDirectories = new Set(["node_modules", "dist", "build", "coverage", ".git"]);

function walk(directory, output = []) {
  if (!fs.existsSync(directory)) return output;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(target, output);
    else if (allowedExtensions.has(path.extname(entry.name))) output.push(target);
  }
  return output;
}

const files = [...new Set(webRoots.flatMap((directory) => walk(directory)))];
if (files.length === 0) {
  console.log("SKIP static-security: no web source files exist yet");
  process.exit(0);
}

const rules = [
  { name: "dynamic code execution", regex: /\b(?:eval|Function)\s*\(/g },
  { name: "document.write", regex: /\bdocument\.write\s*\(/g },
  { name: "javascript URL", regex: /javascript\s*:/gi },
  { name: "wildcard postMessage target", regex: /\.postMessage\s*\([^,]+,\s*["']\*["']/g },
  { name: "hard-coded bearer token", regex: /bearer\s+[a-z0-9._~+\/-]{20,}/gi },
  { name: "likely embedded upload secret", regex: /(?:api[_-]?key|secret|upload[_-]?token)\s*[:=]\s*["'][^"']{12,}["']/gi },
];

const findings = [];
for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  for (const rule of rules) {
    for (const match of source.matchAll(rule.regex)) {
      const line = source.slice(0, match.index).split("\n").length;
      findings.push(`${path.relative(root, file)}:${line}: ${rule.name}`);
    }
  }
}

assert.deepEqual(findings, [], `Unsafe web patterns found:\n${findings.join("\n")}`);
console.log(`PASS static-security: scanned ${files.length} web source file(s)`);

