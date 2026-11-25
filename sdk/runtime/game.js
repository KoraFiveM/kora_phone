// ../web/src/gameVideo.ts
var VERTEX_SHADER = `
  attribute vec2 a_position;
  attribute vec2 a_texcoord;
  varying vec2 v_texcoord;
  void main() {
    gl_Position = vec4(a_position, 0.0, 1.0);
    v_texcoord = a_texcoord;
  }
`;
var FRAGMENT_SHADER = `
  varying highp vec2 v_texcoord;
  uniform sampler2D u_texture;
  void main() {
    gl_FragColor = texture2D(u_texture, v_texcoord);
  }
`;
function gameViewGeometry(sourceWidth, sourceHeight, targetWidth, targetHeight, zoom = 1) {
  const sourceAspect = sourceWidth / sourceHeight;
  const targetAspect = targetWidth / targetHeight;
  let left = 0;
  let right = 1;
  let top = 0;
  let bottom = 1;
  if (sourceAspect > targetAspect) {
    const visibleWidth = targetAspect / sourceAspect;
    left = (1 - visibleWidth) / 2;
    right = 1 - left;
  } else if (sourceAspect < targetAspect) {
    const visibleHeight = sourceAspect / targetAspect;
    top = (1 - visibleHeight) / 2;
    bottom = 1 - top;
  }
  const normalizedZoom = Math.min(3, Math.max(0.5, zoom));
  const centerX = (left + right) / 2;
  const centerY = (top + bottom) / 2;
  left = Math.max(0, centerX + (left - centerX) / normalizedZoom);
  right = Math.min(1, centerX + (right - centerX) / normalizedZoom);
  top = Math.max(0, centerY + (top - centerY) / normalizedZoom);
  bottom = Math.min(1, centerY + (bottom - centerY) / normalizedZoom);
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
      bottom
    ])
  };
}
function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  if (!shader) throw new Error("game_view_shader_unavailable");
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader) || "game_view_shader_failed");
  }
  return shader;
}
function createGameView(canvas, options = {}) {
  const gl = canvas.getContext("webgl", {
    alpha: false,
    antialias: false,
    depth: false,
    desynchronized: true,
    failIfMajorPerformanceCaveat: false,
    preserveDrawingBuffer: options.preserveDrawingBuffer === true,
    stencil: false
  });
  if (!gl) throw new Error("game_view_unavailable");
  let lost = false;
  let disposed = false;
  let program = null;
  let positionBuffer = null;
  let texcoordBuffer = null;
  let texture = null;
  let lastSize = null;
  const releaseResources = () => {
    if (positionBuffer) gl.deleteBuffer(positionBuffer);
    if (texcoordBuffer) gl.deleteBuffer(texcoordBuffer);
    if (texture) gl.deleteTexture(texture);
    if (program) gl.deleteProgram(program);
    positionBuffer = null;
    texcoordBuffer = null;
    texture = null;
    program = null;
  };
  const initializeResources = () => {
    releaseResources();
    const nextProgram = gl.createProgram();
    if (!nextProgram) throw new Error("game_view_program_unavailable");
    const vertexShader = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
    const fragmentShader = compileShader(gl, gl.FRAGMENT_SHADER, FRAGMENT_SHADER);
    gl.attachShader(nextProgram, vertexShader);
    gl.attachShader(nextProgram, fragmentShader);
    gl.linkProgram(nextProgram);
    gl.deleteShader(vertexShader);
    gl.deleteShader(fragmentShader);
    if (!gl.getProgramParameter(nextProgram, gl.LINK_STATUS)) {
      const error = gl.getProgramInfoLog(nextProgram);
      gl.deleteProgram(nextProgram);
      throw new Error(error || "game_view_program_failed");
    }
    gl.useProgram(nextProgram);
    const positionLocation = gl.getAttribLocation(nextProgram, "a_position");
    const texcoordLocation = gl.getAttribLocation(nextProgram, "a_texcoord");
    if (positionLocation < 0 || texcoordLocation < 0) {
      gl.deleteProgram(nextProgram);
      throw new Error("game_view_attributes_unavailable");
    }
    const nextPositionBuffer = gl.createBuffer();
    const nextTexcoordBuffer = gl.createBuffer();
    const nextTexture = gl.createTexture();
    if (!nextPositionBuffer || !nextTexcoordBuffer || !nextTexture) {
      if (nextPositionBuffer) gl.deleteBuffer(nextPositionBuffer);
      if (nextTexcoordBuffer) gl.deleteBuffer(nextTexcoordBuffer);
      if (nextTexture) gl.deleteTexture(nextTexture);
      gl.deleteProgram(nextProgram);
      throw new Error("game_view_resources_unavailable");
    }
    program = nextProgram;
    positionBuffer = nextPositionBuffer;
    texcoordBuffer = nextTexcoordBuffer;
    texture = nextTexture;
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
      gl.DYNAMIC_DRAW
    );
    gl.enableVertexAttribArray(positionLocation);
    gl.vertexAttribPointer(positionLocation, 2, gl.FLOAT, false, 0, 0);
    gl.bindBuffer(gl.ARRAY_BUFFER, texcoordBuffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]),
      gl.STATIC_DRAW
    );
    gl.enableVertexAttribArray(texcoordLocation);
    gl.vertexAttribPointer(texcoordLocation, 2, gl.FLOAT, false, 0, 0);
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA,
      1,
      1,
      0,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      new Uint8Array([0, 0, 0, 255])
    );
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
    gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.uniform1i(gl.getUniformLocation(program, "u_texture"), 0);
    gl.clearColor(0, 0, 0, 1);
  };
  const applySize = () => {
    if (!lastSize || !positionBuffer || !texcoordBuffer) return;
    const geometry = gameViewGeometry(
      lastSize.sourceWidth,
      lastSize.sourceHeight,
      lastSize.width,
      lastSize.height,
      lastSize.zoom
    );
    canvas.width = lastSize.width;
    canvas.height = lastSize.height;
    gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, geometry.positions, gl.DYNAMIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, texcoordBuffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      geometry.textureCoordinates,
      gl.DYNAMIC_DRAW
    );
    gl.viewport(0, 0, lastSize.width, lastSize.height);
  };
  const onContextLost = (event) => {
    event.preventDefault();
    lost = true;
    console.error("[Camera] Game-view WebGL context lost.");
    options.onContextLost?.();
  };
  const onContextRestored = () => {
    if (disposed) return;
    try {
      initializeResources();
      lost = false;
      applySize();
      options.onContextRestored?.();
    } catch (error) {
      lost = true;
      console.error("[Camera] Could not restore the game-view WebGL context.", error);
    }
  };
  canvas.addEventListener(
    "webglcontextlost",
    onContextLost,
    false
  );
  canvas.addEventListener(
    "webglcontextrestored",
    onContextRestored,
    false
  );
  try {
    initializeResources();
  } catch (error) {
    canvas.removeEventListener(
      "webglcontextlost",
      onContextLost,
      false
    );
    canvas.removeEventListener(
      "webglcontextrestored",
      onContextRestored,
      false
    );
    releaseResources();
    throw error;
  }
  return {
    canvas,
    dispose() {
      if (disposed) return;
      disposed = true;
      canvas.removeEventListener(
        "webglcontextlost",
        onContextLost,
        false
      );
      canvas.removeEventListener(
        "webglcontextrestored",
        onContextRestored,
        false
      );
      if (!lost) releaseResources();
    },
    isLost: () => lost,
    render() {
      if (disposed || lost || !program) return;
      gl.useProgram(program);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      gl.finish();
    },
    resize(width, height, sourceWidth = window.innerWidth, sourceHeight = window.innerHeight, zoom = 1) {
      lastSize = {
        height,
        sourceWidth,
        sourceHeight,
        width,
        zoom
      };
      if (disposed || lost) return;
      applySize();
    }
  };
}

