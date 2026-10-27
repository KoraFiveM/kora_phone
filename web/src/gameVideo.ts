const VERTEX_SHADER = `
  attribute vec2 a_position;
  attribute vec2 a_texcoord;
  varying vec2 v_texcoord;
  void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
    v_texcoord = a_texcoord;
  }
`

const FRAGMENT_SHADER = `
  varying highp vec2 v_texcoord;
  uniform sampler2D u_texture;
  void main() {
    gl_FragColor = texture2D(u_texture, v_texcoord);
  }
`

interface GameView {
  readonly canvas: HTMLCanvasElement
  dispose(): void
  isLost(): boolean
  render(): void
  resize(
    width: number,
    height: number,
    sourceWidth?: number,
    sourceHeight?: number,
    zoom?: number,
  ): void
}

interface GameViewOptions {
  onContextLost?: () => void
  onContextRestored?: () => void
  preserveDrawingBuffer?: boolean
}

function gameViewGeometry(
  sourceWidth: number,
  sourceHeight: number,
  targetWidth: number,
  targetHeight: number,
  zoom = 1,
): { positions: Float32Array; textureCoordinates: Float32Array } {
  const sourceAspect = sourceWidth / sourceHeight
  const targetAspect = targetWidth / targetHeight
  let left = 0
  let right = 1
  let top = 0
  let bottom = 1

  if (sourceAspect > targetAspect) {
    const visibleWidth = targetAspect / sourceAspect
    left = (1 - visibleWidth) / 2
    right = 1 - left
  } else if (sourceAspect < targetAspect) {
    const visibleHeight = sourceAspect / targetAspect
    top = (1 - visibleHeight) / 2
    bottom = 1 - top
  }

  const normalizedZoom = Math.min(3, Math.max(0.5, zoom))
  const centerX = (left + right) / 2
  const centerY = (top + bottom) / 2
  left = Math.max(0, centerX + (left - centerX) / normalizedZoom)
  right = Math.min(1, centerX + (right - centerX) / normalizedZoom)
  top = Math.max(0, centerY + (top - centerY) / normalizedZoom)
  bottom = Math.min(1, centerY + (bottom - centerY) / normalizedZoom)

  return {
    positions: new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
    textureCoordinates: new Float32Array([
      left,
      top,
      right,
      top,
      left,
      bottom,
      right,
      bottom,
    ]),
  }
}

function compileShader(
  gl: WebGLRenderingContext,
  type: number,
  source: string,
): WebGLShader {
  const shader = gl.createShader(type)
  if (!shader) throw new Error('game_view_shader_unavailable')
  gl.shaderSource(shader, source)
  gl.compileShader(shader)
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader) || 'game_view_shader_failed')
  }
  return shader
}

