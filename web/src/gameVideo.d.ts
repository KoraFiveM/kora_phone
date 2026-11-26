interface GameView {
    readonly canvas: HTMLCanvasElement;
    dispose(): void;
    isLost(): boolean;
    render(): void;
    resize(width: number, height: number, sourceWidth?: number, sourceHeight?: number, zoom?: number): void;
}
interface GameViewOptions {
    onContextLost?: () => void;
    onContextRestored?: () => void;
    preserveDrawingBuffer?: boolean;
}
export declare function createGameView(canvas: HTMLCanvasElement, options?: GameViewOptions): GameView;
export type VideoSignal = {
    kind: 'offer' | 'answer' | 'ice';
    sdp?: RTCSessionDescriptionInit;
    candidate?: RTCIceCandidateInit;
};
export declare class GameVideo {
    private peer?;
    private cameraToken?;
    private stream?;
    private remote;
    private view?;
    private animation;
    private generation;
    private makingOffer;
    private ignoreOffer;
    private settingAnswer;
    private polite;
    private paused;
    private front;
    private candidates;
    private receiveQueue;
    private retryTimer?;
    private disconnectTimer?;
    private restarts;
    private onSignal;
    private onError;
    start(iceServers: RTCIceServer[], polite: boolean, onSignal: (signal: VideoSignal) => void, onStream: (stream: MediaStream, local: boolean) => void, onError: (message: string) => void): Promise<void>;
    receive(signal: VideoSignal): Promise<void>;
    setPaused(paused: boolean): void;
    flip(): Promise<void>;
    stop(): void;
    private restart;
    private errorText;
    private fail;
}
export {};
