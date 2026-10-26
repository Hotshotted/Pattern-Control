# Pattern Work: style guide

One identity for every screen: **warm, soft, chunky and lived-in** ("Cozy Airfield"). Cream surfaces float over a sunlit airfield;
orange is the one thing to press, gold means money and stars, green means go, red means trouble. Everything below lives in code
in `scripts/Style.gd` (the tokens) and `scripts/Hud.gd` (the drawing). Change the token, not the call site.

## Palette

| Role | Token | Hex | Use |
|---|---|---|---|
| Primary | `PRIMARY` | `#4c8fd6` | blue: selection, info (runway 2) |
| Primary dark | `PRIMARY_DARK` | `#2f6aa8` | pressed / edge of blue elements |
| Accent | `ACCENT` | `#f2b233` | the coin and the stars, rewards |
| Accent dark | `ACCENT_DARK` | `#b87a14` | the coin's rim, edges of gold elements |
| Success | `SUCCESS` | `#35c98a` | go, earned, the green timer ring |
| Success dark | `SUCCESS_DARK` | `#1a8a5a` | earned text on cream |
| Warning | `WARNING` | `#f0803c` | orange: streaks, notices, runway 1, the primary button |
| Danger | `DANGER` | `#ea4a3c` | fines, conflicts, overtime, last 15 s |
| Danger dark | `DANGER_DARK` | `#a8302a` | edges of red elements |
| Ink | `INK` | `#3a2410` | outlines (a warm brown, never black) |
| Surface dark | `SURFACE_DARK` | `#f6e8cf` | cream: cards, sheets, pills (the lower end of their gradient) |
| Surface dark 2 | `SURFACE_DARK_2` | `#ebd9b6` | raised or selected cream, chips |
| Surface light | `SURFACE_LIGHT` | `#fff8ea` | cream, the top end of the gradient |
| Surface light 2 | `SURFACE_LIGHT_2` | `#f6e8cf` | cream cards, dividers |
| Text | `TEXT` | `#5a3a12` | text on cream |
| Text soft | `TEXT_SOFT` | `#7a5a2c` | secondary text on cream |
| Text quiet | `TEXT_QUIET` | `#a88c5e` | tertiary / disabled text |
| Text on light | `TEXT_ON_LIGHT` | `#5a3a12` | text on the lightest cream |
| Scrim | `SCRIM` | `#2b1b0a` | the warm shade behind a screen or sheet |

Also `EDGE` `#c9a46e` (the solid 4 px bottom edge of every cream surface), `ORANGE_TOP` `#ff9d4f` / `ORANGE` `#f0803c` /
`ORANGE_EDGE` `#b85a1b` (the primary button), `WORLD_TEXT` `#fff4df` (display text over the field) and the extrusion
`EXT_TOP` `#c9641f` to `EXT_BOTTOM` `#803d11`. Gold text on cream is darkened to `#8a5a05` (`Hud.C_GOLD_TXT`).

Contrast: `TEXT` and `TEXT_SOFT` on `SURFACE_DARK`, gold text on cream (`#8a5a05`), and `TEXT_ON_LIGHT` on `SURFACE_LIGHT` are all
at least 4.5:1 (checked by the smoke test). Display text over the game world is cream on a warm extrusion, which reads on any
ground. Colour is never the only signal: fines and overtime also use a minus sign / a plus sign, stars use a shape.

## Cozy Airfield (the art direction)

A top-down, warm, soft and lived-in toy diorama: the camera looks straight down at a sunlit field with a little life on it. Same
game, same layouts and the same readability rules as ever; the mood comes from the light first, then from shaded surfaces, soft
shadows and small moving things. This section describes what is in the build (it replaces the earlier "Sunny Airfield" look and the
two polish passes); every number below is in the code or in `Tuning.gd`, and the other repos can copy it as written.

| Part | Where |
|---|---|
| Light overlay, time of day | `scripts/LightOverlay.gd`, `shaders/light_overlay.gdshader` |
| Shading baked into vertex colours | `scripts/Prim.gd` |
| Soft shadows (baked textures, offsets that grow) | `scripts/Shadow.gd`, `shaders/shadow_blob.gdshader` |
| The field, runways, ramp, landmarks, life, wind layer | `scripts/Airfield.gd`, `scripts/Models.gd` |
| Airport layouts and their aprons | `scripts/Airports.gd` |
| Hangar, ramp and taxi routes | `scripts/Ramp.gd` (pure logic), `Airfield.begin_taxi / step_taxi` |
| Paths, snapping, halo | `scripts/Traffic.gd`, `scripts/PathRibbons.gd` |
| Interface | `scripts/Hud.gd`, `scripts/Style.gd`, `scripts/ExtLabel.gd` |

