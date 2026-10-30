# Pattern Work: content audit

Nothing in the game was changed for this audit. The only file added is this one. The numbers come from the game's own code (`Tuning.gd`, `Airports.gd`, `Upgrades.gd`, `Cosmetics.gd`, `Save.gd`, `Main.gd`) and from headless simulations of the real shift code played by three autopilot bots.

## How to read the simulations

- **Bots.** `poor`, `average` and `good` are deterministic autopilots with different reaction and routing skill (fixed seeds). They are a model of a player, not players. A human who learns an airport will beat the `average` bot there.
- **Coins.** *gross* is landing pay plus bonuses; *fines* are conflict, diversion and hazard fines plus overtime; *net* is gross minus fines (this is what the star thresholds measure); *paid* is what the player banks, which is `max(net, 50% of landing pay)`. A shift can be net-negative and still pay.
- **Minutes.** A shift is its length plus a 20 s overhead for menu, results and tapping through. Minutes of play are cumulative shift minutes.
- **Two spending policies, because the order a player plays airports decides what they see.**
  - `newest`: always fly the highest open airport.
  - `yield`: fly the open airport with the best coins per minute, trying each once.
  The real range of human behaviour sits between them.
- **Buying.** Each bot buys the cheapest upgrade it can afford as soon as it can, then cosmetics once every upgrade is bought. A human would choose differently, but total cost is the same.
- **Caps.** Careers run 250 shifts (about 6 to 8 hours of play), and the survey runs 30 shifts per bot per airport, once with no upgrades and once with every upgrade at level 3.

---

## 1. Inventory

### 1.1 Airports

Six airports. Each opens when the player's total stars across all airports reach the unlock number. **Star 1** is for finishing the shift with at least that many landings; **stars 2 and 3** are for the shift's **net coins** (after fines). A star needs the ones before it. (Tables in sections 1 to 5 describe the game after balance phase 1 where they say so; the economy numbers in sections 2 to 4 are the original audit, kept as the baseline. Section 6 has the before and after.)

| # | Airport | Tag | Runways | Pads | Water lanes | Mountains | Opens at | Shift | Max planes | Spawn gap (start → end) | Stars: landings / net coins / net coins |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Grass Strip | One runway, both directions | 1 | 0 | 0 | 0 | 0 stars | 45 s | 3 | 7.0 → 4.4 s | 2 / 40 / 70 |
| 1 | County | Crossing runways | 2 | 0 | 0 | 0 | 2 stars | 60 s | 4 | 6.5 → 4.0 s | 2 / 15 / 45 |
| 2 | Regional | Parallel runways + helipad | 2 | 1 | 0 | 0 | 4 stars | 75 s | 6 | 6.0 → 3.2 s | 4 / 15 / 40 |
| 3 | Mountain Field | Keep clear of the mountains | 2 | 0 | 0 | 5 | 7 stars | 75 s | 6 | 6.5 → 3.8 s | 3 / 25 / 160 |
| 4 | Island | Water landing lane | 2 | 0 | 1 | 0 | 10 stars | 90 s | 12 | 4.8 → 1.9 s | 6 / 35 / 345 |
| 5 | International | Everything, all at once | 3 | 2 | 2 | 0 | 13 stars | 90 s | 14 | 4.2 → 1.5 s | 6 / 125 / 360 |

18 stars exist in total; the last airport opens at 13, so 5 stars are never needed to progress.

**Traffic mix** (share of arrivals):

| Airport | Small | Medium | Jet | Glider | Helicopter | Seaplane |
|---|---|---|---|---|---|---|
| Grass Strip | 85% | | | 15% | | |
| County | 35% | 45% | | 20% | | |
| Regional | 25% | 35% | 20% | | 20% | |
| Mountain Field | 30% | 35% | | 35% | | |
| Island | 20% | 25% | 30% | | | 25% |
| International | 10% | 25% | 30% | | 15% | 20% |

**Other per-airport tuning.** Plane speed ×0.75, 0.85, 0.92, 0.92, 1.05, 1.12 (in airport order). Timer length ×1.5, 1.35, 1.2, 1.4, 0.95, 0.9 (Mountain Field is calmer than before: 6 aircraft, slower spawns, longer timers). Special-aircraft rate ×0, 0.3, 0.6, 1.0, 1.1, 1.5. Fine scale ×0.3, 0.3, 0.35, 0.35, 0.45, 0.45. Scripted beats: Grass a glider at 5 s; County a small plane at 5 s; Regional a helicopter at 5 s and a jet at 24 s; Mountain a small plane at 5 s; Island a seaplane at 5 s; International a helicopter at 5 s, a seaplane at 22 s and a jet at 40 s.

