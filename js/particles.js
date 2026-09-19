import * as THREE from './lib/three.module.js';

// Pooled additive point-sprite particle system shared by every effect.
export class ParticleSystem {
  constructor(scene, texture, max = 900) {
    this.max = max;
    this.positions = new Float32Array(max * 3);
    this.colors = new Float32Array(max * 3);
    this.velocities = new Float32Array(max * 3);
    this.life = new Float32Array(max);
    this.maxLife = new Float32Array(max);
    this.gravity = new Float32Array(max);
    this.baseColor = new Float32Array(max * 3);
    this.cursor = 0;

    // Park dead particles far below the world.
    for (let i = 0; i < max; i++) this.positions[i * 3 + 1] = -9999;

    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.positions, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(this.colors, 3));
    geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 0, -60), 400);

    const mat = new THREE.PointsMaterial({
      size: 0.32,
      map: texture,
      vertexColors: true,
      transparent: true,
      opacity: 0.95,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      sizeAttenuation: true,
    });
    this.points = new THREE.Points(geo, mat);
    this.points.frustumCulled = false;
    scene.add(this.points);

    this._color = new THREE.Color();
  }

  spawn(x, y, z, vx, vy, vz, color, life, gravity = 0) {
    const i = this.cursor;
    this.cursor = (this.cursor + 1) % this.max;
    this.positions[i * 3] = x;
    this.positions[i * 3 + 1] = y;
    this.positions[i * 3 + 2] = z;
    this.velocities[i * 3] = vx;
    this.velocities[i * 3 + 1] = vy;
    this.velocities[i * 3 + 2] = vz;
    this._color.set(color);
    this.baseColor[i * 3] = this._color.r;
    this.baseColor[i * 3 + 1] = this._color.g;
    this.baseColor[i * 3 + 2] = this._color.b;
    this.life[i] = life;
    this.maxLife[i] = life;
    this.gravity[i] = gravity;
  }

  // Radial burst; upBias skews velocities upward (0..1).
  burst(pos, { count = 16, color = 0x35e0ff, speed = 4, life = 0.7,
               gravity = 4, upBias = 0.3 } = {}) {
    for (let n = 0; n < count; n++) {
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(2 * Math.random() - 1);
      const s = speed * (0.4 + Math.random() * 0.6);
      const vx = Math.sin(phi) * Math.cos(theta) * s;
      const vz = Math.sin(phi) * Math.sin(theta) * s;
      let vy = Math.cos(phi) * s;
      vy = vy * (1 - upBias) + Math.abs(vy) * upBias;
      this.spawn(pos.x, pos.y, pos.z, vx, vy, vz, color,
        life * (0.6 + Math.random() * 0.6), gravity);
    }
  }

  update(dt) {
    const p = this.positions;
    const v = this.velocities;
    const c = this.colors;
    for (let i = 0; i < this.max; i++) {
      if (this.life[i] <= 0) continue;
      this.life[i] -= dt;
      const i3 = i * 3;
      if (this.life[i] <= 0) {
        p[i3 + 1] = -9999;
        c[i3] = c[i3 + 1] = c[i3 + 2] = 0;
        continue;
      }
      v[i3 + 1] -= this.gravity[i] * dt;
      p[i3] += v[i3] * dt;
      p[i3 + 1] += v[i3 + 1] * dt;
      p[i3 + 2] += v[i3 + 2] * dt;
      // Additive blending: fading brightness = fading particle.
      const f = this.life[i] / this.maxLife[i];
      c[i3] = this.baseColor[i3] * f;
      c[i3 + 1] = this.baseColor[i3 + 1] * f;
      c[i3 + 2] = this.baseColor[i3 + 2] * f;
    }
    this.points.geometry.attributes.position.needsUpdate = true;
    this.points.geometry.attributes.color.needsUpdate = true;
  }
}
