# Pattern Work

Working title. A portrait, top-down air traffic game: two runways, planes coming in from every
edge, and you drawing each one home before they meet.

**Play:** https://hotshotted.github.io/Pattern-Control/

## How to play

- **Drag from a plane** to draw its flight path; it follows the line as you draw. Each plane is
  coloured like one of the two runways. End the path on that runway's **approach end** (the ring
  with the arrows) and the plane lands - score is planes landed.
- **Tap a plane** to make it circle in place (a holding pattern); tap it again to let it go.
- **Flashing planes are low on fuel** and show a countdown: land them in time or the run ends.
- **Two planes getting too close ends the run.** A warning ring grows around them first.
- Planes fly at different speeds (slow props, medium, fast jets), and traffic ramps up the longer you last.

## Debug / tuning URLs

| Flag | What it does |
| --- | --- |
| `?perf` | worst-frame-time readout, hitch log (frames over 50 ms), sim vs wall clock |
| `?tune` | TUNE button (top right): live sliders for spawn rate, speeds, conflict distance, fuel timers...; **Copy values** puts the changed values on the clipboard, **Reset** restores defaults |
| `?nofx=burst,ripple,popup,haptic,glow,hold` | switch effects off (`all` for every one) |
| `?noprewarm` | skip the start-up pre-warm splash |
| `?god` | planes never collide or run dry |

Flags combine with `&`, e.g. `?perf&tune`. Every feel value lives in `scripts/Tuning.gd`.

## Project notes

Godot 4.5, Compatibility renderer, portrait 1080x1920, web export to GitHub Pages
(`.github/workflows/deploy.yml`: build stamp in the corner, cache-busted file names, headless smoke
test before every export). Same conventions as sky-dodge: everything is pooled and pre-warmed behind a
splash at boot, nothing is allocated during a run, and restarting is in place.

Run the smoke test locally: `godot --headless --path . --script res://tests/smoke_test.gd`
