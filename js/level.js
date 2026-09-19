import * as THREE from './lib/three.module.js';
import { LEVEL } from './config.js';
import { lerp, makeHalo } from './util.js';

const Y_AXIS = new THREE.Vector3(0, 1, 0);
const _v = new THREE.Vector3();

export class Level {
  constructor(scene, assets) {
    this.scene = scene;
    this.assets = assets;
    this.group = new THREE.Group();
    this.colliders = [];
    this.movers = [];
    this.spinners = [];
    this.cores = [];
    this.crystals = [];
    this.checkpoints = [];
    this.hiddenMats = [];   // materials revealed by Lightshift
    this.tutorials = LEVEL.tutorials.map((t) => ({ ...t, done: false }));
    this.killY = LEVEL.killY;
    this.spawn = LEVEL.spawn;

    this._islandMat = new THREE.MeshStandardMaterial({
      color: 0x2a3560, metalness: 0.15, roughness: 0.85, flatShading: true,
    });
    this._islandSideMat = new THREE.MeshStandardMaterial({
      color: 0x1a2140, metalness: 0.2, roughness: 0.9, flatShading: true,
    });
    this._rimMat = new THREE.MeshStandardMaterial({
      color: 0x35e0ff, emissive: 0x2090b0, emissiveIntensity: 0.7,
      metalness: 0.4, roughness: 0.5,
    });
    this._platMat = new THREE.MeshStandardMaterial({
      color: 0x394a80, metalness: 0.3, roughness: 0.7, flatShading: true,
    });
    this._moverMat = new THREE.MeshStandardMaterial({
      color: 0x3a5a9a, emissive: 0x1a4a7a, emissiveIntensity: 0.5,
      metalness: 0.4, roughness: 0.6, flatShading: true,
    });

    for (const island of LEVEL.islands) this._buildIsland(island);
    for (const p of LEVEL.platforms) this._buildPlatform(p);
    for (const m of LEVEL.movers) this._buildMover(m);
    for (const s of LEVEL.spinners) this._buildSpinner(s);
    LEVEL.cores.forEach((c, i) => this._buildCore(c, i));
    LEVEL.crystals.forEach((c, i) => this._buildCrystal(c, i));
    LEVEL.checkpoints.forEach((c, i) => this._buildCheckpoint(c, i));
    this._buildPortal(LEVEL.portal);

    scene.add(this.group);
  }

  // ---------- construction ----------

  _buildIsland({ x, y, z, r }) {
    const bodyH = 2.2;
    const top = new THREE.Mesh(
      new THREE.CylinderGeometry(r, r * 0.9, bodyH, 12, 1), this._islandMat);
    top.position.set(x, y - bodyH / 2, z);
    top.castShadow = true;
    top.receiveShadow = true;
    this.group.add(top);

    const under = new THREE.Mesh(
      new THREE.ConeGeometry(r * 0.88, r * 0.95, 12, 1), this._islandSideMat);
    under.rotation.x = Math.PI;
    under.position.set(x, y - bodyH - r * 0.45, z);
    this.group.add(under);

    const rim = new THREE.Mesh(
      new THREE.TorusGeometry(r - 0.15, 0.09, 6, 36), this._rimMat);
    rim.rotation.x = Math.PI / 2;
    rim.position.set(x, y + 0.02, z);
    this.group.add(rim);

    // Cool under-glow beacon cone.
    const glow = new THREE.Mesh(
      new THREE.ConeGeometry(r * 0.55, r * 1.6, 10, 1, true),
      new THREE.MeshBasicMaterial({
        color: 0x2a50c0, transparent: true, opacity: 0.07,
        blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
      }));
    glow.rotation.x = Math.PI;
    glow.position.set(x, y - bodyH - r * 0.8, z);
    this.group.add(glow);

    // A few decorative low-poly rocks near the rim.
    const rockMat = this._islandSideMat;
    const rockCount = Math.max(2, Math.floor(r / 4));
    for (let i = 0; i < rockCount; i++) {
      const a = (i / rockCount) * Math.PI * 2 + r; // deterministic-ish scatter
      const rockR = 0.35 + ((i * 7 + r) % 3) * 0.18;
      const rock = new THREE.Mesh(new THREE.DodecahedronGeometry(rockR, 0), rockMat);
      rock.position.set(
        x + Math.cos(a) * (r - 1.6),
        y + rockR * 0.5,
        z + Math.sin(a) * (r - 1.6));
      rock.rotation.set(i, a, i * 0.7);
      rock.castShadow = true;
      this.group.add(rock);
    }

    this.colliders.push({ type: 'cyl', x, z, radius: r, topY: y, bottomY: y - bodyH - 1 });
  }