**Runways in play.** The wind decides the active runway. First wind change / strength: Grass none; County 35 s / ×2.2; Regional 38 s / ×1.5; Mountain 35 s / ×1.0; Island 32 s / ×0.8; International 30 s / ×0.6. Wind then shifts every 55 s down to 28 s, with an 8 s warning.

**Weather events** (announced 6 s ahead; spacing 60 s down to 32 s; storm and fog last 22 s, a crosswind closure 16 s):

| Airport | Events | First event | Strength |
|---|---|---|---|
| Grass Strip | none | – | – |
| County | none (wind only) | – | – |
| Regional | crosswind, fog | 50 s | ×1.6 |
| Mountain Field | storm, fog | 45 s | ×1.0 |
| Island | storm, crosswind, fog | 40 s | ×0.85 |
| International | storm, crosswind, fog | 35 s | ×0.7 |

### 1.2 Pay and fines

| Item | Coins |
|---|---|
| Landing: small 10, medium 14, helicopter 18, jet 20, seaplane 16, glider 22 (Grass Strip glider ×1.4) | per landing |
| Student pilot (12% of runway arrivals) | pay ×2 |
| VIP (8% × specials rate) | +25 |
| Emergency (5% × specials rate, timer ×0.5) | +60 |
| Quick-succession streak | +4 per landing already in the streak, window 4 s, cap 5 |
| Finishing before the par window | +6 per second early |
| Overtime | −4 per second |
| Conflict | −100 × airport fine scale |
| Diversion (timer runs out) | −20 × scale |
| Hazard (mountain) | −50 × scale |
| First time a star is earned | +100 per star (up to +1,800 once) |
| Pay floor | a completed shift always pays at least 25% of its gross (landing pay + bonuses + early bonus); fines and overtime cut the pay down to that floor and no further. Stars still use the net. The results card says "Shift pay protected" when the floor is what pays. A shift left from the pause menu pays nothing. |

### 1.3 Upgrades

Six upgrades, three levels each, **global** (not per airport). 5,520 coins to buy all 18 levels.

| Upgrade | Level 1 | Level 2 | Level 3 | Total | Effect per level |
|---|---|---|---|---|---|
| Radar | 160 | 360 | 700 | 1,220 | view +12%; arrivals announced 0.6 s earlier |
| Approach Control | 200 | 450 | 800 | 1,450 | +25% chance an arrival comes in lined up |
| Tower Staff | 120 | 280 | 550 | 950 | traffic 4% slower; arrivals 6% rarer |
| Better Comms | 50 | 140 | 320 | 510 | timers +10% |
| Holding Fixes | 70 | 180 | 380 | 630 | holds drain 20% slower; circles 12% tighter |
| Fast Turnoffs | 90 | 220 | 450 | 760 | runways clear 30% faster |

### 1.4 Cosmetics

Prices in coins. These change looks only.

| Airport themes | Price | Plane liveries | Price |
|---|---|---|---|
| Classic | free | Pattern Air | free |
| Autumn | 300 | Fox Air | 200 |
| Desert | 500 | Owl Express | 300 |
| Winter | 700 | Penguin Pacific | 400 |
| Night | 900 | Bear Cargo | 500 |
| | | Cat Airways | 600 |
| **Total** | **2,400** | **Total** | **2,000** |

Cosmetics total 4,400 coins. Everything purchasable (upgrades + cosmetics) is **9,920 coins**.

### 1.5 Modes and modifiers

| Mode | How it works | Gate |
|---|---|---|
| Regular shift | Pick an airport, play its shift, earn stars and coins. | Airport unlock (stars). |
| Daily shift | One seeded shift per day. Airport is one of the open airports, picked by the day (`day % 6` when all six are open). No permanent stars, but at least 1 star completes it. Bonus 75 + 13 × min(streak, 7) coins; streak resets after a missed day; keeps its own best. | Open airports only (fixed in balance phase 1; before it, the airport could be locked). |
| Bad Pilot Day | Same daily shape with its own streak and best. Airport is one of the open airports, picked by `day + 3` (`(day + 3) % 6` when all six are open). Every arrival is a student, go-around floor 0.6, landing pay ×1.5, net-coin star thresholds ×2.5 (the landing count for star 1 is the same), bonus ×2. | Open airports only. |
| No engines | Optional per airport: nobody can go around. Landing pay ×2. Also a switch for Bad Pilot Day. | The airport must have 3 stars. |
| Intro shift | The first shift at an airport spawns fewer planes with longer timers. | Automatic. |

One-time tips cover dragging a path, gliders, helicopters, jets, seaplanes, emergencies, VIPs and students.

### 1.6 Unlocks and what gates them

