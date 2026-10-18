# Pattern Work

Working title. A portrait, top-down air traffic game: two runways, planes coming in from every
edge, and you drawing each one home before they meet.

**Play:** https://hotshotted.github.io/Pattern-Control/

## How to play

You run an airport, one **shift** at a time.

- **Drag from an aircraft** to draw its flight path; it follows the line as you draw. Each aircraft is
  coloured like one of the runways. End the path on that runway's **approach end** (the ring with the
  arrows) and it lands.
- **Tap an aircraft** to make it circle in place (a holding pattern); tap again to let it go.
- Every aircraft has a **timer ring** that runs down from the moment it is on screen (green, then yellow,
  then red). Circling burns it more slowly. When it runs out the aircraft is **diverted: a strike**.
  **3 strikes end the shift.**
- **Two aircraft getting too close ends the shift immediately.** A warning ring grows around them first.
- New aircraft get a pulsing edge glow about 2 s before they appear (green slow, yellow medium, red fast).
- Each shift has **three star goals** (land 25 aircraft, land 4 jets, finish with no strikes). Landings and
  stars earn **coins**. Stars, coins and bests are saved.

## Debug / tuning URLs

| Flag | What it does |
| --- | --- |
| `?perf` | worst-frame-time readout, hitch log (frames over 50 ms), sim vs wall clock |
| `?tune` | TUNE button (top right): live sliders for spawn rate, speeds, conflict distance, fuel timers...; **Copy values** puts the changed values on the clipboard, **Reset** restores defaults |
| `?nofx=burst,ripple,popup,haptic,glow,hold` | switch effects off (`all` for every one) |
| `?noprewarm` | skip the start-up pre-warm splash |
| `?god` | planes never collide or run dry |

New planes get a pulsing edge glow (green slow, yellow medium, red fast; faster planes pulse faster) about 2 s before they appear.

Flags combine with `&`, e.g. `?perf&tune`. Every feel value lives in `scripts/Tuning.gd`.

## Project notes

Godot 4.5, Compatibility renderer, portrait 1080x1920, web export to GitHub Pages
(`.github/workflows/deploy.yml`: build stamp in the corner, cache-busted file names, headless smoke
test before every export). Same conventions as sky-dodge: everything is pooled and pre-warmed behind a
splash at boot, nothing is allocated during a run, and restarting is in place.

Run the smoke test locally: `godot --headless --path . --script res://tests/smoke_test.gd`
