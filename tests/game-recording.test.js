const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('../web/node_modules/typescript');
const source = ts.transpileModule(fs.readFileSync('web/src/gameRecording.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
let recorder, stopped, timer, timeout;
class Recorder {
  static isTypeSupported(type) { return type.startsWith('video/webm'); }
  constructor(stream) { this.state = 'inactive'; recorder = this; assert.equal(stream.audio, false); }
  start() { this.state = 'recording'; }
  stop() { this.state = 'inactive'; this.onstop(); }
  chunk(size) { this.ondataavailable({ data: new Blob(['x'.repeat(size)]) }); }
}
const context = { exports: {}, Blob, MediaRecorder: Recorder,
  setTimeout(fn, ms) { timer = fn; timeout = ms; return 1; }, clearTimeout() {},
};
vm.runInNewContext(source, context);
const canvas = { captureStream(fps) { assert.equal(fps, 20); return { audio: false, getTracks: () => [{ stop() { stopped++; } }] }; } };
const start = (seconds = 15, bytes = 100) => { stopped = 0; return context.exports.recordGameClip(canvas, seconds, bytes); };
(async () => {
  let capture = start();
  recorder.chunk(5); capture.stop();
  let blob = await capture.result;
  assert.equal(blob.size, 5); assert.equal(blob.type, 'video/webm'); assert.equal(stopped, 1);
  capture = start(15); recorder.chunk(3); assert.equal(timeout, 15000); timer();
  assert.equal((await capture.result).size, 3); assert.equal(stopped, 1);
  capture = start(120); assert.equal(timeout, 60000); capture.cancel();
  await assert.rejects(capture.result, /cancelled/); assert.equal(stopped, 1);
  capture = start(15, 2); recorder.chunk(3);
  await assert.rejects(capture.result, /too large/); assert.equal(stopped, 1);
  capture = start(); capture.stop();
  await assert.rejects(capture.result, /empty recording/); assert.equal(stopped, 1);
  capture = start(); recorder.onerror();
  await assert.rejects(capture.result, /recording failed/); assert.equal(stopped, 1);
  console.log('PASS game recording: canvas capture, stop, duration, size limit, cancellation and errors');
})().catch(error => { console.error(error); process.exitCode = 1; });
