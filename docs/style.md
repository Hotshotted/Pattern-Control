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

A top-down, warm, soft and lived-in toy diorama. Same game and layouts as ever; the mood comes from the light first, then from
shaded surfaces, soft shadows and a little life. (It replaces the earlier "Sunny Airfield" look.)

**Light and shading**
* The camera looks straight down. **One light overlay** (`LightOverlay`, a ColorRect with `shaders/light_overlay.gdshader`) sits over
  the whole field, above the 3D scene and below the paths, rings and interface: a warm radial glow `#FFD68A` pinned to the
  upper-left corner (35 % at its centre, fading to 0 by 90 % of the screen diagonal, added to the picture), a cool radial shade
  `#2F4A7A` pinned to the lower-right (20 %, fading the same way), and **8 % static film grain** from a tiled 128 px noise texture
  (made once, never per-frame). `?nolight` switches the overlay off for comparison.
* Surfaces are softly shaded, not flat: every roof, wing, tree and tank runs from lighter at its upper-left to darker at its
  lower-right, about 18 % in value (`Prim.SHADE`), baked into vertex colours at build time: no per-frame cost. The field itself is
  a gradient mesh. **No outlines anywhere on the ground**; aircraft keep a thin, soft slate edge only.
* **Shadows** are blue-grey `#3B4A6B` at 26 %, soft-edged with the softness baked into small textures once (`Shadow.gd`; nothing is
  blurred at run time), cast toward the lower-right. A building's shadow is half as long as the building is high. A flying plane's
  shadow slides further away as it climbs and fades a little; on the ground it hugs the wheels.

**Palette (Countryside; one palette per airport, Coastal and Alpine are config variants with their own ground, walls and accent)**
* Grass: a gradient across the field from `#B9DC72` (upper-left) through `#8FC45C` to `#76AA4B` (lower-right), lighter and darker
  translucent patches, and small three-blade grass tufts scattered sparsely (never in the approach corridors).
* Runway asphalt `#6A7079` to `#565B66`; markings cream `#F2EDE4` at 90 %, runway numbers at 80 %, rubber streaks on the touchdown
  zones at 20 % black. Taxiway `#A3A8B0` with yellow `#E6C35A` centreline dashes. Apron `#B6BBC2` to `#9CA1A9`.
* Accents: orange `#F0803C` (runway 1 livery, the primary button), blue `#4C8FD6` (runway 2), violet `#8E6BBE` (helipad), teal
  `#2BA3A6` (seaplane lane). Airframes stay white with the livery on the nose, wingtips and fin and a soft gradient across the wings.
* Trees: round canopies with a radial gradient from `#9AD46E` to `#3F7D3F`, each with a soft shadow.
* Buildings: rust hangar roof `#E2654A` to `#B3452F`, teal FBO roof `#4FB8B2` to `#2F8D88`, cream tower `#FFF2DC` to `#E3D3B6` with
  a navy cab and a red beacon; a 4 px darker side on the right and bottom.

**Readability is unchanged:** paths are lines of round dots in the runway colour (final segment green / yellow / red), timer rings
are thick on a dark track (green, yellow, red, red adds a halo), conflicts are a red dashed ring around the pair. Scenery, life and
props are placed outside the approach corridors and the strips where paths get drawn, so nothing can block or confuse a path.

**The ground kit and the life** (pooled, pre-warmed; only the truck, birds, balloon, mower and windsock move; `?nolife` stops them):
parked planes on tie-downs with wheel chocks, a plane being washed, a fuel farm and a fuel truck that drives to a parked plane and
back, a picnic table with a dog, a small car park, PAPI lights, two birds, a mower leaving stripes, a hot-air balloon and a glider on
a trailer (scenery only), and a landmark per airport (Countryside: red barn and silo; Coastal: lighthouse and pier with gulls;
Alpine: timber lodge with chimney smoke, pines and a chairlift).

**Interface:** cream surfaces (gradient `#FFF8EA` to `#F6E8CF`, a solid 4 px bottom edge `#C9A46E`, a soft drop shadow, text `#5A3A12`),
pills fully rounded, cards 22 px radius. The primary button is orange (`#FF9D4F` to `#F0803C`, a 7 px bottom edge `#B85A1B`, inset
top highlight, white text with a slight dark shadow); pressing it drops it onto its edge. The display face is **Bowlby One SC**
(title, timer, score, headers) in cream `#FFF4DF` with a stacked warm extrusion (`#C9641F` to `#803D11`) and a soft shadow; the title
sits at a 2 degree tilt. Body and labels are **Rubik** 800 and 500. The coin is a real gold coin (`#F2B233`, darker rim, a propeller
mark); stars are gold with a dark outline, empty stars cream. HUD positions never move.

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
* **One key:** C major pentatonic (C D E G A), the key of the music (chords C, Am, F, G). All pitched sounds are drawn from it
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
music's tempo (0.375 s of the 6 s loop; the page reports the loop's phase on the web) so they land on the beat; at most one of
each per beat. Taps, the touchdown tap and the results stingers play at once. Pitch variation is only about 1 % so everything
stays in key.

