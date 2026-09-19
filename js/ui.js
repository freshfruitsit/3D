import { formatTime } from './util.js';

// All DOM: HUD, screens, toasts. The Game drives this through simple setters.
export class UI {
  constructor(callbacks) {
    this.cb = callbacks;
    const $ = (id) => document.getElementById(id);

    this.screens = {
      loading: $('screen-loading'),
      start: $('screen-start'),
      pause: $('screen-pause'),
      victory: $('screen-victory'),
      gameover: $('screen-gameover'),
    };
    this.hud = $('hud');
    this.energyPips = $('energy-pips');
    this.hudCores = $('hud-cores');
    this.hudCrystals = $('hud-crystals');
    this.hudTimer = $('hud-timer');
    this.hudScore = $('hud-score');
    this.lsFill = $('ls-fill');
    this.lsLabel = $('ls-label');
    this.toasts = $('toasts');
    this.damageFlash = $('damage-flash');
    this.lsPulse = $('ls-pulse');
    this.startBest = $('start-best');
    this.btnSound = $('btn-sound');
    this.btnMusic = $('btn-music');

    $('btn-start').addEventListener('click', () => callbacks.onStart());
    $('btn-resume').addEventListener('click', () => callbacks.onResume());
    $('btn-restart').addEventListener('click', () => callbacks.onRestart());
    $('btn-again').addEventListener('click', () => callbacks.onRestart());
    $('btn-retry').addEventListener('click', () => callbacks.onRestart());
    this.btnSound.addEventListener('click', () => callbacks.onToggleSound());
    this.btnMusic.addEventListener('click', () => callbacks.onToggleMusic());

    this._timerText = '';
    this._scoreText = '';
    this._lsState = '';
  }

  showScreen(name) {
    for (const key of Object.keys(this.screens)) {
      this.screens[key].classList.toggle('hidden', key !== name);
    }
    this.hud.classList.toggle('hidden', name !== null && name !== 'pause');
  }

  setAudioButtons(sfxOn, musicOn) {
    this.btnSound.classList.toggle('off', !sfxOn);
    this.btnMusic.classList.toggle('off', !musicOn);
  }

  setEnergy(current, max) {
    if (this.energyPips.childElementCount !== max) {
      this.energyPips.innerHTML = '';
      for (let i = 0; i < max; i++) {
        const pip = document.createElement('div');
        pip.className = 'pip';
        this.energyPips.appendChild(pip);
      }
    }
    [...this.energyPips.children].forEach((pip, i) => {
      pip.classList.toggle('empty', i >= current);
    });
  }

  setCores(n, total) { this.hudCores.textContent = `◆ ${n}/${total}`; }
  setCrystals(n, total) { this.hudCrystals.textContent = `✦ ${n}/${total}`; }

  setTimer(seconds) {
    const text = formatTime(seconds);
    if (text !== this._timerText) {
      this._timerText = text;
      this.hudTimer.textContent = text;
    }
  }

  setScore(score) {
    const text = String(score);
    if (text !== this._scoreText) {
      this._scoreText = text;
      this.hudScore.textContent = text;
    }
  }

  // state: 'ready' | 'active' | 'cooldown'; frac: 0..1 fill amount.
  setLightshift(state, frac) {
    this.lsFill.style.width = `${Math.round(frac * 100)}%`;
    if (state !== this._lsState) {
      this._lsState = state;
      this.lsFill.classList.toggle('charging', state === 'cooldown');
      this.lsFill.classList.toggle('ready', state === 'ready');
      this.lsLabel.textContent =
        state === 'ready' ? 'READY' : state === 'active' ? 'ACTIVE' : 'CHARGING';
    }
  }

  toast(msg, duration = 3200) {
    const el = document.createElement('div');
    el.className = 'toast';
    el.textContent = msg;
    this.toasts.appendChild(el);
    while (this.toasts.childElementCount > 3) this.toasts.firstChild.remove();
    setTimeout(() => el.classList.add('fade'), duration);
    setTimeout(() => el.remove(), duration + 500);
  }

  clearToasts() { this.toasts.innerHTML = ''; }

  flashDamage() {
    this.damageFlash.classList.remove('active');
    void this.damageFlash.offsetWidth; // restart the CSS animation
    this.damageFlash.classList.add('active');
  }

  pulseLightshift() {
    this.lsPulse.classList.remove('active');
    void this.lsPulse.offsetWidth;
    this.lsPulse.classList.add('active');
  }

  setStartBest(best) {
    this.startBest.textContent = best
      ? `Best score ${best.score} · Fastest run ${formatTime(best.time)}`
      : 'No runs recorded yet — good luck, little spark.';
  }

  showVictory({ time, timeBonus, cores, coreTotal, crystals, crystalTotal,
                energy, falls, hits, total, newBestScore, newBestTime, best, scoring }) {
    const $ = (id) => document.getElementById(id);
    $('v-time').textContent = formatTime(time);
    $('v-time-bonus').textContent = `+${timeBonus}`;
    $('v-cores').textContent = `${cores}/${coreTotal}  (+${cores * scoring.core})`;
    $('v-crystals').textContent = `${crystals}/${crystalTotal}  (+${crystals * scoring.crystal})`;
    $('v-energy').textContent = `${energy}  (+${energy * scoring.energy})`;
    $('v-falls').textContent = `${falls}  (−${falls * scoring.fallPenalty})`;
    $('v-hits').textContent = `${hits}  (−${hits * scoring.hitPenalty})`;
    $('v-total').textContent = total;
    const badges = [];
    if (newBestScore) badges.push('★ NEW BEST SCORE');
    if (newBestTime) badges.push('⚡ NEW FASTEST TIME');
    $('v-badges').textContent = badges.join('   ');
    $('v-best').textContent = best
      ? `Best score ${best.score} · Fastest run ${formatTime(best.time)}`
      : '';
    this.showScreen('victory');
  }

  showGameOver(score, best) {
    document.getElementById('go-score').textContent = score;
    document.getElementById('go-best').textContent = best
      ? `Best score ${best.score} · Fastest run ${formatTime(best.time)}`
      : '';
    this.showScreen('gameover');
  }
}
