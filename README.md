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
  then red). Circling burns it more slowly. When it runs out the aircraft is **diverted: a small fine**.
- **Two aircraft getting too close is a large fine and both are lost.** A warning ring grows around them first.
- **Every shift is timed** (100 seconds par, a countdown at the top). There is no instant game over. Arrivals stop
  at 85 s ("LAST ARRIVALS"), then it is **CLEAR THE SKY**: the shift ends only when every aircraft has landed or been
  lost (timers keep running). Clearing before par pays a bonus per second early; after par the clock turns red,
  counts up, and costs coins per second (both rates in Tuning, both shown on the results). The traffic ramp is
  scaled to the spawning window, so every shift builds to the same busy finish.
  Each landing pays coins (more for special aircraft; landings close together earn a quick-succession bonus).
  Fines come off the balance (conflict large, diversion small, terrain/storm medium); it can go negative
  during a shift. **Every shift pays something:** half of the landing pay is always kept (Tuning
  `landing_keep_fraction`), and fines and overtime only eat into what is above that. Stars use the net after fines.
  The results show landings earned, fines, the guaranteed share kept, and the total paid.
- New aircraft get a pulsing edge glow about 2 s before they appear (green slow, yellow medium, red fast).
- **Wind:** a windsock and a wind arrow show it. Aircraft can only land on runway ends facing roughly into the wind (those are bright; the others are dull with an X). The wind shifts during a shift with a banner ~8 s ahead ("Wind shifting to 270"); aircraft already cleared to an end that closes get a dashed red path and must be re-routed.
- **Six airports**, unlocked by total stars: Grass Strip (one runway, both directions), County (crossing
  runways: a landing on a crossing runway while the other is busy is a runway conflict), Regional (parallel
  runways + a helipad), Mountain Field (terrain no-fly zones: flying into a mountain is a fine), Island
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
  *storm cells* drift across the field (flying into one is a fine), *fog* ("FOG ROLLING IN") is atmospheric: drifting translucent
  waves dim the ground and scenery, while aircraft, paths, timers, banners and runways stay on top and fully readable;
  the mood is muted colors, a soft ambience and tenser music, and poor approaches go around slightly more often
  (never on Grass Strip or County); and a *gusty crosswind* closes one runway for
  a while (red X and a countdown; aircraft cleared to it are re-routed).
- **Shop** (cosmetics only): airport *themes* (Autumn, Desert, Winter, Night: palette and scenery) and airline
  *liveries* with an animal pilot (Fox Air, Owl Express, Penguin Pacific, Bear Cargo, Cat Airways). The pilot's
  portrait sits in the corner of the HUD, hops on each landing and appears on the results screen.
- **Daily Shift:** one seeded shift per day (same airport and arrivals for everyone that day) with bonus coins
  and a streak. It earns coins but no permanent stars.
- **Ads (stubs, no real ads yet):** a rewarded "undo the conflict and keep going" (once per shift), a rewarded
  "double coins" on the results screen, and an interstitial only between shifts, at most every third one. Each
  shows a fake "Ad playing" screen.
- Each airport has **three coin thresholds** that give the shift's stars. On the results screen
  there is one rewarded ad per shift: "refund your biggest fine" or "double coins". Stars, coins and bests are saved
  (save format v3).

- **Go-arounds are earned.** When an aircraft reaches short final its approach is scored: turning in the last
  stretch (a U-turn is worst), straight aligned final before the threshold (jets want more), the gap behind the
  previous landing on that runway, and the wind. A good approach practically never goes around; a poor one often
  does: the aircraft climbs out along the runway heading ("Go-around!" and the reason), keeps its timer and needs a
  new path. While you draw, the last stretch of the path is tinted green / yellow / red by the predicted go-around
  chance. Gliders and emergencies never go around (a glider that finds the runway busy is lost).

- **Student pilots** (an orange **L** badge) turn up now and then in normal shifts: they go around far more
  often, and pay double when they land.
