// Headless sanity check: verifies that every jump on the intended route is
// physically possible with the movement constants in js/config.js.
// Run with: node tests/reachability.mjs

import { CONFIG, LEVEL } from '../js/config.js';

const g = CONFIG.gravity;
const v0 = CONFIG.jumpSpeed;
const apex = (v0 * v0) / (2 * g);

// Horizontal distance reachable when landing `rise` units above takeoff
// (negative rise = landing lower), at a given run speed.
function jumpRange(speed, rise) {
  if (rise > apex) return 0;
  const t = (v0 + Math.sqrt(v0 * v0 - 2 * g * rise)) / g;
  return speed * t;
}

const island = (i) => LEVEL.islands[i];
const plat = (i) => LEVEL.platforms[i];
const mover = (i) => LEVEL.movers[i];

// Closest take-off point on an island rim toward a target.
function rimPoint(isl, tx, tz) {
  const dx = tx - isl.x;
  const dz = tz - isl.z;
  const d = Math.hypot(dx, dz);
  return { x: isl.x + (dx / d) * isl.r, y: isl.y, z: isl.z + (dz / d) * isl.r };
}

// Closest point on a rectangular platform toward a source point.
function platEdge(p, fromX, fromZ) {
  const x = Math.max(p.x - p.w / 2, Math.min(fromX, p.x + p.w / 2));
  const z = Math.max(p.z - p.d / 2, Math.min(fromZ, p.z + p.d / 2));
  return { x, y: p.y, z };
}

let failures = 0;

function checkJump(name, from, to, { boost = false, slack = 0.4 } = {}) {
  const rise = to.y - from.y;
  const dist = Math.hypot(to.x - from.x, to.z - from.z);
  const speed = boost ? CONFIG.boostSpeed : CONFIG.moveSpeed;
  const range = jumpRange(speed, rise);
  const ok = rise <= apex - 0.15 && dist + slack <= range;
  const flag = ok ? 'ok  ' : 'FAIL';
  console.log(
    `${flag} ${name.padEnd(38)} gap=${dist.toFixed(2)} rise=${rise.toFixed(2)} ` +
    `range=${range.toFixed(2)}${boost ? ' (boost)' : ''}`);
  if (!ok) failures += 1;
}

function between(name, a, b, opts) {
  // Jump between two rectangular platforms, edge to edge.
  const ea = platEdge(a, b.x, b.z);
  const eb = platEdge(b, a.x, a.z);
  checkJump(name, ea, eb, opts);
}

console.log(`jump apex = ${apex.toFixed(2)} units\n`);

// --- Start island → stepping stones → island B ---
const A = island(0);
const B = island(1);
checkJump('start rim → stone 1', rimPoint(A, 0, -18.5), platEdge(plat(1), 0, -14));
between('stone 1 → stone 2', plat(1), plat(2));
between('stone 2 → stone 3', plat(2), plat(3));
checkJump('stone 3 → island B',
  platEdge(plat(3), B.x, B.z), rimPoint(B, plat(3).x, plat(3).z));

// Core-1 pillar on the start island.
checkJump('start island → core pillar',
  { x: 9, y: 0, z: -3 }, platEdge(plat(0), 9, -3));

// --- Island B → mover 1 → island C ---
const C = island(2);
const m1 = mover(0);
checkJump('island B rim → mover (near end)',
  rimPoint(B, 0, -60),
  { x: m1.x, y: m1.y, z: m1.from + m1.d / 2 });
checkJump('mover (far end) → island C',
  { x: m1.x, y: m1.y, z: m1.to - m1.d / 2 },
  rimPoint(C, 0, m1.to - m1.d / 2));

// --- Island C secret east path (hidden platforms, crystal 1) ---
checkJump('island C rim → hidden east 1',
  rimPoint(C, plat(4).x, plat(4).z), platEdge(plat(4), C.x, C.z));
between('hidden east 1 → crystal perch', plat(4), plat(5));
between('crystal perch → hidden east 1 (back)', plat(5), plat(4));
checkJump('hidden east 1 → island C (back)',
  platEdge(plat(4), C.x, C.z), rimPoint(C, plat(4).x, plat(4).z));

// --- Island C → elevator → island D ---
const D = island(3);
const m2 = mover(1);
checkJump('island C rim → elevator (low)',
  rimPoint(C, m2.x, m2.z), { x: m2.x, y: m2.from, z: m2.z + m2.d / 2 });
