import * as THREE from './lib/three.module.js';
import { CONFIG, LEVEL } from './config.js';
import { Input } from './input.js';
import { AudioManager } from './audio.js';
import { ParticleSystem } from './particles.js';
import { UI } from './ui.js';
import { Player } from './player.js';
import { Drone } from './drone.js';
import { Level } from './level.js';
import { clamp, damp, lerp, makeGlowTexture, storage } from './util.js';

const FOG_BASE = new THREE.Color(0x0a0c1e);
const FOG_SHIFT = new THREE.Color(0x142a4a);
const _camTarget = new THREE.Vector3();
const _camDesired = new THREE.Vector3();
const _v = new THREE.Vector3();

export class Game {
  constructor(canvas) {
    this.canvas = canvas;
    this.state = 'loading';

    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.15;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x060812);
    this.scene.fog = new THREE.FogExp2(FOG_BASE.getHex(), 0.014);

    this.camera = new THREE.PerspectiveCamera(
      CONFIG.camera.fov, window.innerWidth / window.innerHeight, 0.1, 500);
    this.camYaw = 0;
    this.camPitch = CONFIG.camera.startPitch;
    this.camDist = CONFIG.camera.startDist;
    this.shakeAmp = 0;

    this._setupLights();
    this._setupBackdrop();

    this.assets = { glowTexture: makeGlowTexture() };
    this.particles = new ParticleSystem(this.scene, this.assets.glowTexture);
    this.audio = new AudioManager();
    this.input = new Input(canvas);

    this.ui = new UI({
      onStart: () => this.newGame(),
      onResume: () => this.resume(),
      onRestart: () => this.newGame(),
      onToggleSound: () => {
        this.audio.setSfx(!this.audio.sfxEnabled);
        this.audio.uiClick();
        this._syncAudioButtons();
      },
      onToggleMusic: () => {
        this.audio.setMusic(!this.audio.musicEnabled);
        this._syncAudioButtons();
      },
    });
    this._syncAudioButtons();

    this.level = null;
    this.player = null;
    this.drones = [];
    this.shockwaves = [];
    this._buildShockwavePool();

