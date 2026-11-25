// Webcam and microphone clip recorder for apps that declare the `record` permission (the phone then lets their frame use
// getUserMedia). Records at most `seconds`, keeps the clip in memory, and always releases the camera.
export function createClipRecorder(seconds, onChange = () => {}) {
    let session = 0;
    let stream;
    let recorder;
    let timer;
    let url = '';
    const state = { recording: false, clip: undefined };
    const emit = () => onChange({ ...state });

    const clear = () => {
        session += 1;
        clearTimeout(timer);
        if (recorder && recorder.state === 'recording') recorder.stop();
        if (stream) stream.getTracks().forEach(track => track.stop());
        stream = undefined; recorder = undefined;
        if (url) URL.revokeObjectURL(url);
        url = '';
    };
    const discard = () => { clear(); state.clip = undefined; state.recording = false; emit(); };
    const stop = () => {
        clearTimeout(timer);
        if (recorder && recorder.state === 'recording') recorder.stop();
        state.recording = false; emit();
    };
    const start = async () => {
        discard();
        const token = session;
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || typeof MediaRecorder === 'undefined') throw new Error('Webcam recording is unavailable here. Photo capture is still available.');
        const media = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        if (token !== session) { media.getTracks().forEach(track => track.stop()); return; }
        stream = media;
        try {
            const mimeType = ['video/webm;codecs=vp8,opus', 'video/webm', 'video/mp4'].find(type => MediaRecorder.isTypeSupported(type));
            if (!mimeType) throw new Error('This browser cannot record supported video clips.');
            const rec = new MediaRecorder(media, { mimeType, videoBitsPerSecond: 1000000, audioBitsPerSecond: 64000 });
            const chunks = [];
            rec.ondataavailable = event => { if (event.data.size) chunks.push(event.data); };
            rec.onstop = () => {
                media.getTracks().forEach(track => track.stop());
                if (token !== session) return;
                state.recording = false;
                // Uploads use a plain MIME type; codec parameters are not part of the upload contract.
                const blob = new Blob(chunks, { type: mimeType.split(';')[0] });
                if (blob.size) { url = URL.createObjectURL(blob); state.clip = { blob, url }; }
                emit();
            };
            recorder = rec; rec.start(); state.recording = true; emit();
            timer = setTimeout(stop, Math.min(60, Math.max(1, seconds)) * 1000);
        } catch (error) { clear(); throw error; }
    };
    return { start, stop, discard, state: () => ({ ...state }) };
}