### Light, shading and shadows

* **One light overlay** (a ColorRect with `light_overlay.gdshader`, layer 0) sits over the whole field, above the 3D scene and below
  the paths, rings and interface: a warm radial glow `#FFD68A` pinned to the upper-left corner, a cool radial shade `#2F4A7A` pinned to
  the lower-right (both fade to nothing by 90 % of the screen diagonal; the glow is added, the shade mixed over). **No grain, no texture
  over the screen**: the shader is plain arithmetic in units of the screen width (no value above about 2), so it is exact in a phone's
  half-precision fragment shaders. `?nolight` switches it off.
* **The grass has a very faint static texture** (the only texture on the field): `assets/textures/grass.png`, a tileable blotchy noise
  that darkens the colour by 0-2.5 % (4 world units to a repeat), on the ground mesh of the grass airports only: not the runways,
  taxiways, aprons or buildings (separate meshes), not the water. It is baked (`tools/bake_textures.gd`), never animated, and nothing
  of it is drawn over the screen.
* **Time passes over the shift, linearly:** the glow goes 35 % to 50 % and the shade 20 % to 30 %; every shadow offset grows to 130 %;
  the grass gets a touch warmer (blue down 9 %, green down 2 %). A restart resets it; Bad Pilot Day starts 40 % in.
  (`Main._set_day`, `LightOverlay.set_time`, `Airfield.set_time`, `Shadow.set_time`.)
* Surfaces are softly shaded, not flat: every roof, wing, tree and tank runs from lighter at its upper-left to darker at its
  lower-right, about 18 % in value, baked into vertex colours at build time (no per-frame cost; ratios stay at or under 1 because vertex
  colours clamp). The field is a gradient mesh from `#B9DC72` (upper-left) through `#8FC45C` to `#76AA4B`. **No outlines on the ground**;
  aircraft keep a thin, soft slate edge only.
* **Shadows** are blue-grey `#3B4A6B` at 26 %, soft-edged, the softness baked into small textures once; cast toward the lower-right; a
  building's shadow is half as long as the building is high. A flying plane's shadow slides away as it climbs and fades a little. Each
  shadow quad that has an offset from its caster is registered (`Shadow.register`) so the offsets can grow with the shift.

### Palettes (one per airport style)

| | Countryside (default) | Coastal (Island) | Alpine (Mountain Field) |
|---|---|---|---|
| Ground | `#B9DC72` gradient; water for the island | sand rim, blue sea | `#8FC45C` with snow patches |
| Hangar roof | `#E2654A` | `#3F8FC2` | `#6B4A3A` |
| FBO roof | `#4FB8B2` | `#EAA64A` | `#9A3B2E` |
| Walls | `#E8E1D2` / `#EFE6D3` | `#F7F4EA` / `#FBF8EE` | `#B98757` / `#C7955F` |
| Apron | `#B6BBC2` | `#D2CAB6` | `#9AA0A8` |
| Landmark | red barn and white silo, a pond | lighthouse (its lamp pulses) and a pier with gulls | timber lodge with drifting chimney smoke, pines, a chairlift with two moving chairs |
| Birds | dark | white gulls | dark |

Shared: runway asphalt `#6A7079` to `#565B66`, markings cream `#F2EDE4` at 90 % (numbers 80 %), rubber streaks 20 % black, taxiway `#A3A8B0`
with yellow `#E6C35A` dashes; accents orange `#F0803C` (runway 1, the primary button), blue `#4C8FD6` (runway 2), violet `#8E6BBE`
(helipad), teal `#2BA3A6` (seaplane lane). Airframes are white with the livery on the nose, wingtips and fin. Trees: round canopies
(`#9AD46E` to `#3F7D3F`), pines in the mountains, each with a soft shadow. The tower is cream `#FFF2DC` with a navy cab and a red beacon.
Buildings have a 4 px darker side on the right and bottom.

### The ground kit and the life

