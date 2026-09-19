import * as THREE from './lib/three.module.js';
import { damp, makeHalo } from './util.js';

const PATROL = 0;
const CHASE = 1;
const RETURN = 2;

const _tmp = new THREE.Vector3();

export class Drone {
  constructor(parent, data, assets) {
    this.waypoints = data.waypoints.map((w) => new THREE.Vector3(w[0], w[1], w[2]));
    this.detect = data.detect;
    this.patrolSpeed = data.patrol;
    this.chaseSpeed = data.chase;
    this.state = PATROL;
    this.wpIndex = 0;
    this.hitCooldown = 0;
    this.phase = Math.random() * Math.PI * 2;

    this.group = new THREE.Group();
    this.group.position.copy(this.waypoints[0]);
    this._buildMesh(assets);
    parent.add(this.group);
  }

  _buildMesh(assets) {
    const visual = new THREE.Group();
    this.visual = visual;
    this.group.add(visual);

    const shellMat = new THREE.MeshStandardMaterial({
      color: 0x252a33, metalness: 0.75, roughness: 0.35, flatShading: true,
    });
    this.coreMat = new THREE.MeshStandardMaterial({
      color: 0xff8c2a, emissive: 0xff7a1a, emissiveIntensity: 1.8,
      metalness: 0.1, roughness: 0.5,
    });

    const shell = new THREE.Mesh(new THREE.SphereGeometry(0.55, 8, 6), shellMat);
    shell.castShadow = true;
    visual.add(shell);

    const core = new THREE.Mesh(new THREE.SphereGeometry(0.3, 8, 6), this.coreMat);
    this.coreMesh = core;
    visual.add(core);

    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.11, 6, 5), this.coreMat);
    eye.position.set(0, 0.05, 0.5);
    visual.add(eye);

    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.68, 0.05, 6, 18),
      new THREE.MeshStandardMaterial({
        color: 0x3a2a1a, emissive: 0xff7a1a, emissiveIntensity: 0.5,
        metalness: 0.6, roughness: 0.4,
      }));
    ring.rotation.x = Math.PI / 2;
    visual.add(ring);

    this.rotor = new THREE.Group();
    const bladeGeo = new THREE.BoxGeometry(1.15, 0.04, 0.1);
    const bladeMat = new THREE.MeshStandardMaterial({
      color: 0x444c58, metalness: 0.6, roughness: 0.4,
    });
    const bladeA = new THREE.Mesh(bladeGeo, bladeMat);
    const bladeB = new THREE.Mesh(bladeGeo, bladeMat);
    bladeB.rotation.y = Math.PI / 2;
    this.rotor.add(bladeA, bladeB);
    this.rotor.position.y = 0.62;
    visual.add(this.rotor);

    this.halo = makeHalo(assets.glowTexture, 0xff7a1a, 2.4, 0.35);
    visual.add(this.halo);

    // Downward scan beam — subtle, always faintly visible.
    const beam = new THREE.Mesh(
      new THREE.ConeGeometry(0.9, 1.8, 12, 1, true),
      new THREE.MeshBasicMaterial({
        color: 0xff8c2a, transparent: true, opacity: 0.06,
        blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
      }));
    beam.rotation.x = Math.PI;
    beam.position.y = -1.1;
    visual.add(beam);

    // Detection zone — revealed by Lightshift.
    const zoneMat = new THREE.MeshBasicMaterial({
      color: 0xff6a1a, transparent: true, opacity: 0,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    });
    this.zoneDisc = new THREE.Mesh(new THREE.CircleGeometry(this.detect, 36), zoneMat);
    this.zoneDisc.rotation.x = -Math.PI / 2;
    this.zoneDisc.position.y = -1.35;
    this.group.add(this.zoneDisc);
    const edgeMat = new THREE.MeshBasicMaterial({
      color: 0xffa040, transparent: true, opacity: 0,
      blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
    });
    this.zoneRing = new THREE.Mesh(
      new THREE.RingGeometry(this.detect - 0.18, this.detect, 48), edgeMat);
    this.zoneRing.rotation.x = -Math.PI / 2;
    this.zoneRing.position.y = -1.33;
    this.group.add(this.zoneRing);
  }

  get pos() { return this.group.position; }
  get isChasing() { return this.state === CHASE; }

  // Returns 'hit' when the drone touches a vulnerable player.
  update(dt, player, audio, time) {
    this.hitCooldown = Math.max(0, this.hitCooldown - dt);
    const playerCenter = _tmp.set(
      player.pos.x, player.pos.y + 0.9, player.pos.z);
    const flatDist = Math.hypot(
      playerCenter.x - this.pos.x, playerCenter.z - this.pos.z);
    const dy = Math.abs(playerCenter.y - this.pos.y);

    const canSee = flatDist < this.detect && dy < 4 && player.invulnTimer <= 0;

    if (this.state === PATROL) {
      if (canSee) {
        this.state = CHASE;
        audio.alert();
      } else {
        this._moveToward(this.waypoints[this.wpIndex], this.patrolSpeed, dt);
        if (this.pos.distanceTo(this.waypoints[this.wpIndex]) < 0.5) {
          this.wpIndex = (this.wpIndex + 1) % this.waypoints.length;
        }
      }
    } else if (this.state === CHASE) {
      const lost = flatDist > this.detect + 5 || dy > 6 || player.invulnTimer > 0;
      if (lost) {
        this.state = RETURN;
      } else {
        _tmp.y += 0.5; // aim slightly above the player's center
        this._moveToward(_tmp, this.chaseSpeed, dt);
      }
    } else { // RETURN
      let nearest = 0;
      let nearestD = Infinity;
      for (let i = 0; i < this.waypoints.length; i++) {
        const d = this.pos.distanceTo(this.waypoints[i]);
        if (d < nearestD) { nearestD = d; nearest = i; }
      }
      this.wpIndex = nearest;
      this._moveToward(this.waypoints[nearest], this.patrolSpeed * 1.4, dt);
      if (nearestD < 0.6) this.state = PATROL;
    }

    // --- visuals ---
    const chasing = this.state === CHASE;
    this.rotor.rotation.y += (chasing ? 32 : 18) * dt;
    this.visual.position.y = Math.sin(time * 2 + this.phase) * 0.18;
    this.coreMat.emissive.setHex(chasing ? 0xff2020 : 0xff7a1a);
    this.coreMat.emissiveIntensity = chasing ? 2.4 + Math.sin(time * 18) * 0.8 : 1.8;
    this.halo.material.color.setHex(chasing ? 0xff3020 : 0xff7a1a);

    // Face travel direction / the player.
    if (this._lastDir) {
      const target = Math.atan2(this._lastDir.x, this._lastDir.z);
      let diff = target - this.group.rotation.y;
      while (diff > Math.PI) diff -= Math.PI * 2;
      while (diff < -Math.PI) diff += Math.PI * 2;
      this.group.rotation.y += diff * Math.min(1, dt * 5);
    }

    // --- contact damage ---
    if (this.hitCooldown <= 0 && player.invulnTimer <= 0 &&
        flatDist < 1.15 && dy < 1.6) {
      this.hitCooldown = 1;
      return 'hit';
    }
    return null;
  }

  _moveToward(target, speed, dt) {
    const dir = _dir.subVectors(target, this.pos);
    const dist = dir.length();
    if (dist < 1e-4) return;
    dir.divideScalar(dist);
    const step = Math.min(speed * dt, dist);
    this.pos.addScaledVector(dir, step);
    if (!this._lastDir) this._lastDir = new THREE.Vector3();
    this._lastDir.copy(dir);
  }

  onPlayerRespawn() {
    if (this.state === CHASE) this.state = RETURN;
    this.hitCooldown = 1.5;
  }

  setReveal(f) {
    this.zoneDisc.material.opacity = 0.09 * f;
    this.zoneRing.material.opacity = 0.5 * f;
    // Keep the zone drawn at patrol-plane height while chasing dips the drone.
    this.zoneDisc.visible = this.zoneRing.visible = f > 0.01;
  }
}

const _dir = new THREE.Vector3();