export function createGameView(
  canvas: HTMLCanvasElement,
  options: GameViewOptions = {},
): GameView {
  const gl = canvas.getContext('webgl', {
    alpha: false,
    antialias: false,
    depth: false,
    desynchronized: true,
    failIfMajorPerformanceCaveat: false,
    preserveDrawingBuffer: options.preserveDrawingBuffer === true,
    stencil: false,
  }) as WebGLRenderingContext | null
  if (!gl) throw new Error('game_view_unavailable')

  let lost = false
  let disposed = false
  let program: WebGLProgram | null = null
  let positionBuffer: WebGLBuffer | null = null
  let texcoordBuffer: WebGLBuffer | null = null
  let texture: WebGLTexture | null = null
  let lastSize: {
    height: number
    sourceHeight: number
    sourceWidth: number
    width: number
    zoom: number
  } | null = null

  const releaseResources = (): void => {
    if (positionBuffer) gl.deleteBuffer(positionBuffer)
    if (texcoordBuffer) gl.deleteBuffer(texcoordBuffer)
    if (texture) gl.deleteTexture(texture)
    if (program) gl.deleteProgram(program)
    positionBuffer = null
    texcoordBuffer = null
    texture = null
    program = null
  }

  const initializeResources = (): void => {
    releaseResources()
    const nextProgram = gl.createProgram()
    if (!nextProgram) throw new Error('game_view_program_unavailable')
    const vertexShader = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER)
    const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER)
    gl.attachShader(nextProgram, vertexShader)
    gl.attachShader(nextProgram, fragmentShader)
    gl.linkProgram(nextProgram)
    gl.deleteShader(vertexShader)
    gl.deleteShader(fragmentShader)
    if (!gl.getProgramParameter(nextProgram, gl.LINK_STATUS)) {
      const error = gl.getProgramInfoLog(nextProgram)
      gl.deleteProgram(nextProgram)
      throw new Error(error || 'game_view_program_failed')
    }
    gl.useProgram(nextProgram)

    const positionLocation = gl.getAttribLocation(nextProgram, 'a_position')
    const texcoordLocation = gl.getAttribLocation(nextProgram, 'a_texcoord')
    if (positionLocation < 0 || texcoordLocation < 0) {
      gl.deleteProgram(nextProgram)
      throw new Error('game_view_attributes_unavailable')
    }

    const nextPositionBuffer = gl.createBuffer()
    const nextTexcoordBuffer = gl.createBuffer()
    const nextTexture = gl.createTexture()
    if (!nextPositionBuffer || !nextTexcoordBuffer || !nextTexture) {
      if (nextPositionBuffer) gl.deleteBuffer(nextPositionBuffer)
      if (nextTexcoordBuffer) gl.deleteBuffer(nextTexcoordBuffer)
      if (nextTexture) gl.deleteTexture(nextTexture)
      gl.deleteProgram(nextProgram)
      throw new Error('game_view_resources_unavailable')
    }

    program = nextProgram
    positionBuffer = nextPositionBuffer
    texcoordBuffer = nextTexcoordBuffer
    texture = nextTexture

    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer)
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
      gl.DYNAMIC_DRAW,
    )
    gl.enableVertexAttribArray(positionLocation)
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0)

    gl.bindBuffer(gl.ARRAY_BUFFER, texcoordBuffer)
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]),
      gl.STATIC_DRAW,
    )
    gl.enableVertexAttribArray(texcoordLocation)
    gl.vertexAttribPointer(texcoordLocation, 2, gl.FLOAT, false, 0, 0)

    gl.bindTexture(gl.TEXTURE_2D, texture)
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA,
      1,
      1,
      0,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      new Uint8Array([0, 0, 0, 255]),
    )
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    // CitizenFX watches this exact wrap-mode sequence and replaces the seeded pixel with the live
    // game backbuffer. These calls are intentionally not redundant.
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT)
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.uniform1i(gl.getUniformLocation(program, 'u_texture'), 0)
    gl.clearColor(0, 0, 0, 1)
  }

  const applySize = (): void => {
    if (!lastSize || !positionBuffer || !texcoordBuffer) return
    const geometry = gameViewGeometry(
      lastSize.sourceWidth,
      lastSize.sourceHeight,
      lastSize.width,
      lastSize.height,
      lastSize.zoom,
    )
    canvas.width = lastSize.width
    canvas.height = lastSize.height
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer)
    gl.bufferData(gl.ARRAY_BUFFER, geometry.positions, gl.DYNAMIC_DRAW)
    gl.bindBuffer(gl.ARRAY_BUFFER, texcoordBuffer)
    gl.bufferData(
      gl.ARRAY_BUFFER,
      geometry.textureCoordinates,
      gl.DYNAMIC_DRAW,
    )
    gl.viewport(0, 0, lastSize.width, lastSize.height)
  }

  const onContextLost = (event: Event) => {
    event.preventDefault()
    lost = true
    console.error('[Camera] Game-view WebGL context lost.')
    options.onContextLost?.()
  }
  const onContextRestored = () => {
    if (disposed) return
    try {
      initializeResources()
      lost = false
      applySize()
      options.onContextRestored?.()
    } catch (error) {
      lost = true
      console.error('[Camera] Could not restore the game-view WebGL context.', error)
    }
  }
  canvas.addEventListener(
    'webglcontextlost',
    onContextLost as EventListener,
    false,
  )
  canvas.addEventListener(
    'webglcontextrestored',
    onContextRestored as EventListener,
    false,
  )
  try {
    initializeResources()
  } catch (error) {
    canvas.removeEventListener(
      'webglcontextlost',
      onContextLost as EventListener,
      false,
    )
    canvas.removeEventListener(
      'webglcontextrestored',
      onContextRestored as EventListener,
      false,
    )
    releaseResources()
    throw error
  }

  return {
    canvas,
    dispose() {
      if (disposed) return
      disposed = true
      canvas.removeEventListener(
        'webglcontextlost',
        onContextLost as EventListener,
        false,
      )
      canvas.removeEventListener(
        'webglcontextrestored',
        onContextRestored as EventListener,
        false,
      )
      if (!lost) releaseResources()
      gl.getExtension('WEBGL_lose_context')?.loseContext()
    },
    isLost: () => lost,
    render() {
      if (disposed || lost || !program) return
      gl.useProgram(program)
      gl.clear(gl.COLOR_BUFFER_BIT)
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
      gl.finish()
    },
    resize(
      width: number,
      height: number,
      sourceWidth = window.innerWidth,
      sourceHeight = window.innerHeight,
      zoom = 1,
    ) {
      lastSize = {
        height,
        sourceWidth,
        sourceHeight,
        width,
        zoom,
      }
      if (disposed || lost) return
      applySize()
    },
  }
}