The ramp (an apron slab with the tower, hangar, FBO, picnic table and dog, car park, oil stains, painted tie-downs, a fenced fuel farm with a
fuel truck that drives to the ramp and back, a glider on a trailer), PAPI lights, runway lights, two birds, a mower leaving stripes and a
hot-air balloon. Everything is built once at start-up and pooled; `?nolife` stops the moving parts (and stills the sock, the
beacons and the lights, which `?windtest` also does).

**Placement rule (checked at every airport).** Nothing built, planted or parked may stand in something the player's eye follows:
`Airfield.in_strip(p, r)` is true inside a runway and its lights (half width + 0.55), inside the approach funnel drawn behind each end
(it widens from half width + 0.65 at the threshold to + 2.05 at 3.4 behind it, 3.6 long), inside a water lane's or a helipad's
approach (1.0 / 0.9 beyond it), and **under the interface**: `Airfield.in_hud` is the footprint of the pause button, the timer / coins
pill with its star bar, the wind card and the wind-shift banner (just under the star bar, the widest it gets), each with a 12 px margin,
taken from the 1080 x 1920 layout at the closest view (a radar upgrade only shrinks it). Always with the object's own radius `r` added.
Landmarks, props, trees, tufts, pines, the pond, the chairlift, parked planes, overflow spots and upgrade props are placed with it (an
upgrade prop may stand under the interface only where the field has no other room), and so are the aprons and windsocks in `Airports.gd`.
Lane ends, threshold rings and helipads must not be under the interface at any airport, **an approach funnel is drawn only as far as it
stays clear of it** (`Airfield.funnel_length`, 1.4 to 3.4 behind its threshold, so a tall layout shows fewer chevrons at its north ends),
and **no arrival spawns under it** (`Traffic.spawn` skips an entry point under the pause button, the pill or the wind card). The
County, Mountain Field and Island aprons were moved for the strips; the International's layout was redrawn (the three runways stay,
the helipads, a shorter seaplane lane and its full-size apron with terminal and six tie-downs sit in the right-hand column between the
banner and the horizontal lane). The smoke test walks every placed thing at every airport (`airport=<name|index>` limits it), checks the
funnels, rings, lane ends and 250 spawns per airport against the interface, and the screenshot tool takes the same argument.

### Aircraft on the ground: taxi, hangar and ramp

* A landing ends in a puff of dust and a soft in-key tyre chirp (E5 to G5, on the next eighth of the music, far under it). The plane
  rolls out, leaves the runway past its far end and **taxis at 1.05 units/s along a fixed route** to its place: the shortest route that keeps
  0.5 clear of every runway box (`Ramp.route`, a small visibility graph around the runways), so it never crosses one. Taxiing aircraft
  are scenery: no collisions, drawn on the ground under the paths and the flying traffic. At most **four** taxi at their own pace; older
  ones hurry at 9x.