**Mix.** The music is the reference: heard at its peak (the calm layer, 0.35 played at -4 dB) it peaks at 0.22. Gameplay sounds
peak at or below 0.8 of that (landing chime 0.13, big moments 0.16), UI sounds at or below 0.5 (0.09), the touchdown tap 0.03.
The smoke test checks these peaks, and CI records the page's output and fails if any gameplay sound peaks above the music.
Music: a warm pad with a soft bass, then a plucked pentatonic arpeggio with a very soft pulse that fades in smoothly through the
second half of a shift and to the top in the finale; fog adds a low drone and an airy bed. All layers are the same length (6 s)
and every loop is seamless. Level changes always glide (at most 60 dB a second), never cut. The pause menu has three saved
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

## Landing, taxi and the hangar (polish pass, item 1)

A landing ends in a puff of dust and a tiny tyre chirp (a soft E5→G5 glide in the key, played on the next eighth of the music, far under it).
The aircraft rolls out, leaves the runway past its far end and taxies at 1.05 units/s along a fixed route to its place. The route is
the shortest one that keeps 0.5 clear of every runway box (`Ramp.route`), so it never crosses one. Taxiing aircraft are scenery: they
have no collisions, sit on the ground under the paths and the flying traffic, and at most four taxi at their own pace (the older ones
hurry at 9x). Where they go (`Ramp.place`): the **hangar** takes as many as break the shift even (the one-star threshold divided by
the airport's average landing pay, rounded up; the door shows "N / cap"), then the six **tie-downs** on the apron (chocks appear), then up
to six **overflow spots** on the grass along the taxiway, then only the "+N" tag by the apron. A helicopter sits on the pad for 3 s, then
air-taxis to the marked heli spot; a seaplane taxies to the island's dock. Crashes park nothing. Everything that can park is built once, hidden;
a shift restart clears it in place. The results card says "Hangar full · 9 on the ramp" or "Hangar 5 / 8".

## Path feel (polish pass, item 2)

While drawing, the path follows the average of the finger's last four points (`path_smooth_points`), so a shaky finger draws a smooth
line; the coloured dots keep their halo. A finger within `snap_radius` (0.45) of an open runway end's extended centreline, between 0.5 and
`snap_reach` (3.6) behind the threshold and heading for it, snaps onto the centreline and locks: a soft click, a pulse ring at the lock point
and a short buzz (`navigator.vibrate` on the web, `Input.vibrate_handheld` elsewhere). Tapping a plane clears its path, which fades out over
`path_fade_seconds`. The snap radius, reach, smoothing and fade are in `?tune`.

## Time passing (polish pass, item 3)

Over the shift the light moves on, linearly: the warm glow goes from 35% to 50% and the cool shade from 20% to 30%; every shadow
offset (props, buildings, the aircraft's own) is up to 30% longer (`Shadow.set_time`, which moves the registered shadow quads out
along their own offset); and the grass gradient gets a touch warmer (blue down 9%, green down 2%). A restart resets it all; Bad Pilot Day
starts 40% of the way in.

## Wind you can always see (polish pass, item 4)

Twelve thin cream streaks (60-120 px, about 10% opacity) drift across the field the way the air is going, at 20-60 px/s by the wind's
strength, above the ground props and below the paths and the aircraft (a pooled MultiMesh, each streak fades in and out and is reborn
elsewhere). The grass tufts lean downwind, the trees rock about a lean, the pond ripples and the windsock points downwind. When the wind
shifts the streaks swing round over about 1.2 s and briefly double in brightness, the trees sway three times harder for a second and a
soft gust (a low swell of filtered air, quantised to the music) plays; the wind card's arrow turns smoothly. `?nowind` switches all of
this off; `?windtest` (used by CI) clears the field of aircraft and lets only the wind move. CI loads the real web export twice
(`tools/web_wind_check.js`) and compares two frames a moment apart on the open grass beside the runway: with the wind enough pixels
move, with `?nowind` none do.

## The go-around telegraph (polish pass, item 5)

A go-around is signalled one second before it happens (`go_around_telegraph`): the aircraft wobbles (±4° of roll), a "?" tag shows over
it and its engine note rises (a soft glide in the key). If the player redraws a final whose go-around chance is under 60% of the one it was
rolled at before the second is up, the go-around is cancelled; holding the aircraft cancels it too. Otherwise the tag becomes "GOING AROUND"
and the climb-out proceeds as before. `tools/economy_sim.gd` logs how many warnings were cancelled by the bots (the better the bot, the more).

## Juice (polish pass, item 6)

Coins leave the wheels at touchdown, not at the end of the roll, and arc to the counter one after the other; each plinks (climbing the
scale) and bumps the counter on arrival. Buttons squash to 94% while pressed and spring back. A timer ring pulses once as it turns red.
Score pops rotate a few degrees at random (Cozy phase 3).
