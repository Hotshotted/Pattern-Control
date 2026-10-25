# Start-up and frame cost

Every step of the start is timed (`scripts/Boot.gd`: `Boot.mark("step")` prints `[boot] step +N ms (at T ms)` to the console and, on
the web, pushes it to `window.__boot`). `tools/web_boot_check.js` plays the exported web build in headless Chromium under a CPU
slowdown, prints every step and the game's own per-frame cost in a shift, and fails when the game takes too long to build itself
or spends over 33 ms in one frame (CI runs it with `THROTTLE=4`, `LIMIT_BUILD_MS=9000`, `LIMIT_FRAME_MS=33`):

    node tools/web_boot_check.js build/web [chrome]      env: QUERY=perf THROTTLE=4 SHIFT_SECONDS=30 LIMIT_BUILD_MS=.. LIMIT_FRAME_MS=..

`?perf` on the web also makes the game time its own code: `scripts/FrameProbe.gd` (the last `_process` of the frame) against the
first one, in blocks of 30 frames (`window.__procs`). That is the game's share only; a headless browser draws in software, so its raw
frame times (90-130 ms here) are the renderer's and say nothing about a phone.

`tools/profile_frame.gd` (native, headless) switches the game's parts off one at a time on a full International field and prints
what each costs.

## What the numbers were (this sandbox, headless Chromium, 4x CPU slowdown, a local server)

| step | before | after |
|---|---|---|
| engine start (38 MB wasm, scene loaded) | 10.1 s | 9.9-10.6 s (the browser compiling the engine; not ours) |
| the six airports' scenery | 16.1 s | 1.6 s (only the airport it opens on) |
| 16 aircraft models + 24 ramp models | 4.8 s + part of the next | 0.6 s + 14 ramp models 0.07 s |
| the Fx, ribbons, overlay and HUD nodes | 6.6 s (with the ramp models) | 0.3 s |
| diorama, wiring, sounds | 1.0 s | 0.2 s |
| **the game's own build, engine up -> scene built** | **29.5 s** | **2.9 s** |
| pre-warm (every shader and glyph drawn once) | 11.8 s | 9.4 s (the first frame on a software GL; capped at 2.5 s of settling) |
| intro logo (2.4 s of the game's time) | 19.7 s (the engine's delta is held to 1/60 s) | 3.1 s (runs on the wall clock) |
| **menu shown** | **76 s** | **27 s** |

The game's own code in a shift (International-sized traffic, 4x): mean 5 ms, worst 21 ms, none over 33 ms.

## What was slow, and what was done

- **Meshes.** `Prim.box` / `Prim.cyl` built a primitive, ran a GDScript loop over its vertices for the shading colours and made a
  new `ArrayMesh` every time: forty identical aircraft models, hundreds of props. Meshes are now cached by shape and shared
  (one GPU buffer instead of forty). This alone took the aircraft models from 4.8 s to 0.4 s and the airfields from 2.5 s to 0.7 s each.
- **Six airports built before the menu.** Now only the airport the game opens on is built; the others are built a phase at a time
  (7 phases) every 4th frame while a screen other than a shift is up, the unlocked ones first, and `select()` builds a missing one
  whole (`Airfield.boot_lazy = false` builds all six, for the tests).
- **24 ramp models** -> 14: the most any airport shows at once is 8 parked (tie-downs, overflow spots, heli spot, docks) and 4 taxiing.
- **Textures baked at runtime** (the three shadow shapes, the two particle dots, the sparkle: ~20 000 `set_pixel` calls) are now PNGs in
  `assets/textures/`, written by `tools/bake_textures.gd`, imported lossless (no VRAM compression: phones without S3TC would decompress
  them on the CPU) and checked against their formulas by the smoke test.
- **Pre-warm.** It drew everything for at least 1.5 s and until 10 frames in a row were calm, up to 6 s; now 0.6 s / 6 frames / 2.5 s.
  It still draws every material once behind the cover: removing it only moves the shader compiles into the intro logo.
