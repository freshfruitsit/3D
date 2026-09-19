// Keyboard + mouse input. Actions are polled each frame; one-shot presses are
// collected into a set that the game clears at the end of every frame.

const KEYMAP = {
  forward: ['KeyW', 'ArrowUp'],
  back: ['KeyS', 'ArrowDown'],
  left: ['KeyA', 'ArrowLeft'],
  right: ['KeyD', 'ArrowRight'],
  jump: ['Space'],
  boost: ['ShiftLeft', 'ShiftRight'],
  lightshift: ['KeyE'],
  pause: ['Escape'],
};

const PREVENT_DEFAULT = new Set([
  'Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight',
]);

export class Input {
  constructor(canvas) {
    this.keys = new Set();
    this.justPressed = new Set();
    this.dragDX = 0;
    this.dragDY = 0;
    this.wheel = 0;
    this._dragging = false;
    this._lastX = 0;
    this._lastY = 0;

    window.addEventListener('keydown', (e) => {
      if (PREVENT_DEFAULT.has(e.code)) e.preventDefault();
      if (!e.repeat) this.justPressed.add(e.code);
      this.keys.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.keys.delete(e.code));
    window.addEventListener('blur', () => this.keys.clear());

    canvas.addEventListener('mousedown', (e) => {
      if (e.button !== 0) return;
      this._dragging = true;
      this._lastX = e.clientX;
      this._lastY = e.clientY;
    });
    window.addEventListener('mousemove', (e) => {
      if (!this._dragging) return;
      this.dragDX += e.clientX - this._lastX;
      this.dragDY += e.clientY - this._lastY;
      this._lastX = e.clientX;
      this._lastY = e.clientY;
    });
    window.addEventListener('mouseup', () => { this._dragging = false; });
    canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      this.wheel += e.deltaY;
    }, { passive: false });

    // Single-finger touch drag orbits the camera (the game itself needs keys).
    canvas.addEventListener('touchstart', (e) => {
      if (e.touches.length !== 1) return;
      this._dragging = true;
      this._lastX = e.touches[0].clientX;
      this._lastY = e.touches[0].clientY;
    }, { passive: true });
    canvas.addEventListener('touchmove', (e) => {
      if (!this._dragging || e.touches.length !== 1) return;
      this.dragDX += e.touches[0].clientX - this._lastX;
      this.dragDY += e.touches[0].clientY - this._lastY;
      this._lastX = e.touches[0].clientX;
      this._lastY = e.touches[0].clientY;
    }, { passive: true });
    canvas.addEventListener('touchend', () => { this._dragging = false; });
  }

  down(action) {
    return KEYMAP[action].some((code) => this.keys.has(code));
  }

  pressed(action) {
    return KEYMAP[action].some((code) => this.justPressed.has(code));
  }

  // Returns accumulated mouse deltas since last call and resets them.
  consumeLook() {
    const out = { dx: this.dragDX, dy: this.dragDY, wheel: this.wheel };
    this.dragDX = 0;
    this.dragDY = 0;
    this.wheel = 0;
    return out;
  }

  endFrame() {
    this.justPressed.clear();
  }
}
