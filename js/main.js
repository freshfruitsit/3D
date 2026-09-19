import { Game } from './game.js';

// Bootstrap. Everything in the game is procedural, so "loading" is just
// building geometry and compiling shaders — near-instant on most machines.
function boot() {
  const canvas = document.getElementById('game-canvas');
  try {
    const game = new Game(canvas);
    // Exposed for automated smoke tests; harmless in normal play.
    window.__game = game;
  } catch (err) {
    console.error(err);
    const loading = document.getElementById('screen-loading');
    loading.classList.remove('hidden');
    loading.innerHTML =
      '<p class="loading-text">Could not start WebGL.<br>' +
      'Please use a browser with hardware acceleration enabled.</p>';
  }
}

boot();