- **The loading page** showed the download and then sat at 100 %. The bar is now the download (the first 40 %) and then the game's own
  steps (`Boot.PROGRESS`, reported through `window.__pwProgress`).
- **Audio.** The page decodes the music loops (off the main thread); they are excluded from the pck, so the engine never decodes them.
  The sound effects are uncompressed WAV (`compress/mode=0`): loading is a copy, no decoding.
- **The intro logo** ran on the engine's frame delta, which is held to one physics tick (1/60 s) whenever frames are slower than that
  (`Engine.max_physics_steps_per_frame = 1`): a 2.4 s intro lasted ten seconds on a slow device. It now runs on the wall clock.
  (The same clamp makes everything driven by `delta` run in slow motion below 60 fps; the shift is built to do that on purpose.)

## Per-frame work that was removed

Setting a material property marks it changed and uploads it again, even to the value it already has. These were written every frame:

- the runway threshold blocks (12 materials on International: colour and glow), the radar-mast, tower and lighthouse lamps, the vehicle
  beacons, the chimney smoke and the pond ripples (`Airfield._process` / `_animate_*`) -> `Prim.paint` / `Prim.glow` write only when
  the value differs (smoke and ripple opacities are also stepped to 1/50);
- each aircraft's shadow opacity (16 shader-parameter writes a frame) -> written when it changes (steps of 0.005);
- the fog layer's three shader parameters and the diorama clouds' opacity (every frame; both layers are gone now, see the cloud shadows) -> only on change;
- the aircraft livery colours -> `Traffic._paint` (earlier).

No tween is created anywhere (there is no `create_tween` in the scripts), and the life props are few: 2 birds, a balloon, a mower, a fuel truck, a few vehicles and chairs per airport.

## The frame-delta clamp (1/20 s)

The engine holds every frame's delta to `max_physics_steps_per_frame / physics_ticks_per_second`. The game used 1 step (1/60 s), so any
device under 60 fps ran in slow motion. `Main._ready` now sets 3 steps: 1/20 s, so the game runs at real speed down to 20 fps and only
slower below that (a tab-switch spike is still never simulated). Checked on the web: a slow frame is simulated up to 50 ms (it was 17 ms).