- **Bad Pilot Day** is a second daily challenge on the menu (next to the Daily Shift): every aircraft is a student
  pilot, go-arounds are very likely and every landing pays big. It has its own airport, thresholds, best score and
  streak. Same seeded arrivals for everyone on the same day.

- **Pause** (top-left button, or automatically when the app loses focus) freezes the clock and all traffic and shows
  Resume, Restart Shift, Quit to Menu and sound / music volume sliders (saved; the audio buses are ready, there is
  no audio content yet).

- **Sound** is pre-rendered (`tools/render_audio.gd` bakes `scripts/SfxSynth.gd` into 44.1 kHz WAVs in `assets/audio/`; on the web the page plays the loops natively and suspends all audio when the page is hidden): a shared engine hum, landing chirp, coin, go-around roar,
  conflict alarm, fine, wind-shift chime, last-arrivals / clear-the-sky stingers, overtime tick, UI taps, and a
  two-layer music loop that intensifies towards the finale. It plays through the SFX / Music buses that the pause
  menu sliders control. `?nofx=sound` turns it off.

## Airport difficulty

Every airport has a difficulty profile in `Tuning.airport_profiles` (peak aircraft on the field, arrival pace and
how fast it ramps, aircraft speed, timers, special aircraft, weather and wind-shift frequency, fine size, star
thresholds, and the "beats" that introduce a new mechanic alone and early). Grass Strip is very relaxed (3 aircraft
at most, slow aircraft, long timers, no weather, no wind shifts); County adds a second runway and gentle wind shifts;
difficulty then steps up to today's full intensity at Mountain Field and beyond it at International. The first shift
at an airport is gentler still (arrivals further apart, longer timers).

## Screens

Every screen has one primary element (big and high-contrast), the rest smaller and quieter, icons instead of words,
three text sizes (XL / M / S), one banner and one tip at a time, and numbers that roll up. `tools/screenshots.gd`
renders them all (`xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1080x1920 --script
tools/screenshots.gd -- out=DIR`); the before / after images from the clarity pass are in `docs/screens/`.

## Economy simulation

`tools/economy_sim.gd` plays the real game with poor / average / good autopilots for their first 20 shifts and prints
coins per shift, stars and when each upgrade becomes affordable (`godot --headless --path . --script
tools/economy_sim.gd`, optional `-- shifts=5 modes=saving`). With `-- survey per=8` every bot plays every airport and it
prints stars per airport. The last full run is in `tools/economy_sim_results.txt`.

## Debug / tuning URLs

| Flag | What it does |
| --- | --- |
| `?perf` | worst-frame-time readout, hitch log (frames over 50 ms), sim vs wall clock |
| `?tune` | TUNE button (top right): live sliders for spawn rate, speeds, conflict distance, aircraft timers, wind, weather...; **Copy values** puts the changed values on the clipboard, **Reset** restores defaults; debug buttons: +1000 coins, unlock all airports, max upgrades, force a wind shift, trigger a storm / fog / crosswind, reset save, reset daily |
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


## Look and feel

`docs/style.md` is the style guide (palette, type, radii, shadows, buttons, icons, spacing, safe areas, motion, audio);
`scripts/Style.gd` holds the same tokens in code. Before / after pictures of every screen: `docs/screens/makeover_before`
and `docs/screens/makeover_after`, with the pictures taken after each makeover phase in `docs/screens/makeover_phase1..3`.
Shift lengths differ by airport (45 / 60 / 75 / 75 / 90 / 90 s of arrivals, par 15 s later).

## Credits

*Pattern Work* is made by **Clear Prop Games**. Fonts: Fredoka and Nunito (SIL Open Font License, see `assets/fonts/`).

## Loading page and build stamp

The web build uses a custom loading page (`web/shell.html`): the brand background, the Clear Prop Games mark and a progress bar.
The build stamp (commit and time) is hidden from players; add `?debug` (or `?tune` / `?perf`) to the URL to show it.