- **Airports:** total stars 0, 2, 4, 7, 10, 13.
- **Upgrades, cosmetics:** coins only. Nothing is stars-gated, nothing is airport-gated.
- **No engines:** 3 stars at that airport.
- **Daily and Bad Pilot Day:** available every day; each can be done once per day.
- **Ads (stubs):** a rewarded ad refunds the biggest fine or doubles a shift's coins; an interstitial slot comes every 3 shifts. Both are stubs, nothing real is shown.
- **Debug:** an "all airports" flag opens everything.

### 1.7 Missions, achievements, daily rewards

- **Missions:** none.
- **Achievements:** none.
- **Leaderboards / friends / notifications:** none.
- **Daily rewards:** only the daily shift bonus above (88 to 166 coins at streak 1 to 7). There is no login reward, no calendar, no chest.
- **Records:** best coins per shift per airport, best landings per airport, daily best, Bad Pilot Day best.

---

## 2. Economy timeline

*(Original game, before balance phase 1: sections 2 to 4 are the baseline. Section 6 has the numbers after.)*

### 2.1 Coins per shift and per minute, by airport (survey)

Thirty shifts per cell. **No upgrades.** Coins per shift, then per minute of play (shift + 20 s overhead). `stars ≥1` is the share of shifts that earn at least one star.

| Bot | Airport | Gross | Fines | Net | Paid | Min/shift | Gross/min | Net/min | Paid/min | Shifts ≥1 star |
|---|---|---|---|---|---|---|---|---|---|---|
| Poor | Grass Strip | 57 | 149 | −92 | 24 | 1.63 | 35 | −56 | 15 | 10% |
| Poor | County | 61 | 277 | −216 | 20 | 1.80 | 34 | −120 | 11 | 0% |
| Poor | Regional | 108 | 442 | −334 | 41 | 2.07 | 52 | −162 | 20 | 0% |
| Poor | Mountain Field | 75 | 915 | −840 | 16 | 1.77 | 42 | −474 | 9 | 0% |
| Poor | Island | 182 | 1,147 | −965 | 63 | 2.30 | 79 | −419 | 27 | 0% |
| Poor | International | 270 | 991 | −721 | 78 | 2.30 | 118 | −313 | 34 | 0% |
| Average | Grass Strip | 89 | 102 | −13 | 38 | 1.43 | 62 | −9 | 27 | 31% |
| Average | County | 121 | 179 | −57 | 43 | 1.55 | 78 | −37 | 27 | 24% |
| Average | Regional | 176 | 314 | −138 | 66 | 1.89 | 93 | −73 | 35 | 10% |
| Average | Mountain Field | 168 | 688 | −520 | 57 | 1.87 | 90 | −278 | 30 | 0% |
| Average | Island | 331 | 908 | −577 | 99 | 2.09 | 158 | −276 | 47 | 0% |
| Average | International | 413 | 821 | −408 | 110 | 2.04 | 203 | −200 | 54 | 0% |
| Good | Grass Strip | 122 | 41 | +81 | 83 | 1.26 | 97 | +64 | 66 | 97% |
| Good | County | 176 | 88 | +88 | 102 | 1.47 | 120 | +60 | 69 | 83% |
| Good | Regional | 243 | 193 | +49 | 112 | 1.72 | 141 | +29 | 65 | 48% |
| Good | Mountain Field | 234 | 559 | −325 | 78 | 1.71 | 137 | −189 | 45 | 0% |
| Good | Island | 434 | 700 | −266 | 139 | 2.00 | 218 | −133 | 70 | 3% |
| Good | International | 490 | 626 | −136 | 162 | 1.98 | 247 | −69 | 82 | 17% |

**With every upgrade at level 3** (same survey):

| Bot | Airport | Gross | Fines | Net | Paid | Gross/min | Net/min | Paid/min | Shifts ≥1 star |
|---|---|---|---|---|---|---|---|---|---|
| Poor | Grass Strip | 69 | 118 | −49 | 32 | 47 | −33 | 22 | 28% |
| Poor | County | 68 | 239 | −171 | 25 | 37 | −93 | 14 | 7% |
| Poor | Regional | 99 | 418 | −319 | 35 | 49 | −156 | 17 | 0% |
| Poor | Mountain Field | 82 | 726 | −644 | 24 | 44 | −340 | 12 | 0% |
| Poor | Island | 184 | 1,033 | −849 | 54 | 75 | −348 | 22 | 0% |
| Poor | International | 203 | 919 | −716 | 60 | 90 | −317 | 27 | 0% |
| Average | Grass Strip | 100 | 98 | +2 | 56 | 70 | +1 | 39 | 48% |
| Average | County | 134 | 135 | −2 | 67 | 81 | −1 | 40 | 45% |
| Average | Regional | 172 | 234 | −62 | 74 | 93 | −34 | 40 | 17% |
| Average | Mountain Field | 172 | 504 | −332 | 57 | 94 | −180 | 31 | 3% |
| Average | Island | 315 | 681 | −367 | 108 | 144 | −168 | 50 | 10% |
| Average | International | 369 | 644 | −275 | 119 | 172 | −128 | 56 | 10% |
| Good | Grass Strip | 116 | 37 | +79 | 87 | 88 | +60 | 66 | 86% |
| Good | County | 170 | 67 | +103 | 112 | 116 | +70 | 77 | 79% |
| Good | Regional | 246 | 122 | +124 | 135 | 143 | +72 | 79 | 86% |
| Good | Mountain Field | 223 | 372 | −149 | 83 | 125 | −84 | 46 | 14% |
| Good | Island | 423 | 489 | −67 | 146 | 209 | −33 | 72 | 14% |
| Good | International | 454 | 464 | −10 | 174 | 222 | −5 | 85 | 31% |