* **It is the aircraft that landed:** the ramp uses 24 extra complete models of the traffic pool (`Traffic.ramp_claim / ramp_configure`),
  dressed from the one that landed: its type and speed class, its runway's livery colour, the airline livery's body and stripe (the nose, wingtips and fin always keep the runway's colour), the
  student badge. It shrinks from the size it had on the runway (0.9) to the parked size (0.42 x the apron's scale) over its first
  3 units, and a parked one shows wheel chocks.
* **Where it goes** (`Ramp.place`). **Every landing counts toward the hangar**, wherever the aircraft parks: the hangar holds the
  **break-even landing count**, the airport's one-star threshold divided by the average landing pay across all its traffic types, rounded
  up (Regional 4, Mountain Field 5, Island 7), so "Hangar full" happens exactly when the shift breaks even. A helicopter sits on its pad
  for 3 s, then air-taxis to a marked heli spot (airports with a pad) and a seaplane taxis to the island's dock, but both still take one
  of the hangar's places and bump its "N / cap" (and the results line); the rest go into the hangar itself. The landings after it is full
  are "on the ramp": the next free tie-down on the apron (six, in two rows, the second on an extension of the slab to the south or the
  west), then up to six overflow spots on the grass along the taxiway, then a "+N" tag by the apron (a helicopter or seaplane still uses
  its spot or dock first).
  Crashes park nothing and keep the coin penalty. The results card says "Hangar full · 9 on the ramp" or "Hangar 5 / 8".
* Everything that can park is built once and hidden; a shift restart clears it in place.

### The wind layer

Twelve thin cream streaks (60 to 120 px long, about 10 % opacity) drift across the field the way the air is going, at 20 to 60 px/s by
the wind's strength, above the ground props and below the paths (a pooled MultiMesh; each streak fades in and out and is reborn
elsewhere). The grass tufts lean downwind, the trees rock about a lean, the pond ripples (three pooled rings drifting downwind) and the
windsock points downwind. **When the wind shifts** the streaks swing round over about 1.2 s and briefly double in brightness, the trees
sway three times harder for a second and a soft gust (low filtered air, on the beat of the music) plays; the wind card's arrow turns
smoothly. `?nowind` switches all of this off. `?windtest` (CI only) hides the interface, clears the field of aircraft and stills
everything but the wind; `tools/web_wind_check.js` loads the real web export twice and compares two frames a moment apart: about a
thousand pixels move with the wind, none without it.

### Paths, snapping and the go-around warning

* **Path feel:** while drawing, the path follows the average of the finger's last four points. A finger within 0.45 of an open runway end's
  extended centreline, between 0.5 and 3.6 behind its threshold and heading for it, snaps onto the centreline and locks (a soft click, a
  pulse ring at the lock point, a short buzz: `navigator.vibrate` on the web, `Input.vibrate_handheld` elsewhere). Tapping a plane clears
  its path, which fades out over 0.25 s.
* **Path halo:** the coloured dots sit on a cream `#FFF4DF` halo at 55 %. The earlier dark halo is behind a `?tune` toggle
  (`path_halo_dark`) for comparison.
* **Go-around warning:** a go-around is signalled 1.0 s before it happens (`go_around_telegraph`, in `?tune`): the plane wobbles (4 degrees
  of roll), a "?" tag shows and its engine note rises (a soft glide in the key). Redrawing a final whose go-around chance is under 60 %
  of the one it was rolled at inside that second cancels it (so does holding the plane); otherwise the tag becomes "GOING AROUND" and the
  climb-out proceeds. After every shift the console gets `[go-around] warnings: N, cancelled by the player: M (cancel rate X%, window 1.0 s)`
  and the results details list it; the economy sim logs the bots' rate.

### Juice

Coins leave the wheels at touchdown and arc to the counter one after the other; each plinks (climbing the scale) and bumps the counter
on arrival. Buttons squash to 94 % while pressed and spring back. A timer ring pulses once as it turns red. Score pops tilt a few degrees
at random. Aircraft have no engine hum: gameplay sounds are on the music's grid (see Audio).

### Interface

Cream surfaces (gradient `#FFF8EA` to `#F6E8CF`, a solid 4 px bottom edge `#C9A46E`, a soft drop shadow, text `#5A3A12`), pills fully
rounded, cards 22 px radius. The primary button is orange (`#FF9D4F` to `#F0803C`, a 7 px bottom edge `#B85A1B`, an inset top highlight,
white text with a slight dark shadow); pressing it drops it onto its edge. The display face is **Bowlby One SC** (title, timer, score,
headers) in cream `#FFF4DF` with a stacked warm extrusion (`#C9641F` to `#803D11`) and a soft shadow; the title sits at a 2 degree tilt.
Body and labels are **Rubik** 800 and 500. The coin is a real gold coin (`#F2B233`, darker rim, a propeller mark); stars are gold with a
dark outline, empty stars cream. HUD positions never move.

### Flags, tuning and what guards it

| Flag | Effect |
|---|---|
| `?nolight` | no light overlay |
| `?nolife` | no moving scenery (truck, birds, balloon, mower, vehicles, sock sway, beacons) |
| `?nowind` | no visible wind (streaks, leaning grass, swaying trees, pond ripples) |
| `?windtest` | CI: no interface, no aircraft, a still field but for the wind |
| `?tune` | live sliders: snap radius / reach, smoothing, path fade, path halo toggle, go-around warning and cancel factor, plus every other feel value |

The smoke test (`tests/smoke_test.gd`) covers the light and its time of day, the placement rule at every airport, the hangar
capacity and ramp counts, taxi routes that never cross a runway, taxi identity, snapping, smoothing, the wind layer, the go-around warning
and its cancel, the halo and the juice. CI also loads the exported game in headless Chrome twice: the web audio check (sound under CPU
throttling, background audio held) and the wind motion check. Screenshots per airport: `xvfb-run -a godot --path . --rendering-driver
opengl3 --script tools/screenshots.gd -- out=DIR only=cozy prefix=NAME airport=countryside,island,mountain` writes the menu, a mid-shift,
the airports list and the results for each (`docs/screens/cozy_airport_*`).

## Typography

Both fonts are open-licence (SIL OFL 1.1; licence files `OFL-BowlbyOneSC.txt` and `OFL-Rubik.txt` in `assets/fonts/`), from the
google/fonts repository.

* **Display: Bowlby One SC**, heavy and friendly small caps. The title, the timer, the score, every number and the screen headers
  and card names. Over the field it is cream (`#FFF4DF`) on a stacked warm extrusion (`#C9641F` to `#803D11`) with a soft shadow
  (`Style.draw_ext`, `ExtLabel`); on a cream card it is brown. The title "PATTERN WORK" sits at a 2 degree tilt.
* **Labels: Rubik 800** (ExtraBold) and **descriptions: Rubik 500** (Medium).
* Three sizes: **XL 110** (the one primary thing), **M 56** (card titles, banners), **S 30** (secondary); long labels shrink to fit.
* Text on cream is `#5A3A12` with no outline; text over the game view is cream with the extrusion or an ink outline.
* Labels are at most about four words; a description is one short line.

## Shape

* Corner radii: **S 14** (inner highlights), **M 22** (cards, chips), **L 40** (primary button, sheets), **pill** fully rounded (banners, tips, the corner totals).
* Cream surfaces: a gradient `#FFF8EA` (top) to `#F6E8CF` (bottom), a solid **4 px bottom edge** `#C9A46E`, no outline.
* **Shadow:** soft, offset down: a warm brown at 30 %, blur 16 px, offset (0, 8). Every raised panel has it; flat things do not.
* **Chunky edge:** the primary button sits on a 7 px edge `#B85A1B`; pressing drops the button onto it.

## Buttons

| Style | Look | Used for |
|---|---|---|
| Primary | big, orange gradient `#FF9D4F` to `#F0803C`, white display text with a slight dark shadow, a 7 px edge, an inset top highlight | Start shift, Next shift, Resume: one per screen |
| Secondary | cream, a 4 px bottom edge, soft shadow | Airports, Bad pilot day, cards, list rows, chips |
| Round | a small cream circle with a brown icon and a label under it | Upgrades, Hangar, Daily, back, home, pause |

States: **normal**, **pressed** (cream drops 4 px; the primary drops onto its edge), **disabled** (flat, greyed, no shadow; taps
are swallowed, not passed to the game), **selected** (an orange ring; a maxed upgrade is gold).

### Only what you can tap looks tappable

**Only things you can tap get a bottom edge and a shadow.** Everything that only shows something is flat: no bottom edge, no
drop shadow, no pill around plain text.

- Tappable: buttons, cards (airport, upgrade, hangar rows), tabs, the round icon buttons, the airport name under the menu title
  (it opens the Airports screen), the ad chips, the pause button. These use `_cream` (a 4 px #C9A46E bottom edge and the warm shadow).
- Flat (`Art._flat`, or a ring with no shadow): the coin and star counters, the status pills under the star bar, the banner and tip,
  the wind card, the results chips and unlock card, the title's small print ("AIR TRAFFIC CONTROL", "CLEAR PROP GAMES": tracked
  capitals in muted cream at 70%, no shape at all).
- Surfaces that hold things (the pause sheet, the results card, Details) have the soft shadow but no bottom edge.

### The shop's preview sheet

Tapping a livery or an airport skin opens a sheet over the shop (the list stays behind it): the name, a picture (a livery: the plane
turning and banking, and a small one in the game's top-down view with the runway's colour on nose, wingtips and fin; a skin: the airport's
vignette, the current look and the new one with a Current / New toggle), the price with the coin icon, and the balance before and after
("2,480 \u2192 1,980"). Nothing is bought anywhere else. The button reads "Buy for N" and is **held** for `Tuning.buy_hold_seconds`
(0.6 s) while an orange fill runs across it; a tap only says "Hold to buy". Too poor: grey, "Need N more", never spends. After the
purchase a burst and a check, then a single "Equip" (owned things show "Equip" or "Equipped" instead of a price).

## Icons

One vector set drawn in code (`Hud.Art.glyph`): bold filled silhouettes and thick strokes, round proportions, no text and
no emoji. Two-tone only where the colour is the meaning (coin gold, star gold, danger red, sun yellow). Stats and
buttons always use the same icon: coin, star, clock, plane, wind, storm, fog, crosswind, radar, tower, comms, holding,
turnoffs, approach, lock, check, play, pause, restart, home, back, speaker, note, shop, daily, bad day, ad. Icons sit in a
box of radius r; strokes are r / 6 (at least 3 px).

## Spacing

Scale: 8, 16, 24, 40, 64. Screen gutter 40. Cards are 160-170 tall with 10 gap. The primary button is at least 230 tall.
One primary element per screen; secondary things are smaller and quieter; the rest is behind a "Details" tap.

## Safe areas

`Style.safe_top / bottom / left / right` (viewport pixels) come from the device (`DisplayServer.get_display_safe_area`) or,
in the browser, from the page's `env(safe-area-inset-*)`. Everything pinned to an edge (pause button, coin total, clock,
star bar, wind dial, back buttons, headers, tips) adds the inset. Backgrounds and the world still run edge to edge.

