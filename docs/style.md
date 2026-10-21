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

Short, soft and rounded: a bright pop for taps, a lower thud for back, a rising two-note for rewards, a muted buzz for
errors. Music has a calm and a tense layer that cross-fade; fog adds ambience. All procedural, no files.
