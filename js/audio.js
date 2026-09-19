import { storage } from './util.js';

// All audio is synthesized with the Web Audio API — no sound files.
// The AudioContext is created lazily on the first user gesture (Start click).

export class AudioManager {
  constructor() {
    this.ctx = null;
    this.sfxEnabled = storage.get('lightshift.sound', true);
    this.musicEnabled = storage.get('lightshift.music', true);
    this._musicNodes = null;
    this._pluckTimer = null;
    this._noiseBuffer = null;
  }

  unlock() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.9;
      this.master.connect(this.ctx.destination);
      this.sfxGain = this.ctx.createGain();
      this.sfxGain.gain.value = this.sfxEnabled ? 1 : 0;
      this.sfxGain.connect(this.master);
      this.musicGain = this.ctx.createGain();
      this.musicGain.gain.value = this.musicEnabled ? 1 : 0;
      this.musicGain.connect(this.master);
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    if (this.musicEnabled) this.startMusic();
  }

  setSfx(on) {
    this.sfxEnabled = on;
    storage.set('lightshift.sound', on);
    if (this.sfxGain) this.sfxGain.gain.value = on ? 1 : 0;
  }

  setMusic(on) {
    this.musicEnabled = on;
    storage.set('lightshift.music', on);
    if (this.musicGain) this.musicGain.gain.value = on ? 1 : 0;
    if (on) this.startMusic();
    else this.stopMusic();
  }

  // ---------- low-level synth helpers ----------

  _tone({ type = 'sine', freq = 440, freqEnd = null, dur = 0.2, gain = 0.15,
          attack = 0.005, when = 0, dest = null }) {
    if (!this.ctx || !this.sfxEnabled) return;
    const t0 = this.ctx.currentTime + when;
    const osc = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t0);
    if (freqEnd !== null) osc.frequency.exponentialRampToValueAtTime(Math.max(1, freqEnd), t0 + dur);
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.linearRampToValueAtTime(gain, t0 + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(g).connect(dest || this.sfxGain);
    osc.start(t0);
    osc.stop(t0 + dur + 0.05);
  }

  _noise({ dur = 0.3, gain = 0.12, filterFrom = 2000, filterTo = 400, when = 0 }) {
    if (!this.ctx || !this.sfxEnabled) return;
    if (!this._noiseBuffer) {
      const len = this.ctx.sampleRate;
      this._noiseBuffer = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
      const data = this._noiseBuffer.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
    }
    const t0 = this.ctx.currentTime + when;
    const src = this.ctx.createBufferSource();
    src.buffer = this._noiseBuffer;
    src.loop = true;
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.setValueAtTime(filterFrom, t0);
    filter.frequency.exponentialRampToValueAtTime(Math.max(40, filterTo), t0 + dur);
    filter.Q.value = 0.9;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(gain, t0);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    src.connect(filter).connect(g).connect(this.sfxGain);
    src.start(t0);
    src.stop(t0 + dur + 0.05);
  }

  // ---------- named sound effects ----------

  jump() {
    this._tone({ type: 'square', freq: 220, freqEnd: 480, dur: 0.14, gain: 0.07 });
  }

  boost() {
    this._noise({ dur: 0.3, gain: 0.1, filterFrom: 500, filterTo: 3200 });
  }

  core(index = 0) {
    const base = 520 + index * 40;
    [0, 4, 7].forEach((semi, i) => {
      this._tone({ type: 'sine', freq: base * Math.pow(2, semi / 12),
        dur: 0.28, gain: 0.11, when: i * 0.07 });
    });
  }

  crystal() {
    this._tone({ type: 'triangle', freq: 1180, dur: 0.18, gain: 0.09 });
    this._tone({ type: 'triangle', freq: 1560, dur: 0.26, gain: 0.08, when: 0.08 });
  }

  lightshift() {
    this._tone({ type: 'sawtooth', freq: 140, freqEnd: 900, dur: 0.5, gain: 0.08 });
    this._tone({ type: 'sine', freq: 900, freqEnd: 1500, dur: 0.6, gain: 0.05, when: 0.15 });
    this._noise({ dur: 0.5, gain: 0.05, filterFrom: 800, filterTo: 4000 });
  }

  lightshiftEnd() {
    this._tone({ type: 'sine', freq: 800, freqEnd: 220, dur: 0.4, gain: 0.05 });
  }

  lightshiftReady() {
    this._tone({ type: 'sine', freq: 1040, dur: 0.12, gain: 0.06 });
    this._tone({ type: 'sine', freq: 1560, dur: 0.18, gain: 0.05, when: 0.09 });
  }

  damage() {
    this._tone({ type: 'sawtooth', freq: 300, freqEnd: 70, dur: 0.4, gain: 0.13 });
    this._noise({ dur: 0.25, gain: 0.12, filterFrom: 900, filterTo: 150 });
  }

  alert() {
    this._tone({ type: 'square', freq: 660, dur: 0.09, gain: 0.05 });
    this._tone({ type: 'square', freq: 880, dur: 0.09, gain: 0.05, when: 0.1 });
  }

  checkpoint() {
    this._tone({ type: 'sine', freq: 620, dur: 0.16, gain: 0.1 });
    this._tone({ type: 'sine', freq: 930, dur: 0.32, gain: 0.1, when: 0.12 });
  }

  portal() {
    this._tone({ type: 'sawtooth', freq: 60, freqEnd: 240, dur: 1.4, gain: 0.1 });
    [523, 659, 784, 1046].forEach((f, i) => {
      this._tone({ type: 'sine', freq: f, dur: 0.7, gain: 0.06, when: 0.3 + i * 0.12 });
    });
  }

  victory() {
    [523, 659, 784, 1046, 1318].forEach((f, i) => {
      this._tone({ type: 'triangle', freq: f, dur: 0.45, gain: 0.1, when: i * 0.14 });
    });
    this._noise({ dur: 1.2, gain: 0.04, filterFrom: 1500, filterTo: 6000, when: 0.5 });
  }

  gameover() {
    [392, 330, 262, 196].forEach((f, i) => {
      this._tone({ type: 'triangle', freq: f, dur: 0.5, gain: 0.09, when: i * 0.22 });
    });
  }

  uiClick() {
    this._tone({ type: 'sine', freq: 700, dur: 0.06, gain: 0.05 });
  }

  // ---------- ambient music ----------

  startMusic() {
    if (!this.ctx || this._musicNodes || !this.musicEnabled) return;
    const t0 = this.ctx.currentTime;

    // Slow-evolving pad: two detuned oscillators through a wobbling lowpass.
    const padGain = this.ctx.createGain();
    padGain.gain.setValueAtTime(0.0001, t0);
    padGain.gain.linearRampToValueAtTime(0.045, t0 + 4);
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.value = 420;
    filter.Q.value = 1.2;
    const oscA = this.ctx.createOscillator();
    oscA.type = 'sawtooth';
    oscA.frequency.value = 55; // A1
    const oscB = this.ctx.createOscillator();
    oscB.type = 'sawtooth';
    oscB.frequency.value = 82.5; // E2, detuned fifth
    oscB.detune.value = 6;
    const lfo = this.ctx.createOscillator();
    lfo.frequency.value = 0.07;
    const lfoGain = this.ctx.createGain();
    lfoGain.gain.value = 190;
    lfo.connect(lfoGain).connect(filter.frequency);
    oscA.connect(filter);
    oscB.connect(filter);
    filter.connect(padGain).connect(this.musicGain);
    oscA.start(t0);
    oscB.start(t0);
    lfo.start(t0);
    this._musicNodes = { oscA, oscB, lfo, padGain };

    // Sparse pentatonic plucks over the pad.
    const scale = [220, 261.63, 293.66, 329.63, 392, 440, 523.25];
    this._pluckTimer = setInterval(() => {
      if (!this.musicEnabled || !this.ctx) return;
      const f = scale[Math.floor(Math.random() * scale.length)];
      const t = this.ctx.currentTime + Math.random() * 0.5;
      const osc = this.ctx.createOscillator();
      const g = this.ctx.createGain();
      osc.type = 'triangle';
      osc.frequency.value = f;
      g.gain.setValueAtTime(0.0001, t);
      g.gain.linearRampToValueAtTime(0.035, t + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t + 1.8);
      osc.connect(g).connect(this.musicGain);
      osc.start(t);
      osc.stop(t + 2);
    }, 2600);
  }

  stopMusic() {
    if (this._pluckTimer) {
      clearInterval(this._pluckTimer);
      this._pluckTimer = null;
    }
    if (this._musicNodes) {
      const { oscA, oscB, lfo, padGain } = this._musicNodes;
      const t = this.ctx.currentTime;
      padGain.gain.cancelScheduledValues(t);
      padGain.gain.setValueAtTime(padGain.gain.value, t);
      padGain.gain.linearRampToValueAtTime(0.0001, t + 0.5);
      [oscA, oscB, lfo].forEach((o) => o.stop(t + 0.6));
      this._musicNodes = null;
    }
  }
}