  _buildPlatform({ x, y, z, w, d, h = 0.6, hidden = false }) {
    let mat = this._platMat;
    if (hidden) {
      mat = new THREE.MeshStandardMaterial({
        color: 0x35e0ff, emissive: 0x35e0ff, emissiveIntensity: 0.15,
        metalness: 0.2, roughness: 0.4, transparent: true, opacity: 0.06,
        flatShading: true, depthWrite: false,
      });
      this.hiddenMats.push(mat);
    }
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat);
    mesh.position.set(x, y - h / 2, z);
    if (!hidden) {
      mesh.castShadow = true;
      mesh.receiveShadow = true;
    }
    this.group.add(mesh);

    // Neon edge outline — brighter on hidden platforms when revealed.
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(mesh.geometry),
      new THREE.LineBasicMaterial({
        color: hidden ? 0x66f0ff : 0x3fa0d0,
        transparent: true,
        opacity: hidden ? 0.1 : 0.5,
      }));
    edges.position.copy(mesh.position);
    this.group.add(edges);
    if (hidden) this.hiddenMats.push(edges.material);

    this.colliders.push({
      type: 'box',
      center: mesh.position.clone(),
      half: { x: w / 2, y: h / 2, z: d / 2 },
    });
  }

  _buildMover({ x, y, z, w, d, axis, from, to, period }) {
    const h = 0.6;
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), this._moverMat);
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    this.group.add(mesh);
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(mesh.geometry),
      new THREE.LineBasicMaterial({ color: 0x5fd0ff, transparent: true, opacity: 0.8 }));
    this.group.add(edges);

    const collider = {
      type: 'box',
      center: new THREE.Vector3(x, y - h / 2, z),
      half: { x: w / 2, y: h / 2, z: d / 2 },
      delta: new THREE.Vector3(),
      prevTop: y,
    };
    this.colliders.push(collider);
    this.movers.push({ mesh, edges, collider, axis, from, to, period, baseX: x, baseY: y, baseZ: z, h });
  }

  _buildSpinner({ x, y, z, len, speed }) {
    const pivot = new THREE.Group();
    pivot.position.set(x, y, z);
    this.group.add(pivot);

    const hub = new THREE.Mesh(
      new THREE.CylinderGeometry(0.5, 0.6, 1.1, 8),
      new THREE.MeshStandardMaterial({
        color: 0x2a2f3a, metalness: 0.7, roughness: 0.35, flatShading: true,
      }));
    hub.position.y = 0.55;
    hub.castShadow = true;
    pivot.add(hub);

    const armMat = new THREE.MeshStandardMaterial({
      color: 0x813a9a, emissive: 0x9a30c0, emissiveIntensity: 0.7,
      metalness: 0.5, roughness: 0.4, flatShading: true,
    });
    const armGeo = new THREE.BoxGeometry(len * 2, 0.45, 0.6);
    const arm = new THREE.Mesh(armGeo, armMat);
    arm.position.y = 0.62;
    arm.castShadow = true;
    pivot.add(arm);
    const tipMat = new THREE.MeshStandardMaterial({
      color: 0xff40ff, emissive: 0xff30f0, emissiveIntensity: 1.6,
      metalness: 0.2, roughness: 0.4,
    });
    for (const side of [-1, 1]) {
      const tip = new THREE.Mesh(new THREE.SphereGeometry(0.32, 8, 6), tipMat);
      tip.position.set(side * len, 0.62, 0);
      pivot.add(tip);
    }

    this.spinners.push({ pivot, x, y, z, len, speed, angle: 0 });
  }

  _buildCore([x, y, z], index) {
    const holder = new THREE.Group();
    holder.position.set(x, y, z);
    const mat = new THREE.MeshStandardMaterial({
      color: 0x10ffe0, emissive: 0x10ffe0, emissiveIntensity: 1.3,
      metalness: 0.1, roughness: 0.3, flatShading: true,
    });
    const mesh = new THREE.Mesh(new THREE.OctahedronGeometry(0.55, 0), mat);
    holder.add(mesh);
    const inner = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.28, 0),
      new THREE.MeshBasicMaterial({ color: 0x9fffec }));
    holder.add(inner);
    const halo = makeHalo(this.assets.glowTexture, 0x10ffe0, 2.8, 0.55);
    holder.add(halo);
    this.group.add(holder);
    this.cores.push({
      holder, mesh, halo, mat,
      pos: new THREE.Vector3(x, y, z),
      baseY: y,
      collected: false,
      phase: index * 1.3,
    });
  }

  _buildCrystal([x, y, z], index) {
    const holder = new THREE.Group();
    holder.position.set(x, y, z);
    const mat = new THREE.MeshStandardMaterial({
      color: 0x54ffa0, emissive: 0x30ff90, emissiveIntensity: 1.4,
      metalness: 0.1, roughness: 0.35, flatShading: true,
      transparent: true, opacity: 0.08, depthWrite: false,
    });
    this.hiddenMats.push(mat);
    const mesh = new THREE.Mesh(new THREE.IcosahedronGeometry(0.42, 0), mat);
    holder.add(mesh);
    const halo = makeHalo(this.assets.glowTexture, 0x54ffa0, 2.2, 0.0);
    holder.add(halo);
    this.group.add(holder);
    this.crystals.push({
      holder, mesh, halo, mat,
      pos: new THREE.Vector3(x, y, z),
      baseY: y,
      collected: false,
      phase: index * 2.1,
    });
  }

  _buildCheckpoint([x, y, z], index) {
    const g = new THREE.Group();
    g.position.set(x, y, z);

    const base = new THREE.Mesh(
      new THREE.CylinderGeometry(1.0, 1.2, 0.35, 8),
      new THREE.MeshStandardMaterial({
        color: 0x30405a, metalness: 0.6, roughness: 0.4, flatShading: true,
      }));
    base.position.y = 0.17;
    base.castShadow = true;
    base.receiveShadow = true;
    g.add(base);

    const ringMat = new THREE.MeshStandardMaterial({
      color: 0x506a8a, emissive: 0x203a50, emissiveIntensity: 0.6,
      metalness: 0.5, roughness: 0.4,
    });
    const ring = new THREE.Mesh(new THREE.TorusGeometry(0.75, 0.09, 8, 24), ringMat);
    ring.position.y = 1.6;
    g.add(ring);

    const beam = new THREE.Mesh(
      new THREE.CylinderGeometry(0.55, 0.75, 9, 12, 1, true),
      new THREE.MeshBasicMaterial({
        color: 0x35e0ff, transparent: true, opacity: 0,
        blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
      }));
    beam.position.y = 4.5;
    g.add(beam);

    this.group.add(g);
    this.checkpoints.push({
      group: g, ring, ringMat, beam,
      pos: [x, y, z],
      active: false,
      index,
    });
  }

  _buildPortal({ x, y, z, daisR }) {
    const g = new THREE.Group();
    g.position.set(x, y, z);

    const dais = new THREE.Mesh(
      new THREE.CylinderGeometry(daisR, daisR + 0.5, 1.2, 10),
      new THREE.MeshStandardMaterial({
        color: 0x2a3050, metalness: 0.5, roughness: 0.5, flatShading: true,
      }));
    dais.position.y = -0.6;
    dais.castShadow = true;
    dais.receiveShadow = true;
    g.add(dais);
    this.colliders.push({
      type: 'cyl', x, z, radius: daisR, topY: y, bottomY: y - 1.2,
    });

    this.portalRingMat = new THREE.MeshStandardMaterial({
      color: 0x35202a, emissive: 0x502060, emissiveIntensity: 0.25,
      metalness: 0.7, roughness: 0.35, flatShading: true,
    });
    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(1.9, 0.28, 8, 28), this.portalRingMat);
    ring.position.y = 2.3;
    g.add(ring);
    this.portalRing = ring;

    // Swirling event-horizon disc (custom shader, procedural).
    this.portalUniforms = {
      uTime: { value: 0 },
      uActive: { value: 0 },
    };
    const disc = new THREE.Mesh(
      new THREE.CircleGeometry(1.65, 40),
      new THREE.ShaderMaterial({
        uniforms: this.portalUniforms,
        transparent: true,
        depthWrite: false,
        side: THREE.DoubleSide,
        vertexShader: `
          varying vec2 vUv;
          void main() {
            vUv = uv;
            gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
          }`,
        fragmentShader: `
          uniform float uTime;
          uniform float uActive;
          varying vec2 vUv;
          void main() {
            vec2 p = vUv - 0.5;
            float r = length(p) * 2.0;
            float a = atan(p.y, p.x);
            float swirl = sin(a * 5.0 - uTime * 2.5 + r * 9.0) * 0.5 + 0.5;
            vec3 cyan = vec3(0.2, 0.85, 1.0);
            vec3 purple = vec3(0.6, 0.25, 1.0);
            vec3 col = mix(purple, cyan, swirl) * (1.2 - r * 0.7);
            float alpha = uActive * smoothstep(1.0, 0.85, r) * (0.55 + swirl * 0.45);
            gl_FragColor = vec4(col * uActive, alpha);
          }`,
      }));
    disc.position.y = 2.3;
    g.add(disc);
    this.portalDisc = disc;

    this.portalLight = new THREE.PointLight(0xa050ff, 0, 20, 2);
    this.portalLight.position.y = 2.5;
    g.add(this.portalLight);

    const halo = makeHalo(this.assets.glowTexture, 0xa050ff, 7, 0.0);
    halo.position.y = 2.3;
    g.add(halo);
    this.portalHalo = halo;

    this.group.add(g);
    this.portal = {
      group: g,
      pos: new THREE.Vector3(x, y, z),
      active: false,
    };
  }

  // ---------- runtime ----------

  activatePortal() {
    this.portal.active = true;
  }

  update(dt, time) {
    // Moving platforms (sinusoidal ping-pong).
    for (const m of this.movers) {
      const mid = (m.from + m.to) / 2;
      const amp = (m.to - m.from) / 2;
      const value = mid + amp * Math.sin((time / m.period) * Math.PI * 2);
      const c = m.collider;
      m.collider.prevTop = c.center.y + c.half.y;
      const old = _v.copy(c.center);
      if (m.axis === 'x') c.center.x = value;
      else if (m.axis === 'y') c.center.y = value - m.h / 2;
      else c.center.z = value;
      c.delta.subVectors(c.center, old);
      m.mesh.position.copy(c.center);
      m.edges.position.copy(c.center);
    }

    // Spinners.
    for (const s of this.spinners) {
      s.angle += s.speed * dt;
      s.pivot.rotation.y = s.angle;
    }

    // Collectibles idle animation.
    for (const core of this.cores) {
      if (core.collected) continue;
      core.mesh.rotation.y += dt * 1.8;
      core.mesh.rotation.x += dt * 0.7;
      core.holder.position.y = core.baseY + Math.sin(time * 2 + core.phase) * 0.22;
      core.halo.material.opacity = 0.45 + Math.sin(time * 3 + core.phase) * 0.15;
    }
    for (const c of this.crystals) {
      if (c.collected) continue;
      c.mesh.rotation.y += dt * 2.2;
      c.holder.position.y = c.baseY + Math.sin(time * 2.4 + c.phase) * 0.15;
    }

    // Checkpoint rings spin when active.
    for (const cp of this.checkpoints) {
      cp.ring.rotation.y += dt * (cp.active ? 2.5 : 0.4);
      if (cp.active) {
        cp.beam.material.opacity = 0.1 + Math.sin(time * 2.5) * 0.04;
      }
    }

    // Portal.
    this.portalUniforms.uTime.value = time;
    const target = this.portal.active ? 1 : 0;
    const u = this.portalUniforms.uActive;
    u.value = lerp(u.value, target, Math.min(1, dt * 2));
    this.portalRing.rotation.z += dt * (0.2 + u.value * 1.2);
    this.portalRingMat.emissive.setHex(this.portal.active ? 0xa040ff : 0x502060);
    this.portalRingMat.emissiveIntensity = 0.25 + u.value * 1.6 +
      Math.sin(time * 4) * 0.25 * u.value;
    this.portalLight.intensity = u.value * (46 + Math.sin(time * 4) * 10);
    this.portalHalo.material.opacity = u.value * (0.5 + Math.sin(time * 3) * 0.12);
  }

  // f = 0..1 Lightshift reveal amount.
  setReveal(f) {
    for (const mat of this.hiddenMats) {
      if (mat.isLineBasicMaterial) {
        mat.opacity = lerp(0.1, 0.95, f);
      } else {
        mat.opacity = lerp(0.07, 0.92, f);
        if (mat.emissiveIntensity !== undefined) {
          mat.emissiveIntensity = lerp(0.2, 1.6, f);
        }
      }
    }
    for (const c of this.crystals) {
      if (!c.collected) c.halo.material.opacity = 0.55 * f;
    }
  }

  // Push the player out of rotating arms; returns knockback info or null.
  checkSpinners(player) {
    const r = 0.5;
    let result = null;
    for (const s of this.spinners) {
      const armBottom = s.y + 0.25;
      const armTop = s.y + 1.0;
      if (player.pos.y > armTop || player.pos.y + 1.6 < armBottom) continue;
      _v.set(player.pos.x - s.x, 0, player.pos.z - s.z);
      const local = _v.applyAxisAngle(Y_AXIS, -s.angle);
      if (Math.abs(local.x) < s.len + 0.3 && Math.abs(local.z) < 0.55 + r) {
        const side = local.z >= 0 ? 1 : -1;
        // Separate, then hand back a world-space knock direction.
        local.z = side * (0.55 + r + 0.05);
        const world = local.applyAxisAngle(Y_AXIS, s.angle);
        player.pos.x = s.x + world.x;
        player.pos.z = s.z + world.z;
        if (player.knockCooldown <= 0) {
          player.knockCooldown = 0.4;
          const dir = _v.set(0, 0, side).applyAxisAngle(Y_AXIS, s.angle);
          result = { x: dir.x, z: dir.z };
        }
      }
    }
    return result;
  }

  dispose() {
    this.scene.remove(this.group);
    this.group.traverse((obj) => {
      if (obj.geometry) obj.geometry.dispose();
      if (obj.material) {
        const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
        // Shared glow texture belongs to the game — don't dispose it here.
        mats.forEach((m) => m.dispose());
      }
    });
  }
}