## Motion

| Token | Seconds | Used for |
|---|---|---|
| `T_FAST` | 0.12 | press and release |
| `T_BASE` | 0.30 | screen transitions, panels in |
| `T_SLOW` | 0.50 | celebrations, stars |
| `STAGGER` | 0.05 | between cards animating in |

Easing: **ease-out-cubic** for things arriving, **ease-in-cubic** for things leaving, **ease-out-back** (overshoot 1.70) for
popups, stars and anything that should feel like it landed. Forward navigation slides in from the right and fades;
back slides from the left. Nothing moves slower than 0.5 s unless it is a celebration, and every animation can be skipped.

## Audio

**Direction: soft, satisfying and musical, in the spirit of Mini Metro and Alto's Adventure: calm, rounded, cozy.** Every
game from this studio should sound like it belongs to the same room.

* **Waveforms:** sines (with a touch of triangle for the muted "bonk") and gently filtered noise. No square, no saw, no
  harsh noise. Everything is low-passed so there is almost no energy above 4 kHz.
* **Envelopes:** every sound has a proper envelope: a soft raised-cosine attack (4-12 ms for UI, up to 0.25 s for pads), a
  natural exponential decay, and a smooth release. Nothing starts or stops hard; there are no clicks.
* **Space:** a short shared "room" (four damped combs) is baked into every chime, plink and fanfare, and into the music's
  arpeggio, so sounds sit in the same space instead of floating on top.
