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
- the fog layer's three shader parameters (every frame while visible) and the diorama clouds' opacity (every frame) -> only on change;
- the aircraft livery colours -> `Traffic._paint` (earlier).

No tween is created anywhere (there is no `create_tween` in the scripts), and the life props are few: 2 birds, a balloon, a mower, a fuel truck, a few vehicles and chairs per airport.
