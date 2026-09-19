// Gameplay tuning and level layout. Pure data — no Three.js imports — so the
// layout can also be sanity-checked headlessly (see tests/).

export const CONFIG = {
  // Physics
  gravity: 25,
  moveSpeed: 8,
  boostSpeed: 13,
  jumpSpeed: 11,          // apex = jumpSpeed^2 / (2*gravity) ≈ 2.42 units
  groundAccel: 12,        // exponential smoothing rate toward target velocity
  airAccel: 5,
  coyoteTime: 0.12,
  jumpBuffer: 0.15,
  playerRadius: 0.5,
  playerHeight: 1.6,

  // Abilities
  boostDuration: 0.95,
  boostCooldown: 2.4,
  lightshiftDuration: 5,
  lightshiftCooldown: 10,

  // Health
  maxEnergy: 3,
  invulnTime: 2,

  // Scoring
  score: {
    core: 500,
    crystal: 300,
    energy: 200,
    fallPenalty: 100,
    hitPenalty: 100,
    timeBonusBase: 4000,  // decays timeBonusRate points per second
    timeBonusRate: 8,
  },

  // Camera
  camera: {
    fov: 62,
    boostFov: 68,
    minDist: 6,
    maxDist: 13,
    startDist: 9,
    startPitch: 0.38,
    minPitch: -0.1,
    maxPitch: 1.15,
  },
};

// Level geometry. The route runs from the start island at z=0 toward -z.
// All y values are the TOP surface height of the object.
export const LEVEL = {
  spawn: [0, 0.1, 6],
  killY: -14,

  // Floating islands: x, topY, z, radius
  islands: [
    { x: 0, y: 0,    z: 0,    r: 14 },  // start / tutorial island
    { x: 0, y: 3,    z: -36,  r: 8 },   // island B — first drone, checkpoint 1
    { x: 0, y: 5.5,  z: -64,  r: 7 },   // island C — spinner, secret east path
    { x: 0, y: 11.5, z: -86,  r: 8 },   // island D — second drone, checkpoint 2
    { x: 0, y: 14,   z: -116, r: 10 },  // final island — third drone, portal
  ],

  // Static platforms: x, topY, z, width, depth. h = block height (default 0.6),
  // hidden platforms are near-invisible until revealed by Lightshift.
  platforms: [
    { x: 9,    y: 1.5,  z: -6,     w: 3,   d: 3, h: 1.5 },   // core-1 pillar
    { x: 0,    y: 0.8,  z: -18.5,  w: 3.4, d: 3.4 },          // stepping stones
    { x: 2.6,  y: 1.6,  z: -23,    w: 3.4, d: 3.4 },
    { x: -1.8, y: 2.8,  z: -27.6,  w: 3.4, d: 3.4 },
    { x: 9.5,  y: 5.0,  z: -64,    w: 3,   d: 3, hidden: true },  // secret east path
    { x: 13.5, y: 4.6,  z: -68,    w: 3,   d: 3, hidden: true },  // crystal 1 perch
    { x: 5.5,  y: 12.2, z: -97,    w: 3.4, d: 3.4 },          // east route to finale
    { x: 8,    y: 13,   z: -102,   w: 4.6, d: 4.6 },          // spinner-2 platform
    { x: 4.5,  y: 13.85, z: -107,  w: 3.4, d: 3.4 },
    { x: 0,    y: 12.2, z: -97,    w: 3.2, d: 3.2, hidden: true }, // hidden shortcut
    { x: 0,    y: 13,   z: -102,   w: 3.2, d: 3.2, hidden: true },
    { x: 0,    y: 11.8, z: -129.5, w: 3.4, d: 3.4, hidden: true }, // crystal 3 ledge
    { x: 3.6,  y: 12.9, z: -128.6, w: 2.6, d: 2.6, hidden: true }, // return step
  ],

  // Moving platforms: oscillate `axis` between from..to over `period` seconds.
  movers: [
    { x: 0, y: 4, z: -51, w: 4, d: 4, axis: 'z', from: -47, to: -53.8, period: 7 },
    { x: 0, y: 9, z: -76, w: 4, d: 4, axis: 'y', from: 6,   to: 12,    period: 8 },
  ],

  // Rotating arm obstacles: y = floor height the arms sweep above.
  spinners: [
    { x: 0, y: 5.5, z: -64,  len: 4.5, speed: 1.4 },
    { x: 8, y: 13,  z: -102, len: 2.6, speed: 1.8 },
  ],

  cores: [
    [9, 2.7, -6],
    [0, 4.2, -36],
    [0, 6.7, -69.5],
    [-5, 12.7, -89],
    [-6, 15.2, -119],
  ],

  crystals: [
    [13.5, 5.7, -68],   // end of the secret east path
    [0, 14.3, -104],    // floats above the hidden shortcut gap
    [0, 12.9, -129.5],  // hidden ledge behind the portal
  ],

  checkpoints: [
    [4.5, 3, -33],
    [4.5, 11.5, -83.5],
  ],

  portal: { x: 0, y: 15.2, z: -122, daisR: 2.6 },

  drones: [
    { waypoints: [[5, 5.4, -36], [0, 5.4, -31], [-5, 5.4, -36], [0, 5.4, -41]],
      detect: 6, patrol: 2.4, chase: 4.6 },
    { waypoints: [[4, 13.2, -82], [-4, 13.2, -82], [-4, 13.2, -90], [4, 13.2, -90]],
      detect: 6.5, patrol: 3, chase: 5.2 },
    { waypoints: [[5.5, 15.6, -112], [-5.5, 15.6, -112], [-5.5, 15.6, -120], [5.5, 15.6, -120]],
      detect: 8, patrol: 3.4, chase: 5.8 },
  ],

  // One-shot tutorial hint zones on the start island.
  tutorials: [
    { x: 0, y: 0, z: 5, r: 5.5,
      msg: 'Move with WASD or Arrow Keys — drag the mouse to look around' },
    { x: 9, y: 0, z: -1.5, r: 4.5,
      msg: 'Press SPACE to jump — grab that energy core!' },
    { x: 0, y: 0, z: -11, r: 4.5,
      msg: 'SHIFT to boost — press E to Lightshift and reveal what is hidden' },
  ],
};
