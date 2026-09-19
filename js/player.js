import * as THREE from './lib/three.module.js';
import { CONFIG } from './config.js';
import { damp, clamp, makeHalo } from './util.js';

const _forward = new THREE.Vector3();
const _right = new THREE.Vector3();

export class Player {
  constructor(parent, assets) {
    this.group = new THREE.Group();
    this.vel = new THREE.Vector3();
    this.grounded = false;
    this.groundCollider = null;
    this.coyoteTimer = 0;
    this.jumpBufferTimer = 0;
    this.boostTimer = 0;
    this.boostCooldown = 0;
    this.invulnTimer = 0;
    this.knockCooldown = 0;
    this.facing = 0;
    this._prev = new THREE.Vector3();
    this._justLanded = false;
    this._landSpeed = 0;

    this._buildMesh(assets);
    parent.add(this.group);
  }

  _buildMesh(assets) {
    // The visual sub-group bobs/tilts; this.group.position is the physics
    // position (player FEET).
    const visual = new THREE.Group();
    this.visual = visual;
    this.group.add(visual);

    const bodyMat = new THREE.MeshStandardMaterial({
      color: 0x9fb8cc, metalness: 0.65, roughness: 0.3, flatShading: true,
      emissive: 0x18242e, emissiveIntensity: 0.8, // never a full silhouette
    });
    const glowMat = new THREE.MeshStandardMaterial({
      color: 0x35e0ff, emissive: 0x35e0ff, emissiveIntensity: 2.2,
      metalness: 0.1, roughness: 0.4,
    });
    this.glowMat = glowMat;

    const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.42, 0.5, 4, 10), bodyMat);
    body.position.y = 0.82;
    body.castShadow = true;
    visual.add(body);

    const head = new THREE.Mesh(new THREE.SphereGeometry(0.3, 10, 8), bodyMat);
    head.position.y = 1.42;
    head.castShadow = true;
    visual.add(head);

    // Visor faces +z; the group is rotated toward the movement direction.
    const visor = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.12, 0.08), glowMat);
    visor.position.set(0, 1.46, 0.27);
    visual.add(visor);

    const chest = new THREE.Mesh(new THREE.SphereGeometry(0.15, 10, 8), glowMat);
    chest.position.set(0, 0.95, 0.32);
    visual.add(chest);

    const antenna = new THREE.Mesh(
      new THREE.CylinderGeometry(0.02, 0.03, 0.35, 5),
      bodyMat);
    antenna.position.y = 1.85;
    visual.add(antenna);
    const tip = new THREE.Mesh(new THREE.SphereGeometry(0.06, 6, 5), glowMat);
    tip.position.y = 2.02;
    visual.add(tip);

    this.halo = makeHalo(assets.glowTexture, 0x35e0ff, 2.4, 0.45);
    this.halo.position.y = 1.0;
    visual.add(this.halo);

    this.light = new THREE.PointLight(0x35e0ff, 26, 12, 2);
    this.light.position.y = 1.2;
    this.group.add(this.light);
  }

  get pos() { return this.group.position; }

  reset(spawn) {
    this.pos.set(spawn[0], spawn[1], spawn[2]);
    this.vel.set(0, 0, 0);
    this.grounded = false;
    this.groundCollider = null;
    this.coyoteTimer = 0;
    this.jumpBufferTimer = 0;
    this.boostTimer = 0;
    this.boostCooldown = 0;
    this.invulnTimer = 0;
    this.knockCooldown = 0;
    this.facing = Math.PI; // look toward -z, into the level
    this.group.rotation.y = this.facing;
    this.visual.visible = true;
  }

  respawn(point) {
    this.pos.set(point[0], point[1] + 0.1, point[2]);
    this.vel.set(0, 0, 0);
    this.grounded = false;
    this.groundCollider = null;
    this.invulnTimer = CONFIG.invulnTime;
    this.boostTimer = 0;
  }

  get isBoosting() { return this.boostTimer > 0; }

  update(dt, input, camYaw, colliders, audio, particles, time) {
    const C = CONFIG;
    this._justLanded = false;

    // Ride the platform we were standing on last frame.
    if (this.grounded && this.groundCollider && this.groundCollider.delta) {
      this.pos.add(this.groundCollider.delta);
    }

    // --- input → target horizontal velocity (camera-relative) ---
    let ix = 0;
    let iz = 0;
    if (input.down('forward')) iz -= 1;
    if (input.down('back')) iz += 1;
    if (input.down('left')) ix -= 1;
    if (input.down('right')) ix += 1;
    const hasInput = ix !== 0 || iz !== 0;
    if (hasInput) {
      const len = Math.hypot(ix, iz);
      ix /= len;
      iz /= len;
    }
    _forward.set(-Math.sin(camYaw), 0, -Math.cos(camYaw));
    _right.set(Math.cos(camYaw), 0, -Math.sin(camYaw));

    // Boost is a short burst on Shift with a cooldown.
    this.boostCooldown = Math.max(0, this.boostCooldown - dt);
    this.boostTimer = Math.max(0, this.boostTimer - dt);
    if (input.pressed('boost') && this.boostCooldown <= 0 && hasInput) {
      this.boostTimer = C.boostDuration;
      this.boostCooldown = C.boostCooldown;
      audio.boost();
    }

    const speed = this.isBoosting ? C.boostSpeed : C.moveSpeed;
    const targetX = (_forward.x * -iz + _right.x * ix) * speed;
    const targetZ = (_forward.z * -iz + _right.z * ix) * speed;
    const accel = this.grounded ? C.groundAccel : C.airAccel;
    this.vel.x = damp(this.vel.x, targetX, accel, dt);
    this.vel.z = damp(this.vel.z, targetZ, accel, dt);

    // --- jumping ---
    this.coyoteTimer = Math.max(0, this.coyoteTimer - dt);
    this.jumpBufferTimer = Math.max(0, this.jumpBufferTimer - dt);
    if (input.pressed('jump')) this.jumpBufferTimer = C.jumpBuffer;
    if (this.jumpBufferTimer > 0 && (this.grounded || this.coyoteTimer > 0)) {
      this.vel.y = C.jumpSpeed;
      this.grounded = false;
      this.groundCollider = null;
      this.coyoteTimer = 0;
      this.jumpBufferTimer = 0;
      audio.jump();
    }

    // Gravity; releasing Space early cuts the jump short.
    this.vel.y -= C.gravity * dt;
    if (this.vel.y > 0 && !input.down('jump')) this.vel.y -= C.gravity * 0.9 * dt;
    this.vel.y = Math.max(this.vel.y, -34);

    // --- integrate & collide ---
    this._prev.copy(this.pos);
    this.pos.x += this.vel.x * dt;
    this.pos.y += this.vel.y * dt;
    this.pos.z += this.vel.z * dt;
    this._collide(colliders);

    this.knockCooldown = Math.max(0, this.knockCooldown - dt);
    this.invulnTimer = Math.max(0, this.invulnTimer - dt);

    this._animate(dt, time, hasInput, particles);
    return this._justLanded ? this._landSpeed : 0;
  }

  _collide(colliders) {
    const r = CONFIG.playerRadius;
    const h = CONFIG.playerHeight;
    const wasGrounded = this.grounded;
    const prevFeet = this._prev.y;
    let bestTop = -Infinity;
    let bestCol = null;

    for (const c of colliders) {
      if (c.type === 'box') {
        const ex = c.half.x + r;
        const ez = c.half.z + r;
        const dx = this.pos.x - c.center.x;
        const dz = this.pos.z - c.center.z;
        if (Math.abs(dx) >= ex || Math.abs(dz) >= ez) continue;
        const top = c.center.y + c.half.y;
        const bottom = c.center.y - c.half.y;
        const prevTop = c.prevTop !== undefined ? c.prevTop : top;
        if (this.vel.y <= 0.001 && prevFeet >= prevTop - 0.12 && this.pos.y <= top + 0.02) {
          if (top > bestTop) { bestTop = top; bestCol = c; }
        } else if (this.vel.y > 0 && this._prev.y + h <= bottom + 0.06 &&
                   this.pos.y + h >= bottom) {
          this.pos.y = bottom - h;
          this.vel.y = 0;
        } else if (this.pos.y < top - 0.25 && this.pos.y + h > bottom + 0.05) {
          const penX = ex - Math.abs(dx);
          const penZ = ez - Math.abs(dz);
          if (penX < penZ) {
            this.pos.x = c.center.x + Math.sign(dx || 1) * ex;
            this.vel.x = 0;
          } else {
            this.pos.z = c.center.z + Math.sign(dz || 1) * ez;
            this.vel.z = 0;
          }
        }
      } else if (c.type === 'cyl') {
        let dx = this.pos.x - c.x;
        let dz = this.pos.z - c.z;
        const d = Math.hypot(dx, dz);
        if (d >= c.radius + r) continue;
        if (this.vel.y <= 0.001 && prevFeet >= c.topY - 0.12 &&
            this.pos.y <= c.topY + 0.02 && d < c.radius + r * 0.5) {
          if (c.topY > bestTop) { bestTop = c.topY; bestCol = c; }
        } else if (this.pos.y < c.topY - 0.25 && this.pos.y + h > c.bottomY) {
          if (d < 1e-4) { dx = 1; dz = 0; }
          const k = (c.radius + r) / Math.max(d, 1e-4);
          this.pos.x = c.x + dx * k;
          this.pos.z = c.z + dz * k;
        }
      }
    }

    if (bestCol) {
      this.pos.y = bestTop;
      if (!wasGrounded && this.vel.y < -1) {
        this._justLanded = true;
        this._landSpeed = -this.vel.y;
      }
      this.vel.y = 0;
      this.grounded = true;
      this.groundCollider = bestCol;
      this.coyoteTimer = CONFIG.coyoteTime;
    } else {
      if (this.grounded) this.coyoteTimer = CONFIG.coyoteTime;
      this.grounded = false;
      this.groundCollider = null;
    }
  }

  _animate(dt, time, hasInput, particles) {
    const hSpeed = Math.hypot(this.vel.x, this.vel.z);

    // Face the direction of motion.
    if (hSpeed > 0.6) {
      const target = Math.atan2(this.vel.x, this.vel.z);
      let diff = target - this.facing;
      while (diff > Math.PI) diff -= Math.PI * 2;
      while (diff < -Math.PI) diff += Math.PI * 2;
      this.facing += diff * Math.min(1, dt * 10);
      this.group.rotation.y = this.facing;
    }

    // Run bob + forward lean.
    const bobAmount = this.grounded ? Math.min(hSpeed / CONFIG.moveSpeed, 1.4) : 0;
    this.visual.position.y = Math.sin(time * 11) * 0.05 * bobAmount;
    this.visual.rotation.x = damp(this.visual.rotation.x,
      hasInput ? 0.12 * Math.min(hSpeed / CONFIG.moveSpeed, 1.3) : 0, 8, dt);

    // Glow pulses gently; brighter while boosting.
    const pulse = 2 + Math.sin(time * 3) * 0.3 + (this.isBoosting ? 1.2 : 0);
    this.glowMat.emissiveIntensity = pulse;
    this.halo.material.opacity = 0.35 + Math.sin(time * 3) * 0.08 + (this.isBoosting ? 0.25 : 0);

    // Boost trail.
    if (this.isBoosting && Math.random() < 0.85) {
      particles.spawn(
        this.pos.x + (Math.random() - 0.5) * 0.4,
        this.pos.y + 0.5 + Math.random() * 0.5,
        this.pos.z + (Math.random() - 0.5) * 0.4,
        -this.vel.x * 0.25, 0.5, -this.vel.z * 0.25,
        0x35e0ff, 0.45, 0);
    }

    // Invulnerability blink.
    this.visual.visible = this.invulnTimer <= 0 ||
      Math.floor(this.invulnTimer * 11) % 2 === 0;
  }

  setLightshiftGlow(f) {
    this.light.intensity = 26 + f * 34;
    this.halo.scale.setScalar(2.4 + f * 1.6);
  }
}
