#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const workflow = fs.readFileSync(path.join(__dirname, "../.github/workflows/release.yml"), "utf8");
const bump = workflow.match(/- name: Bump fxmanifest\.lua version\n\s+run: \|\n((?: {10}.+\n|\n)+)/);
assert.ok(bump, "release workflow must contain the version-bump script");
assert.match(workflow, /push:\s*\n\s+branches:\s*\[dev\]/, "release workflow must run on dev");
const script = bump[1].replace(/^ {10}/gm, "").replaceAll("${{ steps.tag.outputs.new_version }}", "1.2.3");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "kora-release-test-"));
try {
  const remote = path.join(tmp, "remote.git");
  const work = path.join(tmp, "work");
  fs.mkdirSync(work);
  const git = (...args) => execFileSync("git", args, { cwd: work, stdio: "pipe", encoding: "utf8" }).trim();
  git("init", "--bare", remote);
  git("init", "-b", "dev");
  git("config", "user.name", "Test");
  git("config", "user.email", "test@example.com");
  git("remote", "add", "origin", remote);
  fs.writeFileSync(path.join(work, "fxmanifest.lua"), "version '1.2.2'\n");
  git("add", "fxmanifest.lua");
  git("commit", "-m", "initial");
  git("push", "origin", "dev");
  git("checkout", "-b", "main");
  fs.writeFileSync(path.join(work, "main-only"), "main\n");
  git("add", "main-only");
  git("commit", "-m", "main diverges");
  git("push", "origin", "main");
  const mainBefore = git("--git-dir", remote, "rev-parse", "refs/heads/main");
  git("checkout", "dev");

  const runBump = () => execFileSync("bash", ["-e", "-c", script], {
    cwd: work, env: { ...process.env, GITHUB_REF_NAME: "dev" }, stdio: "pipe"
  });
  runBump();
  assert.equal(git("--git-dir", remote, "show", "refs/heads/dev:fxmanifest.lua"), "version '1.2.3'");
  assert.equal(git("--git-dir", remote, "rev-parse", "refs/heads/main"), mainBefore);
  const devAfter = git("--git-dir", remote, "rev-parse", "refs/heads/dev");
  runBump();
  assert.equal(git("--git-dir", remote, "rev-parse", "refs/heads/dev"), devAfter);
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log("PASS release-workflow: version bump pushes only to the triggering branch");