What the survey says:

1. **Income per minute rises with airport number, but only on the "paid" floor.** Paid per minute climbs from about 15 to 66 coins (Grass, no upgrades) to 34 to 82 (International). The floor (50% of landing pay) is what keeps the harder airports paying, because their net is negative for every bot but the good one on the first three airports.
2. **Mountain Field is the first wall.** Even the good bot with all upgrades is net-negative there (−149) and earns a star in only 14% of shifts. The same bot nets +124 at Regional. Fines jump from 193 to 559 because the fine scale rises from 0.8 to 1.0 and mountain hazards add 50 each.
3. **Upgrades barely move the average and poor bots.** All-level-3 raises the average bot's Grass net from −13 to +2 and leaves Mountain at −332. For the good bot they matter more: Regional net +49 → +124, one-star rate 48% → 86%.
4. **The star thresholds are net coins**, so a shift that pays well but fines heavily scores no stars. Mountain asks 65 net for one star; no bot averages that there, even with upgrades.

### 2.2 Minutes of play to reach each milestone (careers)

All times are cumulative minutes of play (including the 20 s per shift overhead). "–" means the milestone was not reached in 250 shifts.

**Airport unlocks**

| Bot / policy | County (2★) | Regional (5★) | Mountain (8★) | Island (11★) | International (14★) | Stars at the end |
|---|---|---|---|---|---|---|
| Poor / newest | 9.1 | – | – | – | – | 3 of 18 |
| Poor / yield | 9.1 | – | – | – | – | 3 of 18 |
| Average / newest | 1.3 | 10.7 | 22.8 | 216.9 | – | 12 of 18 |
| Average / yield | 1.2 | – | – | – | – | 3 of 18 |
| Good / newest | 1.2 | 2.7 | 4.4 | 7.9 | 93.1 | 17 of 18 |
| Good / yield | 1.3 | 2.7 | 4.5 | – | – | 9 of 18 |

(A shift counts as one result: three stars on the first Grass Strip shift opens County at once, so the 1.2 to 1.3 minute figure is the first shift.)

**Upgrades.** Minutes at which level 1 and level 3 of each upgrade were bought (L1 / L3):

| Upgrade | Poor / newest | Poor / yield | Average / newest | Average / yield | Good / newest | Good / yield |
|---|---|---|---|---|---|---|
| Radar | 34.6 / 413 | 27.6 / 339 | 10.7 / 134 | 8.7 / 92 | 2.7 / 49 | 2.7 / 45 |
| Approach Control | 72.8 / – | 60.4 / 387 | 15.9 / 162 | 20.6 / 105 | 4.4 / 61 | 4.5 / 56 |
| Tower Staff | 9.1 / 355 | 9.1 / 279 | 1.3 / 107 | 1.2 / 83 | 2.7 / 39 | 1.3 / 38 |
| Better Comms | 7.8 / 158 | 7.8 / 119 | 1.3 / 30 | 1.2 / 34 | 1.2 / 10 | 1.3 / 10 |
| Holding Fixes | 9.1 / 225 | 9.1 / 188 | 1.3 / 56 | 1.2 / 49 | 1.2 / 20 | 1.3 / 22 |
| Fast Turnoffs | 9.1 / 311 | 9.1 / 255 | 1.3 / 89 | 1.2 / 67 | 1.2 / 34 | 1.3 / 32 |

**Buying everything**

