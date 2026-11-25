export declare function recordGameClip(canvas: HTMLCanvasElement, seconds: number, maxBytes: number, audio?: MediaStream): {
    result: Promise<Blob>;
    stop: () => void;
    cancel: (message?: string) => void;
};
export declare function openMicrophone(timeoutMs?: number): Promise<MediaStream | undefined>;
