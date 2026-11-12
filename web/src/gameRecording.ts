// Own only the recording tracks; the camera screen owns the renderer and canvas.
// `audio` (optional) is the player's own microphone. Once passed in, its tracks belong to the recording and are
// stopped with it. Without it the clip is silent, exactly as before.
export function recordGameClip(canvas: HTMLCanvasElement, seconds: number, maxBytes: number, audio?: MediaStream) {
  const stopAudio = () => audio?.getTracks().forEach(track => track.stop());
  if (typeof MediaRecorder === 'undefined' || !canvas.captureStream) { stopAudio(); throw new Error('Video recording is unavailable in this browser.'); }
  const withAudio = !!audio && audio.getAudioTracks().length > 0;
  const types = withAudio ? ['video/webm;codecs=vp8,opus', 'video/webm', 'video/mp4'] : ['video/webm;codecs=vp8', 'video/webm', 'video/mp4'];
  const mimeType = types.find(type => MediaRecorder.isTypeSupported(type));
  if (!mimeType) { stopAudio(); throw new Error('This browser cannot record supported video clips.'); }
  const video = canvas.captureStream(20);
  const stream = withAudio && audio ? new MediaStream([...video.getVideoTracks(), ...audio.getAudioTracks()]) : video;
  const release = () => { clearTimeout(timer); video.getTracks().forEach(track => track.stop()); stopAudio(); };
  let recorder: MediaRecorder;
  try { recorder = new MediaRecorder(stream, withAudio ? { mimeType, videoBitsPerSecond: 1500000, audioBitsPerSecond: 64000 } : { mimeType, videoBitsPerSecond: 1500000 }); }
  catch (error) { video.getTracks().forEach(track => track.stop()); stopAudio(); throw error; }
  let settled = false;
  let timer: ReturnType<typeof setTimeout>;
  let rejectResult: (error: Error) => void;
  const cancel = (message = 'Recording cancelled.') => {
    if (settled) return;
    settled = true;
    if (recorder.state !== 'inactive') recorder.stop();
    release(); rejectResult(new Error(message));
  };
  const result = new Promise<Blob>((resolve, reject) => {
    rejectResult = reject;
    const chunks: Blob[] = [];
    let bytes = 0;
    recorder.ondataavailable = event => {
      if (settled || !event.data.size) return;
      bytes += event.data.size;
      if (bytes > maxBytes) { cancel('The recording is too large. Try a shorter clip.'); return; }
      chunks.push(event.data);
    };
    recorder.onerror = () => cancel('Video recording failed. Please try again.');
    recorder.onstop = () => {
      if (settled) return;
      settled = true; release();
      if (!bytes) { reject(new Error('The camera produced an empty recording.')); return; }
      resolve(new Blob(chunks, { type: mimeType.split(';')[0] }));
    };
    try {
      recorder.start(250);
      timer = setTimeout(() => { if (recorder.state === 'recording') recorder.stop(); }, Math.min(60, Math.max(1, seconds)) * 1000);
    } catch (error) { settled = true; release(); reject(error); }
  });
  return { result, stop: () => { if (!settled && recorder.state === 'recording') recorder.stop(); }, cancel };
}

// The player's own microphone through FiveM's browser (CEF). FiveM asks the player once and remembers the answer;
// it always uses the Windows default input device. Resolves undefined when it is refused, missing or the player
// does not answer within `timeoutMs`; a stream that arrives after the timeout is stopped at once.
export function openMicrophone(timeoutMs = 15000): Promise<MediaStream | undefined> {
  if (!navigator.mediaDevices?.getUserMedia) return Promise.resolve(undefined);
  return new Promise(resolve => {
    let done = false;
    const timer = setTimeout(() => { done = true; resolve(undefined); }, timeoutMs);
    navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false })
      .then(stream => {
        if (done) { stream.getTracks().forEach(track => track.stop()); return; }
        done = true; clearTimeout(timer);
        resolve(stream.getAudioTracks().length ? stream : (stream.getTracks().forEach(track => track.stop()), undefined));
      })
      .catch(() => { if (!done) { done = true; clearTimeout(timer); resolve(undefined); } });
  });
}
