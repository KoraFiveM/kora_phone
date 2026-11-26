// Bundled to runtime/game.js for the Camera app: the game's render view and the clip recorder, shared with the phone's own code
// so there is one copy of the WebGL view.
export { createGameView } from '../web/src/gameVideo';
export { openMicrophone, recordGameClip } from '../web/src/gameRecording';
