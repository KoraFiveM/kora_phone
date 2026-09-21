import { useEffect, useRef, useState } from 'react';

export function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error('Could not read the recording.'));
    reader.readAsDataURL(blob);
  });
}

export function useClipRecorder(seconds: number) {
  const [recording, setRecording] = useState(false);
  const [clip, setClip] = useState<{ blob: Blob; url: string }>();
  const session = useRef(0);
  const stream = useRef<MediaStream | undefined>(undefined);
  const recorder = useRef<MediaRecorder | undefined>(undefined);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const url = useRef('');
  const clear = () => {
    session.current++;
    clearTimeout(timer.current);
    if (recorder.current?.state === 'recording') recorder.current.stop();
    stream.current?.getTracks().forEach(track => track.stop());
    stream.current = undefined;
    recorder.current = undefined;
    if (url.current) URL.revokeObjectURL(url.current);
    url.current = '';
  };
  const discardClip = () => { clear(); setClip(undefined); setRecording(false); };
  const stopRecording = () => {
    clearTimeout(timer.current);
    if (recorder.current?.state === 'recording') recorder.current.stop();
    setRecording(false);
  };
  const start = async () => {
    discardClip();
    const token = session.current;
    if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === 'undefined') throw new Error('Webcam recording is unavailable in this browser. Photo capture is still available.');
    const media = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    if (token !== session.current) { media.getTracks().forEach(track => track.stop()); return; }
    stream.current = media;
    try {
      const mimeType = ['video/webm;codecs=vp8,opus', 'video/webm', 'video/mp4'].find(type => MediaRecorder.isTypeSupported(type));
      if (!mimeType) throw new Error('This browser cannot record supported video clips.');
      const rec = new MediaRecorder(media, { mimeType, videoBitsPerSecond: 1000000, audioBitsPerSecond: 64000 });
      const chunks: Blob[] = [];
      rec.ondataavailable = event => { if (event.data.size) chunks.push(event.data); };
      rec.onstop = () => {
        media.getTracks().forEach(track => track.stop());
        if (token !== session.current) return;
        setRecording(false);
        // Uploads use a simple MIME type; browser codec parameters are not part of the data URI contract.
        const blob = new Blob(chunks, { type: mimeType.split(';')[0] });
        if (!blob.size) return;
        url.current = URL.createObjectURL(blob);
        setClip({ blob, url: url.current });
      };
      recorder.current = rec; rec.start(); setRecording(true);
      timer.current = setTimeout(stopRecording, Math.min(60, Math.max(1, seconds)) * 1000);
    } catch (error) { clear(); throw error; }
  };
  useEffect(() => () => clear(), []);
  return { recording, clip, discardClip, stopRecording, start };
}