| Bot / policy | All 18 upgrade levels | All 9 cosmetics | Everything (9,920 coins) | Three stars at all six airports |
|---|---|---|---|---|
| Poor / newest | – (17 of 18 levels in 468 min) | – (none bought) | – | – |
| Poor / yield | 387 min | – (2 of 9 by 425 min) | – | – |
| Average / newest | 162 min | 264 min | 264 min | – |
| Average / yield | 105 min | 213 min | 213 min | – |
| Good / newest | 61 min | 106 min | 106 min | – (17 of 18 stars) |
| Good / yield | 56 min | 116 min | 116 min | – (9 of 18 stars) |

Reading the table:

- **Good bot:** every upgrade at about 1 hour, every cosmetic at about 2 hours. After that its bank only grows (24.8k banked at 360 min on `newest`) and there is nothing to spend on.
- **Average bot:** everything bought by 3.5 to 4.5 hours.
- **Poor bot:** about 5,400 to 6,200 coins earned in 7 hours, against 9,920 for everything. It cannot buy everything even at that pace; upgrades alone (5,520) take it 387 minutes on `yield`.
- **Three stars everywhere:** no bot reaches it in 250 shifts. The good bot reaches 17 of 18 (`newest`, by 180 min). The last star is an International 3-star (340 net coins).

---

## 3. Pinch points