// ../web/src/gameRecording.ts
function recordGameClip(canvas, seconds, maxBytes, audio) {
  const stopAudio = () => audio?.getTracks().forEach((track) => track.stop());
  if (typeof MediaRecorder === "undefined" || !canvas.captureStream) {
    stopAudio();
    throw new Error("Video recording is unavailable in this browser.");
  }
  const withAudio = !!audio && audio.getAudioTracks().length > 0;
  const types = withAudio ? ["video/webm;codecs=vp8,opus", "video/webm", "video/mp4"] : ["video/webm;codecs=vp8", "video/webm", "video/mp4"];
  const mimeType = types.find((type) => MediaRecorder.isTypeSupported(type));
  if (!mimeType) {
    stopAudio();
    throw new Error("This browser cannot record supported video clips.");
  }
  const video = canvas.captureStream(20);
  const stream = withAudio && audio ? new MediaStream([...video.getVideoTracks(), ...audio.getAudioTracks()]) : video;
  const release = () => {
    clearTimeout(timer);
    video.getTracks().forEach((track) => track.stop());
    stopAudio();
  };
  let recorder;
  try {
    recorder = new MediaRecorder(stream, withAudio ? { mimeType, videoBitsPerSecond: 15e5, audioBitsPerSecond: 64e3 } : { mimeType, videoBitsPerSecond: 15e5 });
  } catch (error) {
    video.getTracks().forEach((track) => track.stop());
    stopAudio();
    throw error;
  }
  let settled = false;
  let timer;
  let rejectResult;
  const cancel = (message = "Recording cancelled.") => {
    if (settled) return;
    settled = true;
    if (recorder.state !== "inactive") recorder.stop();
    release();
    rejectResult(new Error(message));
  };
  const result = new Promise((resolve, reject) => {
    rejectResult = reject;
    const chunks = [];
    let bytes = 0;
    recorder.ondataavailable = (event) => {
      if (settled || !event.data.size) return;
      bytes += event.data.size;
      if (bytes > maxBytes) {
        cancel("The recording is too large. Try a shorter clip.");
        return;
      }
      chunks.push(event.data);
    };
    recorder.onerror = () => cancel("Video recording failed. Please try again.");
    recorder.onstop = () => {
      if (settled) return;
      settled = true;
      release();
      if (!bytes) {
        reject(new Error("The camera produced an empty recording."));
        return;
      }
      resolve(new Blob(chunks, { type: mimeType.split(";")[0] }));
    };
    try {
      recorder.start(250);
      timer = setTimeout(() => {
        if (recorder.state === "recording") recorder.stop();
      }, Math.min(60, Math.max(1, seconds)) * 1e3);
    } catch (error) {
      settled = true;
      release();
      reject(error);
    }
  });
  return { result, stop: () => {
    if (!settled && recorder.state === "recording") recorder.stop();
  }, cancel };
}
function openMicrophone(timeoutMs = 15e3) {
  if (!navigator.mediaDevices?.getUserMedia) return Promise.resolve(void 0);
  return new Promise((resolve) => {
    let done = false;
    const timer = setTimeout(() => {
      done = true;
      resolve(void 0);
    }, timeoutMs);
    navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }, video: false }).then((stream) => {
      if (done) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      done = true;
      clearTimeout(timer);
      resolve(stream.getAudioTracks().length ? stream : (stream.getTracks().forEach((track) => track.stop()), void 0));
    }).catch(() => {
      if (!done) {
        done = true;
        clearTimeout(timer);
        resolve(void 0);
      }
    });
  });
}
export {
  createGameView,
  openMicrophone,
  recordGameClip
};
