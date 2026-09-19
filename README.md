# Lightshift: The Last Spark

A single-player 3D browser game. You are a small glowing robot — the last
spark of a fallen sky-station. Collect the five energy cores scattered across
the floating islands, dodge the warden drones, and escape through the portal.

Built with [Three.js](https://threejs.org) (vendored locally) and plain
HTML/CSS/JavaScript. No build step, no backend, no external assets — every
model, texture, particle, and sound is generated procedurally in code.

## Running the game

The game uses ES modules, so it must be served over HTTP (opening
`index.html` directly from disk will not work). Any static file server is
fine:

```bash
# from the project root — pick whichever you have installed:
python3 -m http.server 8000
# or
npx serve .
```

Then open <http://localhost:8000> in a modern browser (Chrome, Edge,
Firefox, Safari). No configuration or install step is required.

## Controls

| Key | Action |
| --- | --- |
| `W A S D` / arrow keys | Move |
| `Space` | Jump |
| `Shift` | Short speed boost |
| `E` | Lightshift — reveal hidden platforms, shortcuts, collectibles, and drone detection zones (5 s active, 10 s recharge) |
| `Esc` | Pause / resume |
| Mouse drag | Orbit the camera |
| Mouse wheel | Zoom |

## Goal

* Collect all **5 energy cores** to power the escape portal.
* Find the hidden **bonus crystals** (Lightshift reveals them).
* Touching a drone or falling off costs one of your **3 energy points** and
  returns you to the last checkpoint.
* Your final score combines completion time, cores, crystals, remaining
  energy, falls, and drone hits. Best score and fastest time are saved in
  your browser's local storage.

## Project structure

```
index.html          page shell, HUD and menu markup
css/style.css       all UI styling
js/main.js          bootstrap
js/game.js          game orchestration: states, camera, scoring, lightshift
js/level.js         procedural level construction + moving/rotating obstacles
js/player.js        player movement, physics and collision
js/drone.js         enemy drone AI (patrol / chase / return)
js/particles.js     pooled additive particle system
js/audio.js         Web Audio synthesized SFX + ambient music
js/ui.js            HUD, screens, toasts
js/input.js         keyboard + mouse input
js/config.js        gameplay tuning + level layout data
js/util.js          small shared helpers
js/lib/             vendored three.js (MIT, see THREE-LICENSE.txt)
tests/              headless level-reachability check (node tests/reachability.mjs)
```