    window.addEventListener('resize', () => this._onResize());
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.state === 'playing') this.pause();
    });

    this.clock = new THREE.Clock();
    this.elapsed = 0;      // total wall time for ambient animation
    this.gameTime = 0;     // run timer (pause-aware)

    this._resetRunState();
    this.renderer.setAnimationLoop(() => this._frame());

    // First frame rendered → swap the loading screen for the start screen.
    this.ui.setStartBest(storage.get('lightshift.best'));
    this.ui.showScreen('start');
    this.state = 'start';
  }

  // ---------- static scene ----------

  _setupLights() {
    this.hemi = new THREE.HemisphereLight(0x5a6cc0, 0x180d2a, 0.9);
    this.scene.add(this.hemi);

    this.sun = new THREE.DirectionalLight(0xb8ccff, 3.0);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    const cam = this.sun.shadow.camera;
    cam.left = -34;
    cam.right = 34;
    cam.top = 34;
    cam.bottom = -34;
    cam.near = 1;
    cam.far = 140;
    this.sun.shadow.bias = -0.0004;
    this.sun.shadow.normalBias = 0.02;
    this.sunTarget = new THREE.Object3D();
    this.scene.add(this.sunTarget);
    this.sun.target = this.sunTarget;
    this.scene.add(this.sun);
  }

  _setupBackdrop() {
    // Starfield shell.
    const starCount = 900;
    const positions = new Float32Array(starCount * 3);
    const colors = new Float32Array(starCount * 3);
    const c = new THREE.Color();
    for (let i = 0; i < starCount; i++) {
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(2 * Math.random() - 1);
      const radius = 260 + Math.random() * 90;
      positions[i * 3] = Math.sin(phi) * Math.cos(theta) * radius;
      positions[i * 3 + 1] = Math.cos(phi) * radius * 0.6 + 20;
      positions[i * 3 + 2] = Math.sin(phi) * Math.sin(theta) * radius;
      c.setHSL(0.55 + Math.random() * 0.15, 0.6, 0.55 + Math.random() * 0.35);
      colors[i * 3] = c.r;
      colors[i * 3 + 1] = c.g;
      colors[i * 3 + 2] = c.b;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    const stars = new THREE.Points(geo, new THREE.PointsMaterial({
      size: 1.4, vertexColors: true, transparent: true, opacity: 0.85,
      fog: false, sizeAttenuation: true, depthWrite: false,
    }));
    this.scene.add(stars);

    // Faint abyss glow far below the islands.
    const abyss = new THREE.Mesh(
      new THREE.CircleGeometry(220, 32),
      new THREE.MeshBasicMaterial({
        color: 0x1a1040, transparent: true, opacity: 0.35,
        fog: false, depthWrite: false,
      }));
    abyss.rotation.x = -Math.PI / 2;
    abyss.position.set(0, -70, -60);
    this.scene.add(abyss);
  }

  _buildShockwavePool() {
    for (let i = 0; i < 4; i++) {
      const mesh = new THREE.Mesh(
        new THREE.RingGeometry(0.9, 1.06, 48),
        new THREE.MeshBasicMaterial({
          color: 0x35e0ff, transparent: true, opacity: 0,
          blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
        }));
      mesh.rotation.x = -Math.PI / 2;
      mesh.visible = false;
      this.scene.add(mesh);
      this.shockwaves.push({ mesh, age: 1e9, duration: 0.9, maxR: 16 });
    }
  }

  spawnShockwave(pos, color = 0x35e0ff, maxR = 16, duration = 0.9) {
    const sw = this.shockwaves.reduce((a, b) => (a.age > b.age ? a : b));
    sw.age = 0;
    sw.maxR = maxR;
    sw.duration = duration;
    sw.mesh.position.copy(pos);
    sw.mesh.position.y += 0.15;
    sw.mesh.material.color.setHex(color);
    sw.mesh.visible = true;
  }

  // ---------- run lifecycle ----------

  _resetRunState() {
    this.energy = CONFIG.maxEnergy;
    this.coresCollected = 0;
    this.crystalsCollected = 0;
    this.falls = 0;
    this.hits = 0;
    this.gameTime = 0;
    this.respawnPoint = LEVEL.spawn;
    this.lsState = 'ready';
    this.lsTimer = 0;
    this.revealFactor = 0;
    this.portalActivated = false;
  }

  newGame() {
    this.audio.unlock();
    this.audio.uiClick();

    if (this.level) {
      this.level.dispose();
      this.level = null;
      this.drones = [];
    }
    this.level = new Level(this.scene, this.assets);
    this.drones = LEVEL.drones.map((d) => new Drone(this.level.group, d, this.assets));

    if (!this.player) {
      this.player = new Player(this.scene, this.assets);
    }
    this.player.reset(LEVEL.spawn);

    this._resetRunState();
    this.camYaw = 0;
    this.camPitch = CONFIG.camera.startPitch;
    this.camDist = CONFIG.camera.startDist;
    this._snapCamera();

    this.ui.clearToasts();
    this.input.consumeLook();
    this.ui.setEnergy(this.energy, CONFIG.maxEnergy);
    this.ui.setCores(0, LEVEL.cores.length);
    this.ui.setCrystals(0, LEVEL.crystals.length);
    this.ui.setTimer(0);
    this.ui.setScore(0);
    this.ui.setLightshift('ready', 1);
    this.ui.showScreen(null);
    this.state = 'playing';
  }

  pause() {
    if (this.state !== 'playing') return;
    this.state = 'paused';
    this.ui.showScreen('pause');
  }

  resume() {
    if (this.state !== 'paused') return;
    this.audio.uiClick();
    this.input.consumeLook(); // drop drag/wheel deltas gathered while paused
    this.state = 'playing';
    this.ui.showScreen(null);
  }

  // ---------- scoring ----------

  _currentScore() {
    const S = CONFIG.score;
    const timeBonus = Math.max(0,
      S.timeBonusBase - Math.floor(this.gameTime) * S.timeBonusRate);
    const raw = this.coresCollected * S.core +
      this.crystalsCollected * S.crystal +
      this.energy * S.energy +
      timeBonus -
      this.falls * S.fallPenalty -
      this.hits * S.hitPenalty;
    return { total: Math.max(0, raw), timeBonus };
  }

  // ---------- damage / respawn ----------

  _takeHit(kind) {
    if (this.state !== 'playing') return;
    this.energy -= 1;
    if (kind === 'fall') this.falls += 1;
    else this.hits += 1;
    this.audio.damage();
    this.ui.flashDamage();
    this.ui.setEnergy(this.energy, CONFIG.maxEnergy);
    this.shakeAmp = Math.min(this.shakeAmp + 0.5, 0.8);
    this.particles.burst(
      _v.set(this.player.pos.x, this.player.pos.y + 1, this.player.pos.z),
      { count: 22, color: 0xff5030, speed: 6, life: 0.7, gravity: 6 });

    if (this.energy <= 0) {
      this._gameOver();
      return;
    }
    this.player.respawn(this.respawnPoint);
    for (const d of this.drones) d.onPlayerRespawn();
    this._snapCamera();
    this.ui.toast(kind === 'fall'
      ? 'Energy lost — recovered at checkpoint'
      : 'Drone hit! Recovered at checkpoint');
  }

  _gameOver() {
    this.state = 'gameover';
    this.audio.gameover();
    this.audio.stopMusic();
    const { total } = this._currentScore();
    this.ui.showGameOver(total, storage.get('lightshift.best'));
  }

  _victory() {
    this.state = 'victory';
    this.audio.victory();
    this.spawnShockwave(this.level.portal.pos, 0xa050ff, 26, 1.4);
    this.particles.burst(
      _v.copy(this.level.portal.pos).setY(this.level.portal.pos.y + 2.3),
      { count: 80, color: 0xa050ff, speed: 9, life: 1.4, gravity: 2 });

    const S = CONFIG.score;
    const { total, timeBonus } = this._currentScore();
    const time = this.gameTime;
    const prevBest = storage.get('lightshift.best');
    const newBestScore = !prevBest || total > prevBest.score;
    const newBestTime = !prevBest || time < prevBest.time;
    const best = {
      score: newBestScore ? total : prevBest.score,
      time: newBestTime ? time : prevBest.time,
    };
    storage.set('lightshift.best', best);
    this.ui.setStartBest(best);

    const detail = {
      time,
      timeBonus,
      cores: this.coresCollected,
      coreTotal: LEVEL.cores.length,
      crystals: this.crystalsCollected,
      crystalTotal: LEVEL.crystals.length,
      energy: this.energy,
      falls: this.falls,
      hits: this.hits,
      total,
      newBestScore,
      newBestTime,
      best,
      scoring: S,
    };
    setTimeout(() => {
      if (this.state === 'victory') this.ui.showVictory(detail);
    }, 1400);
  }

  // ---------- per-frame ----------

  _frame() {
    const dt = Math.min(this.clock.getDelta(), 0.05);
    this.elapsed += dt;

    if (this.input.pressed('pause')) {
      if (this.state === 'playing') this.pause();
      else if (this.state === 'paused') this.resume();
    }

    if (this.state === 'playing') {
      this._update(dt);
    } else if (this.state === 'victory' && this.level) {
      // Keep the world alive behind the victory screen.
      this.level.update(dt, this.elapsed);
      this.particles.update(dt);
      this._updateShockwaves(dt);
      this._emitPortalParticles();
    }

    this.renderer.render(this.scene, this.camera);
    this.input.endFrame();
  }

  _update(dt) {
    this.gameTime += dt;

    this.level.update(dt, this.elapsed);

    const landSpeed = this.player.update(
      dt, this.input, this.camYaw, this.level.colliders,
      this.audio, this.particles, this.elapsed);
    if (landSpeed > 13) {
      this.particles.burst(this.player.pos,
        { count: 8, color: 0x7fb8ff, speed: 2.5, life: 0.4, gravity: 5, upBias: 0.7 });
      this.shakeAmp = Math.min(this.shakeAmp + 0.08, 0.3);
    }

    // Rotating obstacles shove the player.
    const knock = this.level.checkSpinners(this.player);
    if (knock) {
      this.player.vel.x = knock.x * 9;
      this.player.vel.z = knock.z * 9;
      this.player.vel.y = Math.max(this.player.vel.y, 4);
      this.player.grounded = false;
      this.shakeAmp = Math.min(this.shakeAmp + 0.25, 0.6);
      this.audio.boost(); // whoosh — the shove costs no energy
    }

    // Drones.
    for (const d of this.drones) {
      const result = d.update(dt, this.player, this.audio, this.elapsed);
      if (result === 'hit') {
        this._takeHit('drone');
        if (this.state !== 'playing') return;
      }
    }

    // Falling into the void.
    if (this.player.pos.y < this.level.killY) {
      this._takeHit('fall');
      if (this.state !== 'playing') return;
    }

    this._checkPickups();
    this._checkCheckpoints();
    this._checkTutorials();
    this._checkPortal();
    this._updateLightshift(dt);
    this._updateCamera(dt);
    this._updateShockwaves(dt);
    this.particles.update(dt);
    this._emitPortalParticles();

    // Sun follows the player so shadows stay crisp along the whole route.
    this.sunTarget.position.copy(this.player.pos);
    this.sun.position.set(
      this.player.pos.x + 18, this.player.pos.y + 34, this.player.pos.z + 14);

    const { total } = this._currentScore();
    this.ui.setScore(total);
    this.ui.setTimer(this.gameTime);
  }

  _checkPickups() {
    const p = this.player.pos;
    for (const core of this.level.cores) {
      if (core.collected) continue;
      if (_v.set(p.x, p.y + 0.9, p.z).distanceTo(core.pos) < 1.6) {
        core.collected = true;
        core.holder.visible = false;
        this.coresCollected += 1;
        this.audio.core(this.coresCollected);
        this.particles.burst(core.pos,
          { count: 30, color: 0x10ffe0, speed: 6, life: 0.9, gravity: 3 });
        this.spawnShockwave(core.pos, 0x10ffe0, 8, 0.6);
        this.ui.setCores(this.coresCollected, LEVEL.cores.length);
        if (this.coresCollected === LEVEL.cores.length) {
          this.level.activatePortal();
          this.portalActivated = true;
          this.audio.portal();
          this.ui.toast('ALL CORES ONLINE — the escape portal is open!', 4200);
          this.spawnShockwave(this.level.portal.pos, 0xa050ff, 24, 1.2);
        } else {
          this.ui.toast(
            `Energy core secured (${this.coresCollected}/${LEVEL.cores.length})`);
        }
      }
    }
    for (const c of this.level.crystals) {
      if (c.collected) continue;
      if (_v.set(p.x, p.y + 0.9, p.z).distanceTo(c.pos) < 1.5) {
        c.collected = true;
        c.holder.visible = false;
        this.crystalsCollected += 1;
        this.audio.crystal();
        this.particles.burst(c.pos,
          { count: 20, color: 0x54ffa0, speed: 5, life: 0.8, gravity: 3 });
        this.ui.setCrystals(this.crystalsCollected, LEVEL.crystals.length);
        this.ui.toast('Bonus crystal found!');
      }
    }
  }

  _checkCheckpoints() {
    const p = this.player.pos;
    for (const cp of this.level.checkpoints) {
      if (cp.active) continue;
      const d = Math.hypot(p.x - cp.pos[0], p.z - cp.pos[2]);
      if (d < 2.4 && Math.abs(p.y - cp.pos[1]) < 2.5) {
        cp.active = true;
        cp.ringMat.color.setHex(0x35e0ff);
        cp.ringMat.emissive.setHex(0x35e0ff);
        cp.ringMat.emissiveIntensity = 1.4;
        this.respawnPoint = cp.pos;
        this.audio.checkpoint();
        this.spawnShockwave(_v.set(cp.pos[0], cp.pos[1], cp.pos[2]), 0x35e0ff, 7, 0.7);
        this.particles.burst(_v.set(cp.pos[0], cp.pos[1] + 1.6, cp.pos[2]),
          { count: 24, color: 0x35e0ff, speed: 4, life: 0.9, gravity: 2 });
        this.ui.toast('Checkpoint activated');
      }
    }
  }

  _checkTutorials() {
    const p = this.player.pos;
    for (const t of this.level.tutorials) {
      if (t.done) continue;
      if (Math.hypot(p.x - t.x, p.z - t.z) < t.r && Math.abs(p.y - t.y) < 3) {
        t.done = true;
        this.ui.toast(t.msg, 4200);
      }
    }
  }

  _checkPortal() {
    if (!this.level.portal.active) return;
    const p = this.player.pos;
    const portal = this.level.portal.pos;
    const d = Math.hypot(p.x - portal.x, p.z - portal.z);
    if (d < 1.7 && p.y > portal.y - 0.6 && p.y < portal.y + 3.4) {
      this._victory();
    }
  }

  _updateLightshift(dt) {
    const C = CONFIG;
    if (this.lsState === 'ready' && this.input.pressed('lightshift')) {
      this.lsState = 'active';
      this.lsTimer = C.lightshiftDuration;
      this.audio.lightshift();
      this.ui.pulseLightshift();
      this.spawnShockwave(this.player.pos, 0x35e0ff, 22, 1.1);
      this.particles.burst(
        _v.set(this.player.pos.x, this.player.pos.y + 1, this.player.pos.z),
        { count: 40, color: 0x66f0ff, speed: 7, life: 1, gravity: 0 });
    } else if (this.lsState === 'active') {
      this.lsTimer -= dt;
      if (this.lsTimer <= 0) {
        this.lsState = 'cooldown';
        this.lsTimer = C.lightshiftCooldown;
        this.audio.lightshiftEnd();
      }
    } else if (this.lsState === 'cooldown') {
      this.lsTimer -= dt;
      if (this.lsTimer <= 0) {
        this.lsState = 'ready';
        this.audio.lightshiftReady();
      }
    }

    const target = this.lsState === 'active' ? 1 : 0;
    this.revealFactor = damp(this.revealFactor, target, 6, dt);
    this.level.setReveal(this.revealFactor);
    for (const d of this.drones) d.setReveal(this.revealFactor);
    this.player.setLightshiftGlow(this.revealFactor);
    this.scene.fog.color.lerpColors(FOG_BASE, FOG_SHIFT, this.revealFactor * 0.7);

    if (this.lsState === 'active') {
      this.ui.setLightshift('active', this.lsTimer / C.lightshiftDuration);
    } else if (this.lsState === 'cooldown') {
      this.ui.setLightshift('cooldown', 1 - this.lsTimer / C.lightshiftCooldown);
    } else {
      this.ui.setLightshift('ready', 1);
    }
  }

  _updateCamera(dt) {
    const C = CONFIG.camera;
    const look = this.input.consumeLook();
    this.camYaw -= look.dx * 0.005;
    this.camPitch = clamp(this.camPitch + look.dy * 0.004, C.minPitch, C.maxPitch);
    this.camDist = clamp(this.camDist + look.wheel * 0.008, C.minDist, C.maxDist);

    _camTarget.set(
      this.player.pos.x, this.player.pos.y + 1.7, this.player.pos.z);
    const cp = Math.cos(this.camPitch);
    _camDesired.set(
      _camTarget.x + Math.sin(this.camYaw) * cp * this.camDist,
      _camTarget.y + Math.sin(this.camPitch) * this.camDist,
      _camTarget.z + Math.cos(this.camYaw) * cp * this.camDist);

    const k = 1 - Math.exp(-7 * dt);
    this.camera.position.lerp(_camDesired, k);

    // Screen shake — decaying random offset.
    this.shakeAmp = damp(this.shakeAmp, 0, 5, dt);
    if (this.shakeAmp > 0.005) {
      this.camera.position.x += (Math.random() - 0.5) * this.shakeAmp;
      this.camera.position.y += (Math.random() - 0.5) * this.shakeAmp;
      this.camera.position.z += (Math.random() - 0.5) * this.shakeAmp;
    }
    this.camera.lookAt(_camTarget);

    // Slight FOV kick while boosting.
    const targetFov = this.player.isBoosting ? C.boostFov : C.fov;
    if (Math.abs(this.camera.fov - targetFov) > 0.05) {
      this.camera.fov = damp(this.camera.fov, targetFov, 6, dt);
      this.camera.updateProjectionMatrix();
    }
  }

  _snapCamera() {
    _camTarget.set(
      this.player.pos.x, this.player.pos.y + 1.7, this.player.pos.z);
    const cp = Math.cos(this.camPitch);
    this.camera.position.set(
      _camTarget.x + Math.sin(this.camYaw) * cp * this.camDist,
      _camTarget.y + Math.sin(this.camPitch) * this.camDist,
      _camTarget.z + Math.cos(this.camYaw) * cp * this.camDist);
    this.camera.lookAt(_camTarget);
  }

  _updateShockwaves(dt) {
    for (const sw of this.shockwaves) {
      if (!sw.mesh.visible) continue;
      sw.age += dt;
      const f = sw.age / sw.duration;
      if (f >= 1) {
        sw.mesh.visible = false;
        continue;
      }
      const eased = 1 - Math.pow(1 - f, 2);
      sw.mesh.scale.setScalar(0.2 + eased * sw.maxR);
      sw.mesh.material.opacity = 0.7 * (1 - f);
    }
  }

  _emitPortalParticles() {
    if (!this.level || !this.level.portal.active) return;
    if (Math.random() > 0.5) return;
    const portal = this.level.portal.pos;
    const a = Math.random() * Math.PI * 2;
    const r = 1.9;
    this.particles.spawn(
      portal.x + Math.cos(a) * r,
      portal.y + 2.3 + Math.sin(a) * r,
      portal.z + (Math.random() - 0.5) * 0.4,
      -Math.cos(a) * 1.2, -Math.sin(a) * 1.2, 0,
      Math.random() < 0.5 ? 0xa050ff : 0x35e0ff, 1.3, 0);
  }

  _syncAudioButtons() {
    this.ui.setAudioButtons(this.audio.sfxEnabled, this.audio.musicEnabled);
  }

  _onResize() {
    this.camera.aspect = window.innerWidth / window.innerHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  }
}
