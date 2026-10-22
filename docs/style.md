# Pattern Work: style guide

One identity for every screen: **friendly, chunky, high-contrast, sunny**. A dark navy interface floats over the bright
airfield; gold means money and stars, green means go, red means trouble. Everything below lives in code in
`scripts/Style.gd` (the tokens) and `scripts/Hud.gd` (the drawing). Change the token, not the call site.

## Palette

| Role | Token | Hex | Use |
|---|---|---|---|
| Primary | `PRIMARY` | `#3d8bff` | brand blue: selection, links, info |
| Primary dark | `PRIMARY_DARK` | `#2459c4` | pressed / lip of blue elements |
| Accent | `ACCENT` | `#ffc933` | coins, stars, rewards, the one thing to look at |
| Accent dark | `ACCENT_DARK` | `#c98a0b` | lip of gold elements |
| Success | `SUCCESS` | `#35c98a` | PLAY, earned, go |
| Success dark | `SUCCESS_DARK` | `#1a8a5a` | lip of the primary button, affordable cards |
| Warning | `WARNING` | `#ff9f2e` | streaks, wind and weather notices |
| Danger | `DANGER` | `#ff5c4d` | fines, conflicts, overtime, last 15 s |
| Danger dark | `DANGER_DARK` | `#b63227` | lip of red elements |
| Ink | `INK` | `#0a1020` | outlines, deepest dark |
| Surface dark | `SURFACE_DARK` | `#14213d` | cards, sheets, pills on the dark UI |
| Surface dark 2 | `SURFACE_DARK_2` | `#1d3157` | raised or selected dark surface |
| Surface light | `SURFACE_LIGHT` | `#f3f7ff` | popups on a light theme |
| Surface light 2 | `SURFACE_LIGHT_2` | `#d9e5f8` | light cards, dividers |
| Text | `TEXT` | `#ffffff` | primary text on dark |
| Text soft | `TEXT_SOFT` | `#bcd0ec` | secondary text |
| Text quiet | `TEXT_QUIET` | `#8497b8` | tertiary / disabled text |
| Text on light | `TEXT_ON_LIGHT` | `#14213d` | text on the light surfaces |
| Scrim | `SCRIM` | `#060b18` | the shade behind a screen or sheet |

Contrast: `TEXT`, `TEXT_SOFT` and `ACCENT` on `SURFACE_DARK`, and `TEXT_ON_LIGHT` on `SURFACE_LIGHT`, are all at least
4.5:1 (checked by the smoke test). Text on a coloured button is always drawn with an ink outline (1/8 of its size).
Colour is never the only signal: fines and overtime also use a minus sign / a plus sign, stars use a shape.

## Typography

Both fonts are open-licence (SIL OFL 1.1; licence files in `assets/fonts/`), variable fonts from the google/fonts repository.

* **Display: Fredoka SemiBold (600)**, rounded and friendly. Titles, every number (coins, clock, costs, "+488") and
  anything at XL / M size.
* **Text: Nunito Bold (700)**, soft and very readable. Labels, one-line descriptions, tips.
* Three sizes only: **XL 110** (the one primary thing), **M 56** (card titles, banners), **S 30** (secondary).
* Text on the game view always carries an ink outline (size / 8, at least 4 px) so it reads over any ground.
* Labels are at most about four words; a description is one short line.

## Shape

* Corner radii: **S 14** (inner highlights), **M 26** (cards, chips), **L 40** (primary button, sheets), **pill 60** (banners, tips, round buttons).
* Borders: 3 px light line on cards and sheets (alpha 0.55), 5 px on the primary button.
* **Shadow:** soft, offset down: colour `#030814` at 45 %, blur 16 px, offset (0, 8). Every raised panel has it; flat things do not.
* **Gradient:** every card and button has a light-to-clear highlight across its top half (a rounded cap that fades down), so
  panels read as slightly domed rather than flat.
* **Chunky lip:** the primary button sits on a darker lip 10 px tall; pressing pushes it down into the lip.

## Buttons

| Style | Look | Used for |
|---|---|---|
| Primary | big, green, XL text and an icon, chunky lip | PLAY, PLAY AGAIN, RESUME: one per screen |
| Secondary | dark surface, light border, soft shadow | cards, list rows, chips, round menu buttons |
| Ghost | translucent dark round chip, icon only, no shadow | back, home, pause |

States: **normal**, **pressed** (face pushed down 5 px, primary squashes into its lip), **disabled** (flat, greyed, no
shadow, no lip; taps are swallowed, not passed to the game), **accent** (selected / affordable: green fill; a maxed
upgrade is gold).

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
* **Rendering:** all sound is synthesised once at start-up into 16-bit `AudioStreamWAV` clips (16 kHz) and played from a
  small pool: no files, no generators, and no buses created at run time (that silences the single-threaded web export). The
  `SFX` and `Music` buses and the Master **limiter** (a hard limiter, ceiling -1 dB) come from `default_bus_layout.tres`.

**The sounds**

| Moment | Sound |
|---|---|
| Touchdown | a soft tire chirp (filtered noise and a faint falling squeak) |
| Landing | a warm two-note bell chime; landings in quick succession climb the scale (seven steps), so a streak is a little melody |
| Coin | a soft bell plink, one note higher for each coin that reaches the counter, starting over after a pause |
| Conflict | a low muted thud with a soft descending two-tone (A3 to E3); fines are the thud alone |
| Go-around | a soft whoosh with a rising engine swell |
| Timer warning | a gentle knock that comes faster and slightly higher the closer a clock or an aircraft timer is to zero (from 8 s) |
| UI | very quiet, very short soft clicks, each kind a little different (forward, back, toggle, error, swipe) |
| Star, purchase, new airport | rising bell figures, from three to five notes |
| Engines | low, smooth, quiet sine beds per aircraft type; they should barely register |

**Mix.** Loudness is normalised per clip by role (peak): engine hums 0.07, UI 0.10 (the quietest), gameplay 0.30, big moments
(landing, star, new airport, results slam) 0.50. Music sits underneath the gameplay sounds: a warm pad with a soft bass, then
a plucked pentatonic arpeggio with a very soft pulse that fades in smoothly through the second half of a shift and to the
top in the finale; fog adds a low drone and an airy bed. All layers are the same length (6 s) and every loop is seamless.
Level changes always glide (at most 60 dB a second), never cut.

## App icon and splash

A gold aircraft with a dark outline and soft shadow, banking across a runway, on a sky-blue rounded square with a top
highlight (`icon.svg`, rendered to `icons/` by `tools/make_icons.gd`). The boot splash is the same mark on the dark
surface (`assets/splash.svg`), followed in the game by the studio mark and the game's logo.

## Studio: Clear Prop Games

The studio mark is a three-blade gold propeller with a dark outline and a white hub in a round dark badge with a blue ring
(`Style.draw_mark`, the same drawing as the SVG in `web/shell.html`). The wordmark is `CLEAR PROP GAMES` in the display face
(Fredoka SemiBold) with the middle word in gold (`Style.draw_wordmark`). The mark spins up and settles in the logo intro; on
the loading pages it spins while the progress bar fills. No raw text ever shows while loading: the web loading page
(`web/shell.html`) is the brand background, the mark, the wordmark and a bar, with a plain message only if the game cannot start.

## The build stamp

The commit and build time are for debugging only: they show, small, in the bottom-left corner with `?debug`, `?tune` or `?perf`, and never otherwise.