* **One key:** D major pentatonic (D E F# A B), the key of the music (chords D, A, Bm, G). All pitched sounds are drawn from it
  (`Sfx.note_hz(degree)`), so anything that overlaps harmonises. The music is never pitch-shifted, because that would leave
  the key.
* **Variation:** every repeated sound gets about +-3% random pitch and a hair of random level, so it never feels robotic.
* **Rendering:** nothing is synthesised on the phone. `scripts/SfxSynth.gd` is the recipe and `tools/render_audio.gd`
  bakes it into 44.1 kHz 16-bit mono WAVs in `assets/audio/` (one-shots) and `assets/audio/loops/` (calm, hot, tense and fog), which are committed (re-run `godot --headless --path . --script tools/render_audio.gd`
  after editing the recipe; the smoke test fails if they differ). One-shots play from a pool of 8 `AudioStreamPlayer`s.
  No buses are created at run time (that silences the single-threaded web export): the `SFX`, `Music` and `Ambience` buses and the
  Master **limiter** (a hard limiter, ceiling -1 dB) come from `default_bus_layout.tres`.
* **Loops on the web:** Godot's web samples loop by restarting a buffer from the main thread, which leaves a gap at every
  wrap when a phone is busy. So the page (`PWAudio` in `web/shell.html`) plays the loops itself as native
  `AudioBufferSource` loops (gapless, off the main thread, phase-locked, through a compressor-limiter); the game only
  sends each layer's level. The loops ship beside the page, not in the pck. Loop waveforms are smooth sums of sines with no
  jumps, and CI records the output in headless Chrome under CPU throttling and fails on discontinuities, repeated
  buffers, dropouts or clipping (`tools/web_audio_check.js`).
* **Background audio:** when the page is hidden, the phone is locked or the tab loses focus (`visibilitychange`,
  `pagehide`, `blur`) every `AudioContext` is suspended by the page (this works even before the game has loaded), and the
  game mutes the Master bus and pauses on Godot's focus-out. Sound stays off when the page comes back until the player taps
  Resume. CI toggles page visibility and checks the output goes silent.

**The sounds**

| Moment | Sound |
|---|---|
| Touchdown | a very soft, low-passed tap, far below the chime (no tire squeal) |
| Arrival | a very soft, short tone (G4), on the beat |
| Landing | ONE soft bell chime in the key, on the next eighth-note of the music; landings in quick succession climb the scale (seven steps) and are each quieter (velocity: about 2 dB less per landing in the last 3 s, down to 9 dB) |
| Coin | a tiny bell plink well under the chime, one note higher for each coin that reaches the counter |
| Conflict | a low muted thud with a soft descending two-tone (A3 to E3); fines are the thud alone |
| Go-around | two soft rising tones (E, A), no noise |
| Timer warning | a gentle G4 knock that steps up the scale (G, A, C) as a clock or an aircraft timer nears zero (from 8 s) |
| UI | very quiet, very short soft clicks, each kind a little different (forward, back, toggle, error, swipe) |
| Star, purchase, new airport | rising bell figures, from three to five notes |

There is **no engine hum**: the music is the only continuous sound (plus the soft fog ambience). Gameplay sounds are part of the
music: arrivals, landings, coins, go-arounds, conflicts, fines, ticks and the stingers wait for the **next eighth-note** of the
music's tempo (0.268 s of the 17.14 s loop; the page reports the loop's phase on the web) so they land on the beat; at most one of
each per beat. Taps, the touchdown tap and the results stingers play at once. Pitch variation is only about 1 % so everything
stays in key.