export type VideoSignal = {
  kind: 'offer' | 'answer' | 'ice';
  sdp?: RTCSessionDescriptionInit;
  candidate?: RTCIceCandidateInit;
};

type CameraReply = { ok: boolean; error?: string };
async function cameraRequest(route: string, body: unknown = {}): Promise<void> {
  if (!window.GetParentResourceName) throw new Error('Live game video requires FiveM');
  const response = await fetch(`https://${window.GetParentResourceName()}/${route}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error('The game camera is unavailable');
  const reply: CameraReply = await response.json();
  if (!reply.ok) throw new Error(reply.error || 'The game camera is unavailable');
}

// One instance belongs to one accepted video session; audio stays on pma-voice.
export class GameVideo {
  private peer?: RTCPeerConnection;
  private cameraToken?: string;
  private stream?: MediaStream;
  private remote = new MediaStream();
  private view?: GameView;
  private animation = 0;
  private generation = 0;
  private makingOffer = false;
  private ignoreOffer = false;
  private settingAnswer = false;
  private polite = false;
  private paused = false;
  private front = true;
  private candidates: RTCIceCandidateInit[] = [];
  private receiveQueue: Promise<void> = Promise.resolve();
  private retryTimer?: ReturnType<typeof setTimeout>;
  private disconnectTimer?: ReturnType<typeof setTimeout>;
  private restarts = 0;
  private onSignal: (signal: VideoSignal) => void = () => undefined;
  private onError: (message: string) => void = () => undefined;

  async start(
    iceServers: RTCIceServer[], polite: boolean,
    onSignal: (signal: VideoSignal) => void,
    onStream: (stream: MediaStream, local: boolean) => void,
    onError: (message: string) => void,
  ): Promise<void> {
    if (this.peer) throw new Error('Video is already active');
    const generation = ++this.generation;
    this.polite = polite; this.onSignal = onSignal; this.onError = onError;
    try {
      const cameraToken = crypto.randomUUID();
      this.cameraToken = cameraToken;
      await cameraRequest('camera:videoStart', { token: cameraToken });
      if (generation !== this.generation) {
        await cameraRequest('camera:videoStop', { token: cameraToken });
        return;
      }
      const canvas = document.createElement('canvas');
      this.view = createGameView(canvas, {
        preserveDrawingBuffer: true,
        onContextLost: () => this.fail('Video rendering stopped. Voice is still connected.'),
      });
      this.view.resize(360, 640);
      let previous = 0;
      const draw = (now: number) => {
        if (generation !== this.generation) return;
        this.animation = requestAnimationFrame(draw);
        if (this.paused || now - previous < 50) return;
        previous = now;
        this.view?.render();
      };
      this.view.render();
      this.animation = requestAnimationFrame(draw);
      this.stream = canvas.captureStream(20);
      onStream(this.stream, true);
      const peer = new RTCPeerConnection({ iceServers });
      this.peer = peer;
      peer.onicecandidate = ({ candidate }) => {
        if (candidate && generation === this.generation) onSignal({ kind: 'ice', candidate: candidate.toJSON() });
      };
      peer.ontrack = ({ track, streams }) => {
        const stream = streams[0];
        if (stream) onStream(stream, false);
        else {
          if (!this.remote.getTracks().some(item => item.id === track.id)) this.remote.addTrack(track);
          onStream(this.remote, false);
        }
      };
      peer.onnegotiationneeded = async () => {
        try {
          this.makingOffer = true;
          if (peer.signalingState !== 'stable') return;
          await peer.setLocalDescription(await peer.createOffer());
          if (generation === this.generation && peer.localDescription) {
            onSignal({ kind: 'offer', sdp: peer.localDescription.toJSON() });
          }
        } catch (error) {
          if (generation === this.generation) this.fail(this.errorText(error));
        } finally { this.makingOffer = false; }
      };
      peer.oniceconnectionstatechange = () => {
        if (peer.iceConnectionState === 'failed') this.restart(generation);
      };
      peer.onconnectionstatechange = () => {
        if (generation !== this.generation) return;
        if (peer.connectionState === 'connected') {
          if (this.retryTimer) clearTimeout(this.retryTimer);
          if (this.disconnectTimer) clearTimeout(this.disconnectTimer);
        } else if (peer.connectionState === 'failed') {
          this.restart(generation);
        } else if (peer.connectionState === 'disconnected' && !this.disconnectTimer) {
          this.disconnectTimer = setTimeout(() => {
            this.disconnectTimer = undefined;
            if (generation === this.generation && peer.connectionState === 'disconnected') this.restart(generation);
          }, 5000);
        }
      };
      this.stream.getVideoTracks().forEach(track => peer.addTrack(track, this.stream!));
      this.retryTimer = setTimeout(() => {
        if (generation === this.generation && peer.connectionState !== 'connected') this.restart(generation);
      }, 20000);
    } catch (error) {
      if (generation === this.generation) this.fail(this.errorText(error));
      throw error;
    }
  }

  receive(signal: VideoSignal): Promise<void> {
    const generation = this.generation;
    this.receiveQueue = this.receiveQueue.then(async () => {
      const peer = this.peer;
      if (!peer || generation !== this.generation || peer.signalingState === 'closed') return;
      if (signal.kind === 'ice') {
        if (!signal.candidate || this.ignoreOffer) return;
        if (!peer.remoteDescription) {
          if (this.candidates.length >= 128) throw new Error('Too many pending video candidates');
          this.candidates.push(signal.candidate);
        } else await peer.addIceCandidate(signal.candidate);
        return;
      }
      const description = signal.sdp;
      if (!description || (description.type !== 'offer' && description.type !== 'answer')) return;
      if (description.type !== signal.kind) return;
      const ready = !this.makingOffer && (peer.signalingState === 'stable' || this.settingAnswer);
      const collision = description.type === 'offer' && !ready;
      this.ignoreOffer = !this.polite && collision;
      if (this.ignoreOffer) return;
      this.settingAnswer = description.type === 'answer';
      try {
        if (collision && this.polite && peer.signalingState === 'have-local-offer') {
          await peer.setLocalDescription({ type: 'rollback' });
        }
        await peer.setRemoteDescription(description);
      } finally { this.settingAnswer = false; }
      for (const candidate of this.candidates.splice(0)) await peer.addIceCandidate(candidate);
      if (description.type === 'offer') {
        await peer.setLocalDescription(await peer.createAnswer());
        if (generation === this.generation && peer.localDescription) {
          this.onSignal({ kind: 'answer', sdp: peer.localDescription.toJSON() });
        }
      }
    }).catch(error => {
      if (generation === this.generation && !this.ignoreOffer) this.fail(this.errorText(error));
    });
    return this.receiveQueue;
  }

  setPaused(paused: boolean): void {
    this.paused = paused;
    this.stream?.getVideoTracks().forEach(track => { track.enabled = !paused; });
  }

  async flip(): Promise<void> {
    const front = !this.front;
    await cameraRequest('camera:videoFacing', { front, token: this.cameraToken });
    this.front = front;
  }

  stop(): void {
    ++this.generation;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    if (this.disconnectTimer) clearTimeout(this.disconnectTimer);
    this.retryTimer = undefined; this.disconnectTimer = undefined;
    cancelAnimationFrame(this.animation);
    const peer = this.peer;
    this.peer = undefined;
    if (peer) {
      peer.onicecandidate = null; peer.ontrack = null; peer.onnegotiationneeded = null;
      peer.onconnectionstatechange = null; peer.oniceconnectionstatechange = null;
      peer.close();
    }
    this.stream?.getTracks().forEach(track => track.stop());
    this.stream = undefined;
    this.remote.getTracks().forEach(track => track.stop());
    this.remote = new MediaStream();
    this.view?.dispose(); this.view = undefined;
    this.candidates = []; this.ignoreOffer = false; this.makingOffer = false;
    this.settingAnswer = false; this.front = true; this.paused = false; this.restarts = 0;
    this.receiveQueue = Promise.resolve();
    const cameraToken = this.cameraToken;
    this.cameraToken = undefined;
    if (cameraToken) void cameraRequest('camera:videoStop', { token: cameraToken }).catch(() => undefined);
  }

  private restart(generation: number): void {
    const peer = this.peer;
    if (!peer || generation !== this.generation || this.restarts) return;
    this.restarts++;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    peer.restartIce();
    this.retryTimer = setTimeout(() => {
      if (generation === this.generation && peer.connectionState !== 'connected') {
        this.fail('Video could not connect. Voice is still connected. Try video again.');
      }
    }, 15000);
  }

  private errorText(error: unknown): string {
    return error instanceof Error ? error.message : 'Video failed. Voice is still connected.';
  }
  private fail(message: string): void { this.stop(); this.onError(message); }
}