Because a step can now be 50 ms, `tools/step_micro.gd` runs each system on its own at 60, 30 and 20 steps a second (path following, a
landing, circling, the aircraft timer, the go-around warning, taxiing, the wind clock, a conflict pass, a flight past a storm's edge)
and `tools/step_compare.py` compares the whole economy / fairness survey (`economy_sim.gd survey totals fps=N`, all bots and airports,
10 shifts each) at the three step sizes: landings, crashes and gross coins must agree within 5%, or within 2.5 standard errors of the sampling noise: each run is exactly
repeatable (`Main.fixed_seed`), but a different step size is a different sample of a chaotic game, so two runs of 130 crashes differ by
~12% with no bias at all. The per-system checks above are the exact ones. Both run in the CI job `frame-rate`.

Only the two detections that compare positions at the end of a step needed sub-stepping, and both now test the whole step instead of
its end point (a swept test, `Aircraft.step_from`): **aircraft-aircraft conflicts** (the nearest approach of the two straight lines flown
during the step) and **storm / mountain crashes** (the distance from the hazard to the segment flown). With the old end-of-step tests a
pass just inside the conflict distance was missed 4 times in 60 at 30 fps. Everything else is already proportional to the step (path
following walks the path by distance, circling integrates an angle, timers and the landing roll subtract the step) and agreed to within
one step.

## The menu's background build (3 ms a frame)

`?perf` logs every menu frame over 33 ms in its first 20 s with what ran in it (`[menu-hitch] t=.. wall .. ms, our code .. ms:` the
airport build, `hud.show_menu`, the interface, the audio; also `window.__menu` for `tools/web_boot_check.js`, which prints the worst
ones). `?airports` opens every airport for the visit, so the background build has something to do.

The other airports are built in the background once the menu has been up 2 s (a shift or the pause menu pauses it). `Airfield._build_scene`
is a coroutine: `await _slice()` sits between its statements (about 38 000 of them for all six airports), and `_slice` hands the frame back
once 3 ms (`Airfield.budget_us`) of it is spent. The placement search that took 15-20 ms in one go (`_find_spots`' grid scan) works a
point at a time and keeps its result per airport and radius; the HUD rectangles are worked out once per view. `tools/build_profile.gd`
lists the slowest statements (natively); none is over 2.5 ms now except a few first-airport warm-ups.

Picking an airport that is not built yet (the airport card or the menu arrows) shows "Loading..." on its card, gives the build 9 ms of
each frame and goes there when it is done, instead of freezing.

Worst menu frames in the first 20 s under a 4x CPU slowdown with all six airports open (headless Chromium, software GL):

| | before (818df89) | after |
|---|---|---|
| frames with the build in them | 8+ frames of 177-394 ms of our code (each a whole build phase) | 3.1-3.6 ms typically; about 3 in 20 s at 110-150 ms |
| what the long ones are | a build phase (6-15 ms natively, ×25 in the browser) | one statement waiting on the software renderer: "ground", "runway" or "pad" (a mesh or texture upload; the same ~90-120 ms at 1x throttle, so not CPU), not the game's own code |
| first frame of the menu | 24 ms (`hud.show_menu` 14 ms) | the same |

A phone's GPU does not make the browser wait for a frame on an upload the way SwiftShader does, so the long ones should be shorter there.

## Opening a panel (180 ms, transform and opacity only)

Airports, Upgrades and the Hangar are laid out **before** they are tapped: `Main._prime_panels` (menu idle for 0.6 s) fills each panel's own
`Art` while it sits parked off screen (`Hud.PARK`; a hidden item is drawn again when shown, a parked one keeps what it drew), one panel a
frame. Opening one only moves the layer: `Hud._apply_transition` scales it 0.94 -> 1 (ease-out back) and fades it 0 -> 1 in
`Style.T_PANEL` (0.18 s); nothing inside is resized, laid out or redrawn. A panel is laid out again only when its data signature changed
(coins, stars, a purchase, safe area). The results card and the pause menu use the same pop; the pause sheet is no longer part of the
shift interface's redraw, and the first frame of a screen is drawn invisibly (`_tr_wait`) before it starts to move.

Glyphs: MSDF rendering was tried for both fonts (it needs no per-size glyphs) and measured: generating the ~300 glyphs of the three
faces added 7.7 s to the pre-warm at 4x (about 25 ms a glyph), which is the load time the game worked hard to lose, so the fonts stay
rasterised and the pre-warm draws every ASCII glyph at **every size the interface uses** (`Hud.begin_prewarm`: 16 display and 10 text
sizes, about 0.4 s at 4x). The characters that are not ASCII (the minus on the results chips, the middle dot, dashes) are in those rows
too: the first sight of the minus sign (a glyph Bowlby One SC does not carry, so it came from a fallback face) cost 20 ms in the results card.
The three panels' first draw is done in the pre-warm as well, behind the cover.

`tools/web_panel_check.js` (CI step "Panel open check") opens each panel in the exported build at 4x throttle, reads the game's own
frame cost from `window.__menu` and fails on any frame over 33 ms. Slowest frame of the game's own code while a panel opens, 4x, headless
Chromium on software GL:

| | before | after |
|---|---|---|
| Airports | 19.8 ms | 5-6 ms |
| Upgrades | 24.4 ms | 5-6 ms |
| Hangar | 16.4 ms | 8-9 ms |
| Pause (first open) | 20.1 ms | 7-11 ms |
| Results | not measured (first sight of the minus sign: 70+ ms) | 21-28 ms |