checkJump('elevator (top) → island D',
  { x: m2.x, y: m2.to, z: m2.z - m2.d / 2 }, rimPoint(D, m2.x, m2.z - m2.d / 2));

// --- Island D → east route (spinner) → final island ---
const E = island(4);
checkJump('island D rim → route 1',
  rimPoint(D, plat(6).x, plat(6).z), platEdge(plat(6), D.x, D.z));
between('route 1 → spinner platform', plat(6), plat(7));
between('spinner platform → route 3', plat(7), plat(8));
checkJump('route 3 → final island',
  platEdge(plat(8), E.x, E.z), rimPoint(E, plat(8).x, plat(8).z));

// --- Island D → hidden shortcut → final island ---
checkJump('island D rim → shortcut 1',
  rimPoint(D, plat(9).x, plat(9).z), platEdge(plat(9), D.x, D.z));
between('shortcut 1 → shortcut 2', plat(9), plat(10));
checkJump('shortcut 2 → final island',
  platEdge(plat(10), E.x, E.z), rimPoint(E, plat(10).x, plat(10).z));

// --- Portal dais and crystal-3 ledge ---
checkJump('final island → portal dais',
  { x: 0, y: E.y, z: LEVEL.portal.z + LEVEL.portal.daisR + 1 },
  { x: 0, y: LEVEL.portal.y, z: LEVEL.portal.z + LEVEL.portal.daisR });
checkJump('final island rim → crystal 3 ledge',
  rimPoint(E, plat(11).x, plat(11).z), platEdge(plat(11), E.x, E.z));
between('crystal 3 ledge → return step', plat(11), plat(12));
checkJump('return step → final island',
  platEdge(plat(12), E.x, E.z), rimPoint(E, plat(12).x, plat(12).z));

// --- Collectible placement: each core/crystal must hover near a surface ---
function nearSurface([x, y, z]) {
  for (const isl of LEVEL.islands) {
    if (Math.hypot(x - isl.x, z - isl.z) < isl.r && y - isl.y > 0 && y - isl.y < 3.2) {
      return true;
    }
  }
  for (const p of LEVEL.platforms) {
    if (Math.abs(x - p.x) < p.w / 2 + 0.5 && Math.abs(z - p.z) < p.d / 2 + 0.5 &&
        y - p.y > 0 && y - p.y < 3.2) {
      return true;
    }
  }
  return false;
}
LEVEL.cores.forEach((c, i) => {
  if (!nearSurface(c)) {
    // Core may also sit above a mover path or mid-jump — only core positions
    // directly over islands/platforms are auto-checked.
    console.log(`note core ${i + 1} at [${c}] is not directly above a static surface`);
  }
});
const floating = LEVEL.crystals.filter((c) => !nearSurface(c));
floating.forEach((c) => {
  console.log(`note crystal at [${c}] floats mid-route (grab in flight)`);
});

// --- Phantom-shove audit: no walkable surface may sit inside an island's
// side-push collider band (horizontally within radius+playerR while its top
// is more than 0.25 below the island top and above the island bottom).
function surfaceInPushZone(name, x, z, w, d, topY) {
  for (const isl of LEVEL.islands) {
    const bottomY = isl.y - 3.2;
    if (topY >= isl.y - 0.25 || topY + CONFIG.playerHeight <= bottomY) continue;
    // nearest point of the rectangle (expanded by player radius) to the axis
    const nx = Math.max(x - w / 2 - 0.5, Math.min(isl.x, x + w / 2 + 0.5));
    const nz = Math.max(z - d / 2 - 0.5, Math.min(isl.z, z + d / 2 + 0.5));
    if (Math.hypot(nx - isl.x, nz - isl.z) < isl.r + 0.5) {
      console.log(`FAIL ${name} overlaps push zone of island at z=${isl.z}`);
      failures += 1;
    }
  }
}
LEVEL.platforms.forEach((p, i) =>
  surfaceInPushZone(`platform ${i} (${p.x},${p.y},${p.z})`, p.x, p.z, p.w, p.d, p.y));
for (const m of LEVEL.movers) {
  for (const end of [m.from, m.to]) {
    const x = m.axis === 'x' ? end : m.x;
    const z = m.axis === 'z' ? end : m.z;
    const y = m.axis === 'y' ? end : m.y;
    surfaceInPushZone(`mover end (${x},${y},${z})`, x, z, m.w, m.d, y);
  }
}

console.log(failures === 0
  ? '\nAll route jumps are within movement limits.'
  : `\n${failures} problem(s) — fix the layout!`);
process.exit(failures === 0 ? 0 : 1);
