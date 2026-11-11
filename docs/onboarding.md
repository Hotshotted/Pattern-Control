# Onboarding: audit and plan

Principle: learn by doing, one mechanic at a time, introduced right when it first matters, one short sentence per tip.

## 1. Audit: what explains the game today

Everything that exists in the build before the onboarding work (section 4 is what replaces it):

| Where | What it says | When it fires |
|---|---|---|
| `Main.TIPS` (a one-line pill at the bottom of the shift, `Hud.show_tip`) | "Drag from an aircraft to its runway" | the first aircraft ever seen, once (`Save.tips_seen["drag"]`), only if no other kind of tip applies |
| | "Glider: short timer, watch the ring", "Helicopters land on the H pad", "Jets need a long runway", "Seaplanes land on water", "Emergency: land it fast", "VIP: don't hold it for a bonus", "Student pilot: ..." | the first time that kind of aircraft appears (`_on_appeared`), once each |
| Popups at the plane | "Go-around!" with the reason, "WRONG RUNWAY", "Not into the wind", "Runway closed", "Helipad: helicopters only", "Water lane: seaplanes only", "Gliders can't hold", "VIP delayed: bonus lost" | every time the thing happens (a refusal, not a lesson) |
| Banners | "Wind to 270", "LAST ARRIVALS", "FOG ROLLING IN" and the weather names, "No engines: no go-arounds", the toasts for stars and ranks, "Your new hangar bay: it parks here ..." | wind shift announced 8 s ahead; the finale; weather; the first plane parked in a bought bay |
| Results card | stars slam in, the nearest goal bar ("120 XP to level 5", "40 coins to Runway lights 3", "Ready to buy!"), "Details" breakdown, "Shift pay protected" / "Fines capped" | every shift |
| Airport detail screen | objectives for the three stars, level and next unlock, today's goals, "first goal" strip until something is bought | when an airport card is opened |
| Improve sheet | each row's effect line ("+1 hangar spot"), hold-to-buy preview | when opened |
| Shop and preview | a card per item with its source ("Level 4", "Rank 3", price); hold to buy | when opened |
| Welcome-back screen | what the parked planes earned while away | on return after 5 min or more |
| Goals sheet | three daily goals, reroll, bonus chest, 7-day streak | when opened |
| Pause menu | volume, Restart, Menu, Privacy, Reset progress | when paused |

There is **no tutorial**, no scripted first shift, no highlight on what a tip is about, no way to read a tip again, and nothing is paused for a lesson.

## 2. Every mechanic a new player meets in the first hour, and whether anything explains it

| Mechanic | Explained today? | Verdict |
|---|---|---|
| Drawing a path from the plane to the runway | one pill line on the first plane | thin: no demonstration, the line disappears by itself |
| Runway ends, chevrons, the glow of the end in use | no | **never explained** |
| Landing, then the plane taxiing in | no | **never explained** |
| Hangar, ramp, what a landing earns | only the "new hangar bay" banner (after an upgrade) | **never explained** (hangar full / ramp: results subtitle only) |
| Spacing and conflicts (red rings, near misses) | no | **never explained** |
| Go-arounds | popup with a reason, after it happened | explained only after the fact |
| Fuel / the timer ring (the ring around a plane empties; out of time = diverted and fined) | no | **never explained** |
| Wind, the dial, active runway ends, "Wind to 270" | the banner, nothing about what it means | **never explained** |
| Student pilots | a tip line and (new) the green/red ends | explained once per kind |
| Gliders | one tip line | thin |
| Helicopters, seaplanes, jets, emergencies, VIPs | one tip line each | thin but present |
| Fines (conflicts, diversions, crashes) | the fines counter shows them; no explanation | **never explained** |
| Overtime (the clock turning red after par) | no | **never explained** |
| Stars (the bar, what earns each) | the objectives on the detail screen only | not met in a shift |
| Coins and what they are for | the goal strip says what is next to buy | thin |
| Upgrades (Improve sheet, hold to buy, Tower upgrades) | rows with effect lines | the hold-to-buy gesture is **never explained** |
| Airport levels and XP | the goal strip, level-up toasts | thin |
| Daily goals, streak, chest | the goals sheet | explained when opened, never pointed at |
| Weekly event | a card on the detail screen | **never explained** |
| Offline income | the welcome-back screen | explained when it happens |
| Cosmetic shop | the shop itself | never pointed at |
| Next airport unlock | a level-up toast | thin |

## 3. The plan (what is built)

1. **Day 1** (a scripted first shift at the Grass Strip, no fail state): calm wind, slow traffic, no fines. Plane 1 arrives alone, the game dims and time stops, a ghost finger draws the path to the green runway end ("Drag a path to the runway."); the plane cannot be lost and time waits until the player draws. It lands and taxis in ("Landed planes park in the hangar. Each landing pays."). Planes 2 and 3 arrive close together ("Keep planes apart. A red ring means a crash is coming."). Then three ordinary arrivals with no tips and the shift ends early with a guaranteed decent result. The results tips: stars, then the first upgrade, with the hold-to-buy walked through. A Skip button for returning players.
2. **Just-in-time tips** for everything else, each once, the first time it really happens, with a highlight on the thing it is about, in a sensible order and never more than two new ones in a shift. The first three shifts have no students and no wind shifts.
3. **Tip style:** a small Cozy card near the thing it is about, one sentence and an optional icon, tap anywhere to dismiss; the game pauses only for Day 1 steps.
4. **Settings:** a Tips page (every tip seen, to reread) and Replay tutorial.
5. **Checks:** the tutorial steps and each tip card are states in `tools/ui_overlap_check.gd`; a smoke test plays Day 1 with scripted inputs; the dev menu (`?tune`) has "Fresh start, tutorial on".