Defined as: **nothing affordable** (the player's coins are below the cheapest remaining item at the start of a shift), **nothing new to unlock** (no airport opens and the next one needs more stars than the current airports can give), **net-negative shifts**, and **repeated airport** (the same airport played back to back).

| Bot / policy | Net ≤ 0 shifts | Longest net ≤ 0 run | Longest "nothing affordable" run | Shifts at the most-played airport | What the bot ends up doing |
|---|---|---|---|---|---|
| Poor / newest | 245 of 250 | 92 shifts / 170 min | 250 shifts / 468 min (the whole career) | County 245 | Never earns a star past the first three. |
| Poor / yield | 210 of 250 | 29 shifts / 54 min | 228 shifts / 386 min | Grass Strip 241 | Same. |
| Average / newest | 238 of 250 | 104 shifts / 192 min | 89 shifts / 160 min | Island 131, Mountain 105 | Grinds the two hardest airports it has opened, net-negative almost every shift. |
| Average / yield | 79 of 250 | 8 shifts / 12 min | 74 shifts / 104 min | Grass Strip 249 | Stuck on Grass with 3 stars, only 2 airports open. |
| Good / newest | 115 of 250 | 8 shifts / 16 min | 31 shifts / 59 min | International 202 | Settles at the last airport from minute 93. |
| Good / yield | 27 of 250 | 3 shifts / 6 min | 34 shifts / 54 min | County 241 | Stays at County (best coins per minute), 9 of 18 stars. |

Where each bot stalls:

- **Poor bot.**
  - *Nothing affordable* from the start: the first purchase (Better Comms, 50 coins) arrives at 7.8 min; the next (70 to 90 coins) at 9.1 min. After that it banks about 20 coins per shift, so each further level takes many shifts: 9 upgrade levels at 90 minutes, 16 to 17 at 360 minutes.
  - *Nothing new to unlock:* County opens at 9 minutes with the first three stars. Regional needs 5 stars and the poor bot earns no County star in 250 shifts, so it is **locked at 2 airports for the whole run**.
  - *Net-negative:* 98% of shifts. Its shift 1 to 3 pay is 20, 0 and 5 coins.
  - *Repeated airport:* 227 to 245 shifts in a row at one airport.
- **Average bot.**
  - On the `newest` policy it climbs to Mountain Field by 23 minutes and then **does nothing new for 194 minutes** until Island opens at 217 minutes. In that time it is net-negative on 95% of shifts, yet the 50% floor pays about 57 coins per shift, so the upgrades still arrive (all by 162 minutes). The grind is invisible in the coin balance.
  - On the `yield` policy it never gets past 3 stars: Grass pays better per minute than County, but Regional needs 5 stars, so **it is locked at two airports for 352 minutes**.
  - *Nothing affordable:* the longest run is 89 shifts / 160 minutes (only the expensive level 3s and cosmetics were left, against a shift that pays about 60 to 100).
- **Good bot.**
  - Never stuck for stars: International at 93 minutes.
  - Its pinch is **nothing to buy**: everything is bought by 106 to 116 minutes and the balance climbs to 18k to 25k with no use for it.
  - After that its only goals are the 17th and 18th stars. It stops improving at 17 of 18.
  - *Repeated airport:* 202 shifts at International (`newest`) or 241 at County (`yield`).

Three structural pinch points show up in every bot's run:

1. **The star gate between Grass Strip / County and Regional.** Five stars are needed, and the first airport only gives 3 for sure. A player who can't earn a County star (30 net coins) is stuck permanently. This is where the poor bot and the average `yield` bot stop.
2. **Mountain Field is a difficulty cliff.** The shift's net drops by about 400 coins compared with Regional for the average and good bots, and the airport needs 8 stars. The average bot spends 194 minutes (105 shifts) here, 95% of them net-negative.
3. **Nothing new to buy after about 2 hours** (good) or 3.5 to 4.5 hours (average).

---

## 4. Session shape

Assumptions for the first three days: day 1 is a 30-minute session, days 2 and 3 are 15 minutes each (60 minutes total), plus the daily shift each day. Daily shift bonuses are 88, 101 and 114 coins for a streak of 1, 2 and 3 (about 300 coins in all).

### 4.1 First 5 minutes

| | Poor | Average | Good |
|---|---|---|---|
| Shifts played | 2 | 3 | 3 |
| Coins earned (includes 100 per first star) | 20 | 440 to 500 | 1,130 to 1,490 |
| Stars | 0 | 3 | 8 to 9 |
| Airports open | 1 | 2 | 4 |
| Upgrade levels bought | 0 | 4 to 5 | 8 to 9 |
| What the player saw | Two Grass Strip shifts that paid 20 and 0 coins; first purchase at 7.8 min. | A three-star Grass shift, County opens, a few cheap upgrades. | Grass, County, Regional and Mountain Field in four consecutive shifts; four airports open, 8 upgrade levels. |

The first shift at each airport is gentler (intro shift). A good player meets four airports in 5 minutes; a poor player has not left the first one.

### 4.2 First 30 minutes

| | Poor | Average (newest / yield) | Good (newest / yield) |
|---|---|---|---|
| Shifts | 17 | 18 / 21 | 16 / 19 |
| Coins earned | 584 to 656 | 1,898 / 1,507 | 3,317 / 3,353 |
| Stars | 3 | 8 / 3 | 12 / 9 |
| Airports open | 2 | 4 / 2 | 5 / 4 |
| Upgrade levels | 5 to 6 | 11 / 9 | 14 / 14 |
| Cosmetics | 0 | 0 | 0 |

The poor bot has spent 25 minutes with two airports and about 6 purchases. The good bot has bought most of what exists.

### 4.3 First three days (60 minutes plus three daily shifts)

| | Poor | Average (newest / yield) | Good (newest / yield) |
|---|---|---|---|
| Shifts | 34 | 34 / 42 | 31 / 37 |
| Coins earned | 885 to 957 (+~300 daily) | 2,701 / 3,223 (+~300) | 5,503 / 5,724 (+~300) |
| Stars | 3 | 8 / 3 | 13 / 9 |
| Airports open | 2 | 4 / 2 | 5 / 4 |
| Upgrade levels | 7 | 13 / 14 | 17 / 18 |
| Cosmetics | 0 | 0 | 0 to 1 |

- **Daily bonus weight.** About 300 coins over three days is a third of the poor bot's earnings and about 5% of the good bot's. It is the only thing that pays a returning player.
- **Daily shift airport.** (Audited before the fix.) It was `day % 6` with no lock check, so a new player could be given International with 0 stars; with no upgrades even the good bot netted −136 there. It now picks among the open airports.
- **After three days.** The good bot has bought all upgrades and starts on cosmetics. The poor bot has seen two airports and 7 of 18 upgrade levels. The average bot's outcome depends on where it plays: 4 airports or 2.
- **Total in 3 days vs total content.** Everything costs 9,920 coins. By day 3 the bots have earned 9% to 58% of that (the 100-coin first-star bonuses are included in these totals).

---

## 5. Gaps against comparable mobile games

Comparable games: Flight Control and its descendants, Pocket Planes and other short-session arcade or management games with a meta layer. This is a list of what the game lacks, not a build plan.

**A reason to come back tomorrow**

- No login reward or daily calendar. The only daily hook is the daily shift, and it is a normal shift that can be done in one visit.
- No streak recovery or freeze. A missed day sets the daily and Bad Pilot Day streaks back to zero.
- No notification or reminder (none on the web build).
- No timed events, seasons or weekly rotating challenges.
- No "welcome back" summary or offline progress.
- The daily shift gives at most 166 coins at streak 7. By the time a player reaches a 7-day streak the average bot earns that in 2 shifts, so the reward is worth nothing to most players after the first week.

**Daily goals**

- No daily or weekly goals ("land 10 gliders today", "earn 300 coins at Island").
- No daily-shift variety beyond the seeded airport and traffic.

**Missions and achievements**

- No missions, quests or contracts.
- No achievements or badges: first 3-star, first jet, first emergency landing, no-fine shift, 10-landing streak, every airport at 3 stars.
- No lifetime stats page (landings, planes handled, hours played, longest streak).
- No collection goals other than buying the 5 themes and 6 liveries.

**Progression**

- Everything purchasable is gone in 1 to 4 hours for an average or good player; the coin balance then has no use.
- Star thresholds past Regional are very hard for the bot model and nothing teaches the player how to meet them. There is no hint or practice mode for the hard airports.
- Mountain Field is a difficulty cliff with nothing in between: no easier practice variant.
- Players who cannot reach 5 stars have no other way to open Regional (no coin unlock, no skip).
- No prestige or New Game+ layer (e.g. a harder "No engines" for every airport, or season resets).

**Rewards and feedback**

- A net-negative shift still pays 50% of landing pay while the star thresholds measure net, so coins and stars can disagree within one shift.
- The first-star bonus is paid once, so the 1,800 coins from stars is a one-time spike in the first hours.
- Rewarded ads exist only as stubs (refund the biggest fine, double coins).

**Social**

- No leaderboards, friends, ghosts of other players' shifts or shareable results.
- No daily-shift ranking: everyone plays the same seeded shift but can't compare scores.

**Session shape**

- A shift is 45 to 90 seconds plus about 20 seconds of menus. I found no "one more" hook on the results screen (no text naming the next unlock or the coins short of the next upgrade).
- No onboarding goal beyond the tips: the first target (3 stars on Grass Strip) is clear, the second (Regional at 5 stars) is not stated.

---

## 6. Balance phase 1: before and after

What changed (all of it in the game, tests in `tests/smoke_test.gd`):

1. **Pay floor.** A completed shift pays at least 25% of its gross (landing pay + bonuses + early bonus). Fines and overtime cut the pay down to that floor and no further; stars still use the net, so fines and crashes still count against stars 2 and 3. The results card says "Shift pay protected" when the floor is what pays. Leaving a shift from the pause menu pays nothing. (Before: 50% of landing pay.)
2. **Stars and gates.** Star 1 is finishing the shift with at least N landings: 2, 2, 4, 3, 6 and 6 for the six airports, chosen so the poor bot gets it within three shifts at least 90% of the time. Stars 2 and 3 are net coins: 40 / 70, 15 / 45, 15 / 40, 25 / 160, 35 / 345 and 125 / 360. The early airports ask little for stars 2 and 3 (a poor shift can reach them now and then, which the poor bot needs to open the next airport); Mountain Field and later ask what a good player nets. Airports open at 0, 2, 4, 7, 10 and 13 stars. The detail screen says "Land N and finish the shift" and "Net X after fines", and the shift bar counts landings toward star 1. The hangar holds N aircraft, so "Hangar full" is star 1.
3. **Mountain Field.** At most 6 aircraft (was 10), spawns every 6.5 s down to 3.8 s (was 5.2 to 2.2), timers ×1.4 (was ×1.0), speed ×0.92 (was ×1.0), fines ×0.35 (was ×1.0). Traffic mix and the five mountains are unchanged. With the nine cheapest upgrade levels the average bot nets about +10 coins per shift there (was −480) and the good bot about +94 (was −221).
4. **Fines scale** also came down at the other airports, because stars 2 and 3 cannot be reached by the average bot at Island or International while fines run at ×1.0: Grass Strip ×0.3, County ×0.3, Regional ×0.35, Island ×0.45, International ×0.45 (were ×0.4, ×0.6, ×0.8, ×1.0, ×1.0). That is more than the Mountain Field retune you asked for; it is the one change I made on my own judgement.
5. **Daily shift and Bad Pilot Day** only pick open airports.

Stars 2 and 3 against the targets (survey, nine cheapest upgrade levels, 60 shifts per cell; "90%" is the number of shifts after which the star has been reached at least once with 90% probability):

| Airport (star 1 landings, star 2, star 3) | Star 1: poor bot, N landings within 3 shifts | Star 2: average bot, chance per shift / shifts for 90% | Star 3: good bot, chance per shift / shifts for 90% |
|---|---|---|---|
| Grass Strip (2, 40, 70) | 95% | 58% / 3 | 58% / 3 |
| County (2, 15, 45) | 98% | 68% / 2 | 97% / 1 |
| Regional (4, 15, 40) | 98% | 62% / 3 | 98% / 1 |
| Mountain Field (3, 25, 160) | 90% | 48% / 4 | 20% / 11 |
| Island (6, 35, 345) | 97% | 25% / 8 | 23% / 9 |
| International (6, 125, 360) | 100% | 25% / 8 | 20% / 11 |

The average bot reaches star 2 within about 8 shifts everywhere and the good bot reaches star 3 within about 10, with Mountain Field, Island and International at the limit. The early airports are much quicker than that on purpose (see item 2).

Time to unlock each airport (minutes of play) and the share of shifts with a net at or below zero (the number the stars use), plus the share of shifts that were paid by the pay floor. 250-shift careers; each bot buys the cheapest upgrade it can afford, then cosmetics. Three ways of choosing the next airport: `newest` (the highest open one), `yield` (best coins per minute) and `chase` (the lowest open airport that still has stars to win, an airport that won nothing in its last 12 plays waits). "–" means not reached in 250 shifts.

**Before (original game, audit_sim careers of 250 shifts)**

| Bot / policy | County | Regional | Mountain Field | Island | International | Stars at the end | Shifts with net ≤ 0 | Shifts paid by the pay floor |
|---|---|---|---|---|---|---|---|---|
| Poor / newest | 9 | – | – | – | – | 3 | 98% | 100% |
| Poor / yield | 9 | – | – | – | – | 3 | 84% | 90% |
| Poor / chase | 9 | – | – | – | – | 3 | 98% | 100% |
| Average / newest | 1 | 11 | 23 | 217 | – | 12 | 95% | 98% |
| Average / yield | 1 | – | – | – | – | 3 | 32% | 48% |
| Average / chase | 1 | 11 | 46 | – | – | 9 | 84% | 94% |
| Good / newest | 1 | 3 | 4 | 8 | 93 | 17 | 46% | 68% |
| Good / yield | 1 | 3 | 4 | – | – | 9 | 11% | 23% |
| Good / chase | 1 | 6 | 7 | 72 | 206 | 18 | 75% | 90% |

**After (balance phase 1)**

| Bot / policy | County | Regional | Mountain Field | Island | International | Stars at the end | Shifts with net ≤ 0 | Shifts paid by the pay floor |
|---|---|---|---|---|---|---|---|---|
| Poor / newest | 11 | 13 | 18 | – | – | 9 | 96% | 98% |
| Poor / yield | 11 | 13 | – | – | – | 6 | 86% | 90% |
| Poor / chase | 13 | 17 | 78 | 106 | – | 12 | 96% | 98% |
| Average / newest | 1 | 3 | 4 | 6 | 14 | 16 | 41% | 62% |
| Average / yield | 1 | 4 | 5 | – | – | 8 | 34% | 46% |
| Average / chase | 1 | 3 | 5 | 10 | 38 | 18 | 48% | 76% |
| Good / newest | 1 | 3 | 4 | 6 | 8 | 16 | 4% | 10% |
| Good / yield | 1 | 3 | 4 | 6 | 8 | 16 | 8% | 18% |
| Good / chase | 1 | 3 | 4 | 6 | 29 | 18 | 0% | 6% |


Against the targets:

- **Poor bot reaches airport 4 within 4 hours: met for the fourth airport, met for the fifth only when the player goes back for stars.** Mountain Field (the fourth airport) opens at 18 minutes with `newest` and 78 with `chase`. Island (the fifth) opens at 106 minutes with `chase`, but not at all in 250 shifts with `newest` (it stops one star short, on 9 of the 10 needed, because it never goes back to an earlier airport) or `yield` (6 stars). International (13 stars) is not reached by the poor bot in any run. Before, the poor bot never got past County in 250 shifts.
- **No bot has a net-negative shift: not met, and it cannot be met by thresholds.** The pay is never negative, and it is never below 25% of the gross. But the net the stars use is still at or below zero in 96 to 98% of the poor bot's shifts (it was 84 to 98%), 41 to 48% of the average bot's with `newest` and `chase` (was 95% and 84%) and 0 to 8% of the good bot's (was 46 to 75%). The poor bot's overtime penalty alone is larger than its gross at the easy airports, and its fines at the hard ones are four to ten times its gross; making its net positive would mean removing fines for bad play. The poor bot also has 3 to 10% of shifts that pay nothing at all, because no aircraft landed and 25% of nothing is nothing.
- **Average and good bots now finish quickly.** With `chase`, the average bot has all 18 stars at 111 minutes and International open at 38; the good bot has all 18 at 37 minutes and International open at 29. Free first stars and the 0 / 2 / 4 / 7 / 10 / 13 gates did this; it is the main thing to look at next.

The simulations are `tools/audit_sim.gd` (survey and career modes) and `tools/audit_report.py` (summaries); the numbers in sections 2 to 4 are from the original game and are kept as the baseline.

## What I did not verify

- Human play. All bot numbers come from autopilots. The star-gate stall (poor bot, average `yield`) depends on those bots not earning a County star, which a person might.
- The ad stubs. They do nothing in the build, so they are listed but have no economy effect in the simulations.
- Whether the daily shift and Bad Pilot Day are blocked anywhere else in the UI for a locked airport. The code path (`start_daily`, `start_bad_day`) has no check.
- The simulation overhead of 20 s per shift is an assumption; the real figure on a phone is probably higher.