**Mix.** The music is the reference: heard at its peak (layer 1, 0.35 played at -4 dB) it peaks at 0.22. Gameplay sounds
peak at or below 0.8 of that (landing chime 0.13, big moments 0.16), UI sounds at or below 0.5 (0.09), the touchdown tap 0.03.
The smoke test checks these peaks, and CI records the page's output and fails if any gameplay sound peaks above the music.
Music: a sunny airfield on a busy afternoon, **112 BPM in D major**, eight bars (D | A | Bm | G | D | A | G | A, 17.14 s, a beat is exactly
23 625 samples) with no pads: plucks, a mallet, a clean guitar, soft keys, a simple bass and soft percussion. Three layers of exactly
the same length loop together (native and gapless from the loading page) and crossfade with the traffic (`Sfx.set_music`):
**layer 1** (`music1`: bass, a light kick on 1 and 3, a rim click on 2 and 4, a shaker on every eighth) always plays; **layer 2**
(`music2`: the rhythm guitar strum and keys stabs) comes in when **3 or more aircraft are inbound**; **layer 3** (`music3`: the lead,
a plucked mallet melody with a dotted-eighth echo) when **5 or more are**, or in the **last 20 s** of the shift. A layer is held 2.5 s
after the traffic drops, so it does not flicker; layers 2 and 3 glide at 22 dB a second, layer 1 at 40. The menu plays layers 1 and 2,
quieter. Fog adds a low drone (`tense`: D and its tritone) and an airy bed. The landing chimes and coin plinks are the same notes of
the key. Every loop is seamless and the web check (`tools/web_audio_check.js`) tests each loop on its own (silence, clicks, dropouts,
peaks, the loop point, equal lengths) as well as the recording of the game. Level changes always glide on the wall clock, never cut. The pause menu has three saved
sliders: **Music**, **Effects** (the SFX bus) and **Ambience** (the fog).

## App icon and splash

A gold aircraft with a dark outline and soft shadow, banking across a runway, on a sky-blue rounded square with a top
highlight (`icon.svg`, rendered to `icons/` by `tools/make_icons.gd`). The boot splash is the same mark on the dark
surface (`assets/splash.svg`), followed in the game by the studio mark and the game's logo.

## Studio: Clear Prop Games

The studio mark is a three-blade gold propeller with a dark outline and a white hub in a round dark badge with a blue ring
(`Style.draw_mark`, the same drawing as the SVG in `web/shell.html`). The wordmark is `CLEAR PROP GAMES` in the display face
(Bowlby One SC) with the middle word in gold (`Style.draw_wordmark`). The mark spins up and settles in the logo intro; on
the loading pages it spins while the progress bar fills. No raw text ever shows while loading: the web loading page
(`web/shell.html`) is the brand background, the mark, the wordmark and a bar, with a plain message only if the game cannot start.

## The build stamp

The commit and build time are for debugging only: they show, small, in the bottom-left corner with `?debug`, `?tune` or `?perf`, and never otherwise.
