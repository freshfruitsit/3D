// Browser end-to-end playthrough. Requires: npm i playwright (plus a
// Chromium playwright can launch), and the game served at 127.0.0.1:8000
// (python3 -m http.server 8000). Run: node tests/e2e.mjs
// End-to-end playthrough of Lightshift using the real game code paths.
// Drives input where practical and teleports the player along the route to
// exercise pickups, checkpoints, drones, falls, portal, scoring and storage.
import { chromium } from 'playwright';

const BASE = 'http://127.0.0.1:8000';
const results = [];
const check = (name, ok, extra = '') => {
  results.push({ name, ok, extra });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${extra ? ' — ' + extra : ''}`);
};

const browser = await chromium.launch(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {});
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const errors = [];
page.on('pageerror', (e) => errors.push(String(e)));
page.on('console', (m) => {
  if (m.type() === 'error') errors.push(m.text());
});

await page.goto(BASE, { waitUntil: 'networkidle' });
await page.waitForTimeout(1200);

check('page loads without console errors', errors.length === 0, errors.join(' | ').slice(0, 300));
check('start screen visible',
  await page.isVisible('#screen-start'));

// Start the game.
await page.click('#btn-start');
await page.waitForTimeout(600);
check('HUD visible after start', await page.isVisible('#hud'));
check('game state playing',
  await page.evaluate(() => window.__game.state === 'playing'));

const pos = () => page.evaluate(() => {
  const p = window.__game.player.pos;
  return { x: p.x, y: p.y, z: p.z };
});

// Walk forward for one second of GAME time (headless rendering can run below
// 60fps and the game clamps dt, so wall time under-measures speed).
const p0 = await pos();
const t0 = await page.evaluate(() => window.__game.gameTime);
await page.keyboard.down('KeyW');
await page.waitForFunction((t) => window.__game.gameTime > t + 1, t0, { timeout: 15000 });
await page.keyboard.up('KeyW');
const t1 = await page.evaluate(() => window.__game.gameTime);
const p1 = await pos();
const speed = (p0.z - p1.z) / (t1 - t0);
check('WASD movement works', speed > 5, `speed=${speed.toFixed(1)} u/s over ${(t1 - t0).toFixed(2)}s game time`);
check('player stands on island', Math.abs(p1.y) < 0.3, `y=${p1.y.toFixed(2)}`);

// Jump.
await page.keyboard.press('Space');
await page.waitForTimeout(280);
const pJump = await pos();
check('jump lifts the player', pJump.y > 0.5, `y=${pJump.y.toFixed(2)}`);
await page.waitForTimeout(800);

// Lightshift.
await page.keyboard.press('KeyE');
await page.waitForTimeout(300);
check('lightshift activates', await page.evaluate(() => window.__game.lsState === 'active'));
const reveal = await page.evaluate(() => window.__game.revealFactor);
check('reveal factor rising', reveal > 0.3, `f=${reveal.toFixed(2)}`);

// Pause / resume via Escape.
await page.keyboard.press('Escape');
await page.waitForTimeout(200);
check('escape pauses', await page.evaluate(() => window.__game.state === 'paused'));
const tPaused = await page.evaluate(() => window.__game.gameTime);
await page.waitForTimeout(500);
const tPaused2 = await page.evaluate(() => window.__game.gameTime);
check('timer frozen while paused', Math.abs(tPaused2 - tPaused) < 0.01);
await page.keyboard.press('Escape');
await page.waitForTimeout(200);
check('escape resumes', await page.evaluate(() => window.__game.state === 'playing'));

// Teleport helper: move the player's feet, zero velocity, grant invulnerability
// long enough that route drones don't interfere with pickup checks.
const teleport = (x, y, z, invuln = 3) => page.evaluate(([x, y, z, inv]) => {
  const g = window.__game;
  g.player.pos.set(x, y, z);
  g.player.vel.set(0, 0, 0);
  g.player.invulnTimer = inv;
}, [x, y, z, invuln]);

// Checkpoint 1.
await teleport(4.5, 3.2, -33);
await page.waitForTimeout(300);
check('checkpoint 1 activates', await page.evaluate(() =>
  window.__game.level.checkpoints[0].active));
check('respawn point updated', await page.evaluate(() =>
  window.__game.respawnPoint[2] === -33));

// Drone damage: stand under drone 1's patrol with no invulnerability.
await teleport(0, 3.2, -36, 0);
await page.evaluate(() => { window.__game.drones[0].pos.set(0, 4.6, -36); });
await page.waitForTimeout(500);
const afterHit = await page.evaluate(() => ({
  energy: window.__game.energy, hits: window.__game.hits,
  z: window.__game.player.pos.z,
}));
check('drone contact costs energy', afterHit.energy === 2 && afterHit.hits === 1,
  JSON.stringify(afterHit));
check('respawned at checkpoint 1', Math.abs(afterHit.z - -33) < 1.5,
  `z=${afterHit.z.toFixed(1)}`);

// Fall damage.
await page.evaluate(() => { window.__game.player.pos.y = -20; });
await page.waitForTimeout(300);
const afterFall = await page.evaluate(() => ({
  energy: window.__game.energy, falls: window.__game.falls,
}));
check('falling costs energy', afterFall.energy === 1 && afterFall.falls === 1,
  JSON.stringify(afterFall));

// Heal back up for the rest of the run (test hook only).
await page.evaluate(() => {
  window.__game.energy = 3;
  window.__game.ui.setEnergy(3, 3);
});

// Spinner knockback: place player inside spinner-1's arm sweep.
await teleport(2, 5.6, -64);
await page.waitForTimeout(700);
const afterSpin = await page.evaluate(() => {
  const p = window.__game.player.pos;
  return { d: Math.hypot(p.x - 0, p.z + 64), y: p.y };
});
check('spinner shoves the player', afterSpin.d > 1.2, `d=${afterSpin.d.toFixed(2)}`);

// Collect all five cores through the normal pickup path.
const cores = await page.evaluate(() => window.__game.level.cores.map((c) => [c.pos.x, c.pos.y, c.pos.z]));
for (const [x, y, z] of cores) {
  await teleport(x, y - 0.9, z);
  await page.waitForTimeout(250);
}
const coreState = await page.evaluate(() => ({
  collected: window.__game.coresCollected,
  portal: window.__game.level.portal.active,
}));
check('all five cores collectible', coreState.collected === 5, `got ${coreState.collected}`);
check('portal activates after 5 cores', coreState.portal);

// Collect the crystals.
const crystals = await page.evaluate(() =>
  window.__game.level.crystals.map((c) => [c.pos.x, c.pos.y, c.pos.z]));
for (const [x, y, z] of crystals) {
  await teleport(x, y - 0.9, z);
  await page.waitForTimeout(250);
}
check('all crystals collectible', await page.evaluate(() =>
  window.__game.crystalsCollected === 3));

// Checkpoint 2 en route.
await teleport(4.5, 11.7, -83.5);
await page.waitForTimeout(300);
check('checkpoint 2 activates', await page.evaluate(() =>
  window.__game.level.checkpoints[1].active));

// Enter the portal.
await teleport(0, 15.4, -122);
await page.waitForTimeout(600);
check('portal entry triggers victory', await page.evaluate(() =>
  window.__game.state === 'victory'));
await page.waitForTimeout(1400);
check('victory screen shown', await page.isVisible('#screen-victory'));
const bd = await page.evaluate(() => ({
  total: document.getElementById('v-total').textContent,
  best: JSON.parse(localStorage.getItem('lightshift.best')),
}));
check('score breakdown filled', Number(bd.total) > 0, `total=${bd.total}`);
check('best score persisted to localStorage',
  bd.best && bd.best.score > 0 && bd.best.time > 0, JSON.stringify(bd.best));

// Restart from the victory screen.
await page.click('#btn-again');
await page.waitForTimeout(500);
const fresh = await page.evaluate(() => ({
  state: window.__game.state,
  cores: window.__game.coresCollected,
  energy: window.__game.energy,
  portal: window.__game.level.portal.active,
}));
check('play-again resets the run',
  fresh.state === 'playing' && fresh.cores === 0 && fresh.energy === 3 && !fresh.portal,
  JSON.stringify(fresh));

// Game over path: burn all energy.
await page.evaluate(() => { window.__game.energy = 1; });
await page.evaluate(() => { window.__game.player.pos.y = -20; });
await page.waitForTimeout(400);
check('game over at zero energy', await page.evaluate(() =>
  window.__game.state === 'gameover'));
check('game-over screen shown', await page.isVisible('#screen-gameover'));
await page.click('#btn-retry');
await page.waitForTimeout(400);
check('retry restarts', await page.evaluate(() => window.__game.state === 'playing'));

// Audio toggles persist.
await page.click('#btn-sound');
await page.click('#btn-music');
const prefs = await page.evaluate(() => ({
  s: JSON.parse(localStorage.getItem('lightshift.sound')),
  m: JSON.parse(localStorage.getItem('lightshift.music')),
}));
check('audio toggles persist', prefs.s === false && prefs.m === false,
  JSON.stringify(prefs));

// Resize handling.
await page.setViewportSize({ width: 800, height: 500 });
await page.waitForTimeout(200);
check('resize keeps running', await page.evaluate(() =>
  window.__game.renderer.domElement.width > 0 && window.__game.state === 'playing'));

check('no console errors during whole run', errors.length === 0,
  errors.join(' | ').slice(0, 400));

// Screenshots for a visual check.
await page.setViewportSize({ width: 1280, height: 720 });
await page.evaluate(() => {
  const g = window.__game;
  g.player.pos.set(0, 0.1, 2);
  g.player.vel.set(0, 0, 0);
});
await page.waitForTimeout(800);
await page.screenshot({ path: 'shot-start-island.png' });
await page.keyboard.press('KeyE');
await page.waitForTimeout(700);
await page.screenshot({ path: 'shot-lightshift.png' });
await page.evaluate(() => {
  const g = window.__game;
  for (const c of g.level.cores) if (!c.collected) {
    c.collected = true; c.holder.visible = false; g.coresCollected += 1;
  }
  g.level.activatePortal();
  g.player.pos.set(0, 14.1, -110);
  g.player.invulnTimer = 5;
});
await page.waitForTimeout(1200);
await page.screenshot({ path: 'shot-portal.png' });

await browser.close();
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
