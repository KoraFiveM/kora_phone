// Own only the recording tracks; the camera screen owns the renderer and canvas.
export function recordGameClip(canvas: HTMLCanvasElement, seconds: number, maxBytes: number) {
  if (typeof MediaRecorder === 'undefined' || !canvas.captureStream) throw new Error('Video recording is unavailable in this browser.');
  const mimeType = ['video/webm;codecs=vp8', 'video/webm', 'video/mp4'].find(type => MediaRecorder.isTypeSupported(type));
  if (!mimeType) throw new Error('This browser cannot record supported video clips.');
  const stream = canvas.captureStream(20);
  let recorder: MediaRecorder;
  try { recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 1500000 }); }
  catch (error) { stream.getTracks().forEach(track => track.stop()); throw error; }
  let settled = false;
  let timer: ReturnType<typeof setTimeout>;
  let rejectResult: (error: Error) => void;
  const release = () => { clearTimeout(timer); stream.getTracks().forEach(track => track.stop()); };
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
