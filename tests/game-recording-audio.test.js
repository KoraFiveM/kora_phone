// Mic audio in Camera clips: web/src/gameRecording.ts with an audio stream passed in.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const ts = require('../web/node_modules/typescript');
const source = ts.transpileModule(fs.readFileSync('web/src/gameRecording.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
let recorder, options, supported;
class Recorder {
  static isTypeSupported(type) { return supported(type); }
  constructor(stream, opts) { this.state = 'inactive'; this.stream = stream; options = opts; recorder = this; }
  start() { this.state = 'recording'; }
  stop() { this.state = 'inactive'; this.onstop(); }
  chunk(size) { this.ondataavailable({ data: new Blob(['x'.repeat(size)]) }); }
}
class Stream { constructor(tracks) { this.tracks = tracks; } getTracks() { return this.tracks; } getAudioTracks() { return this.tracks.filter(t => t.kind === 'audio'); } getVideoTracks() { return this.tracks.filter(t => t.kind === 'video'); } }
const track = kind => ({ kind, stopped: 0, stop() { this.stopped++; } });
const context = { exports: {}, Blob, MediaRecorder: Recorder, MediaStream: Stream, setTimeout() { return 1; }, clearTimeout() {} };
vm.runInNewContext(source, context);
const setup = () => { const video = track('video'); const audio = track('audio'); return { video, audio, canvas: { captureStream: () => new Stream([video]) }, mic: new Stream([audio]) }; };
(async () => {
  supported = type => type.startsWith('video/webm');
  let { video, audio, canvas, mic } = setup();
  let capture = context.exports.recordGameClip(canvas, 15, 100, mic);
  assert.equal(recorder.stream.getTracks().map(t => t.kind).join(','), 'video,audio');
  assert.equal(options.mimeType, 'video/webm;codecs=vp8,opus'); assert.equal(options.audioBitsPerSecond, 64000);
  recorder.chunk(4); capture.stop();
  assert.equal((await capture.result).type, 'video/webm');
  assert.equal(video.stopped, 1); assert.equal(audio.stopped, 1);
  ({ video, audio, canvas, mic } = setup());
  capture = context.exports.recordGameClip(canvas, 15, 100, mic); capture.cancel();
  await assert.rejects(capture.result, /cancelled/); assert.equal(audio.stopped, 1);
  ({ audio, canvas, mic } = setup());
  supported = () => false;
  assert.throws(() => context.exports.recordGameClip(canvas, 15, 100, mic), /cannot record/); assert.equal(audio.stopped, 1);
  supported = type => type.startsWith('video/webm');
  ({ canvas } = setup());
  context.exports.recordGameClip(canvas, 15, 100);
  assert.equal(options.audioBitsPerSecond, undefined); assert.equal(options.mimeType, 'video/webm;codecs=vp8');
  console.log('PASS game recording audio: mic track muxed with opus, released on stop/cancel/failure, silent path unchanged');
})().catch(error => { console.error(error); process.exitCode = 1; });
