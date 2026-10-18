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
- **Wind:** a windsock and a wind arrow show it. Aircraft can only land on runway ends facing roughly into the wind (those are bright; the others are dull with an X). The wind shifts during a shift with a banner ~8 s ahead ("Wind shifting to 270"); aircraft already cleared to an end that closes get a dashed red path and must be re-routed.
- **Six airports**, unlocked by total stars: Grass Strip (one runway, both directions), County (crossing
  runways: a landing on a crossing runway while the other is busy is a runway conflict), Regional (parallel
  runways + a helipad), Mountain Field (terrain no-fly zones: flying into a mountain is a strike), Island
  (water and a seaplane lane) and International (three long runways, two helipads, two lanes). A second
  aircraft reaching a runway that is still busy goes around.
- **Special aircraft** (each shows a one-line tip the first time it appears): **helicopters** land on the
  helipad only and hover when tapped; **gliders** can't hold and only get their first path, with the shortest
  timer; **jets** are fast and need a long runway; **seaplanes** land on the water lane; **emergencies**
  (flashing, SOS) have a short timer, may use any suitable runway and pay a big bonus; **VIP flights** pay
  bonus coins, unless you put them in a holding pattern.
- **Upgrades** (bought with coins, three levels each, and visible on the airport): *Radar* (wider view, earlier
  arrival warnings), *Approach Control* (arrivals line up with the active runways), *Tower Staff* (slower,
  thinner traffic), *Better Comms* (longer timers), *Holding Fixes* (holding burns timers slower, tighter
  circles), *Fast Turnoffs* (runways clear faster).
- **Weather** (later airports, later in a shift; each event is announced ~6 s ahead with a banner):
  *storm cells* drift across the field (flying into one is a strike), *fog* hides aircraft until they get
  close to the field (the Radar upgrade sees further into it), and a *gusty crosswind* closes one runway for
  a while (red X and a countdown; aircraft cleared to it are re-routed).
- **Shop** (cosmetics only): airport *themes* (Autumn, Desert, Winter, Night: palette and scenery) and airline
  *liveries* with an animal pilot (Fox Air, Owl Express, Penguin Pacific, Bear Cargo, Cat Airways). The pilot's
  portrait sits in the corner of the HUD, hops on each landing and appears on the results screen.
- **Daily Shift:** one seeded shift per day (same airport and arrivals for everyone that day) with bonus coins
  and a streak. It earns coins but no permanent stars.
- **Ads (stubs, no real ads yet):** a rewarded "undo the conflict and keep going" (once per shift), a rewarded
  "double coins" on the results screen, and an interstitial only between shifts, at most every third one. Each
  shows a fake "Ad playing" screen.
- Each shift has **three star goals** (land 25 aircraft, land 4 jets, finish with no strikes). Landings and
  stars earn **coins**. Stars, coins and bests are saved.

## Debug / tuning URLs

| Flag | What it does |
| --- | --- |
| `?perf` | worst-frame-time readout, hitch log (frames over 50 ms), sim vs wall clock |
| `?tune` | TUNE button (top right): live sliders for spawn rate, speeds, conflict distance, fuel timers...; **Copy values** puts the changed values on the clipboard, **Reset** restores defaults; debug buttons: +1000 coins, unlock all airports, max upgrades, force a wind shift, trigger a storm / fog / crosswind, reset save, reset daily |
| `?nofx=burst,ripple,popup,haptic,glow,hold` | switch effects off (`all` for every one) |
| `?noprewarm` | skip the start-up pre-warm splash |
| `?god` | aircraft never collide or run out of time |

New planes get a pulsing edge glow (green slow, yellow medium, red fast; faster planes pulse faster) about 2 s before they appear.

Flags combine with `&`, e.g. `?perf&tune`. Every feel value lives in `scripts/Tuning.gd`.

## Project notes

Godot 4.5, Compatibility renderer, portrait 1080x1920, web export to GitHub Pages
(`.github/workflows/deploy.yml`: build stamp in the corner, cache-busted file names, headless smoke
test before every export). Same conventions as sky-dodge: everything is pooled and pre-warmed behind a
splash at boot, nothing is allocated during a run, and restarting is in place.

Run the smoke test locally: `godot --headless --path . --script res://tests/smoke_test.gd`
