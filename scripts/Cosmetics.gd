class_name Cosmetics
extends RefCounted
## Purely visual things bought with coins: airport THEMES (palette + scenery) and airline LIVERIES (tail and
## body and stripe colours (the fuselage and the stripe only: the nose, wingtips and fin always keep the runway's colour), with an animal pilot whose portrait shows up on the shop cards, the HUD and the results).
## Pure data: no Tuning / Save references.

const THEME_COUNT := 9
const LIVERY_COUNT := 17
const SOCK_COUNT := 7
const PAINT_COUNT := 7

## Where an item comes from: "src" is "shop" (coins, "cost"), "mastery" ("ap" and "rank": that airport's mastery rank) or "ach" ("ach": an
## achievement's id, see Achievements). "from" is the line a locked item shows. Items without a "src" are in the shop.

const THEMES := [
	{"id": "classic", "name": "Classic", "cost": 0, "ground": null, "tint": Color(1, 1, 1), "leaf": Color("3f7d3f"), "leaf_mid": Color("69a955"), "leaf_hi": Color("9ad46e"), "trunk": Color(0.45, 0.3, 0.18),
		"style": 0, "bg": Color(0.2, 0.26, 0.34), "ambient": Color(0.8, 0.82, 0.9), "ambient_energy": 0.5, "sun": 1.0},
	{"id": "autumn", "name": "Autumn", "cost": 300, "ground": Color(0.6, 0.5, 0.26), "tint": Color(1.0, 0.92, 0.8), "leaf": Color(0.88, 0.4, 0.1), "trunk": Color(0.4, 0.26, 0.15),
		"style": 0, "bg": Color(0.3, 0.22, 0.16), "ambient": Color(1.0, 0.88, 0.75), "ambient_energy": 0.55, "sun": 1.0},
	{"id": "desert", "name": "Desert", "cost": 500, "ground": Color(0.86, 0.73, 0.48), "tint": Color(1.0, 0.95, 0.75), "leaf": Color(0.3, 0.58, 0.32), "trunk": Color(0.3, 0.5, 0.3),
		"style": 2, "bg": Color(0.5, 0.4, 0.28), "ambient": Color(1.0, 0.93, 0.8), "ambient_energy": 0.6, "sun": 1.15},
	{"id": "winter", "name": "Winter", "cost": 700, "ground": Color(0.9, 0.93, 0.97), "tint": Color(0.85, 0.92, 1.0), "leaf": Color(0.16, 0.38, 0.32), "trunk": Color(0.35, 0.25, 0.18),
		"style": 1, "bg": Color(0.34, 0.4, 0.5), "ambient": Color(0.85, 0.9, 1.0), "ambient_energy": 0.6, "sun": 0.95},
	{"id": "night", "name": "Night", "cost": 900, "ground": Color(0.13, 0.22, 0.17), "tint": Color(0.3, 0.38, 0.6), "leaf": Color(0.07, 0.18, 0.13), "trunk": Color(0.18, 0.12, 0.08),
		"style": 1, "bg": Color(0.03, 0.04, 0.09), "ambient": Color(0.45, 0.5, 0.8), "ambient_energy": 0.42, "sun": 0.4},
	{"id": "spring", "name": "Spring", "cost": 450, "src": "shop", "ground": Color(0.58, 0.82, 0.42), "tint": Color(1.0, 1.0, 0.95), "leaf": Color(0.45, 0.75, 0.38), "trunk": Color(0.42, 0.3, 0.18),
		"style": 0, "bg": Color(0.24, 0.3, 0.38), "ambient": Color(0.9, 0.95, 0.9), "ambient_energy": 0.55, "sun": 1.05},
	{"id": "dusk", "name": "Dusk", "cost": 0, "src": "ach", "ach": "p_stars18", "from": "Achievement: three stars everywhere", "ground": Color(0.32, 0.36, 0.3), "tint": Color(1.0, 0.82, 0.72), "leaf": Color(0.22, 0.3, 0.26), "trunk": Color(0.25, 0.17, 0.14),
		"style": 1, "bg": Color(0.22, 0.15, 0.24), "ambient": Color(1.0, 0.72, 0.62), "ambient_energy": 0.48, "sun": 0.6},
	{"id": "blossom", "name": "Blossom", "cost": 0, "src": "ach", "ach": "p_rank5", "from": "Achievement: your first rank 5", "ground": Color(0.74, 0.8, 0.58), "tint": Color(1.0, 0.95, 0.97), "leaf": Color(0.95, 0.62, 0.72), "trunk": Color(0.4, 0.28, 0.22),
		"style": 0, "bg": Color(0.3, 0.26, 0.34), "ambient": Color(1.0, 0.92, 0.95), "ambient_energy": 0.58, "sun": 1.05},
	{"id": "lagoon", "name": "Lagoon", "cost": 0, "src": "ach", "ach": "p_rank5_all", "from": "Achievement: rank 5 at every airport", "ground": Color(0.66, 0.84, 0.78), "tint": Color(0.92, 1.0, 1.0), "leaf": Color(0.2, 0.55, 0.5), "trunk": Color(0.35, 0.28, 0.2),
		"style": 2, "bg": Color(0.2, 0.32, 0.38), "ambient": Color(0.88, 1.0, 1.0), "ambient_energy": 0.6, "sun": 1.1},
]

const LIVERIES := [
	{"id": "standard", "name": "Pattern Air", "pilot": "Captain Duck", "animal": 0, "cost": 0, "body": null, "stripe": null, "quote": "Quack. Smooth landings, please."},
	{"id": "fox", "name": "Fox Air", "pilot": "Captain Fox", "animal": 1, "cost": 200, "body": Color(0.97, 0.97, 0.95), "stripe": Color(0.75, 0.12, 0.12), "quote": "Sly approach, perfect flare."},
	{"id": "owl", "name": "Owl Express", "pilot": "Captain Owl", "animal": 2, "cost": 300, "body": Color(0.45, 0.3, 0.18), "stripe": Color(0.9, 0.78, 0.5), "quote": "Whoo's landing next?"},
	{"id": "penguin", "name": "Penguin Pacific", "pilot": "Captain Penguin", "animal": 3, "cost": 400, "body": Color(0.1, 0.1, 0.14), "stripe": Color(1.0, 1.0, 1.0), "quote": "Cool as ice on final."},
	{"id": "bear", "name": "Bear Cargo", "pilot": "Captain Bear", "animal": 4, "cost": 500, "body": Color(0.14, 0.4, 0.2), "stripe": Color(0.95, 0.9, 0.3), "quote": "Heavy loads, gentle touchdowns."},
	{"id": "cat", "name": "Cat Airways", "pilot": "Captain Cat", "animal": 5, "cost": 600, "body": Color(0.36, 0.33, 0.34), "stripe": Color(0.98, 0.94, 0.82), "quote": "Always lands on its feet."},
	{"id": "otter", "name": "Otter Air", "pilot": "Captain Otter", "animal": 6, "cost": 650, "src": "shop", "body": Color(0.9, 0.95, 0.97), "stripe": Color(0.1, 0.25, 0.5), "quote": "Smooth as river water."},
	{"id": "hawk", "name": "Hawk Express", "pilot": "Captain Hawk", "animal": 7, "cost": 800, "src": "shop", "body": Color(0.35, 0.4, 0.5), "stripe": Color(0.98, 0.88, 0.25), "quote": "Eyes on the runway."},
	{"id": "bee", "name": "Bee Line", "pilot": "Captain Bee", "animal": 8, "cost": 0, "src": "mastery", "ap": 0, "rank": 3, "from": "Grass Strip, rank 3", "body": Color(0.98, 0.88, 0.3), "stripe": Color(0.12, 0.1, 0.1), "quote": "Straight to the flower, straight to the strip."},
	{"id": "hare", "name": "Hare Post", "pilot": "Captain Hare", "animal": 9, "cost": 0, "src": "mastery", "ap": 1, "rank": 3, "from": "County, rank 3", "body": Color(0.82, 0.76, 0.66), "stripe": Color(0.55, 0.2, 0.2), "quote": "Special delivery, quick as I can."},
	{"id": "heron", "name": "Heron Regional", "pilot": "Captain Heron", "animal": 10, "cost": 0, "src": "mastery", "ap": 2, "rank": 3, "from": "Regional, rank 3", "body": Color(0.8, 0.88, 0.92), "stripe": Color(0.2, 0.35, 0.55), "quote": "Patience makes a perfect flare."},
	{"id": "goat", "name": "Goat Alpine", "pilot": "Captain Goat", "animal": 11, "cost": 0, "src": "mastery", "ap": 3, "rank": 3, "from": "Mountain Field, rank 3", "body": Color(0.93, 0.93, 0.9), "stripe": Color(0.25, 0.45, 0.3), "quote": "Mountains are just steep runways."},
	{"id": "seal", "name": "Seal Island", "pilot": "Captain Seal", "animal": 12, "cost": 0, "src": "mastery", "ap": 4, "rank": 3, "from": "Island, rank 3", "body": Color(0.55, 0.75, 0.8), "stripe": Color(0.97, 0.97, 0.9), "quote": "Splash and dash."},
	{"id": "crane", "name": "Crane Global", "pilot": "Captain Crane", "animal": 13, "cost": 0, "src": "mastery", "ap": 5, "rank": 3, "from": "International, rank 3", "body": Color(0.97, 0.97, 0.97), "stripe": Color(0.2, 0.2, 0.3), "quote": "Long legs, long haul."},
	{"id": "raven", "name": "Raven Night", "pilot": "Captain Raven", "animal": 14, "cost": 0, "src": "ach", "ach": "s_fast_hangar", "from": "Achievement: fill the hangar in 45 seconds", "body": Color(0.12, 0.12, 0.18), "stripe": Color(0.85, 0.85, 0.95), "quote": "Quoth the tower: cleared to land."},
	{"id": "panda", "name": "Panda Pacific", "pilot": "Captain Panda", "animal": 15, "cost": 0, "src": "ach", "ach": "s_locked10", "from": "Achievement: ten locked finals in a row", "body": Color(0.96, 0.96, 0.96), "stripe": Color(0.1, 0.1, 0.1), "quote": "Calm and steady."},
	{"id": "lion", "name": "Lion Gold", "pilot": "Captain Lion", "animal": 16, "cost": 0, "src": "ach", "ach": "a_l1000", "from": "Achievement: 1,000 landings", "body": Color(0.78, 0.7, 0.5), "stripe": Color(0.45, 0.25, 0.12), "quote": "The pride of the pattern."},
]

static func theme_index(id: String) -> int:
	for i in THEME_COUNT:
		if THEMES[i]["id"] == id:
			return i
	return 0

static func livery_index(id: String) -> int:
	for i in LIVERY_COUNT:
		if LIVERIES[i]["id"] == id:
			return i
	return 0

## The windsock colours (the stripes, a pair) and hangar paint (the roof): "field details" shown on every airport. Index 0 is the standard one.
const SOCKS := [
	{"id": "standard", "name": "Orange sock", "cost": 0, "src": "shop", "a": Color("ff6a3d"), "b": Color(0.97, 0.97, 0.95)},
	{"id": "lime", "name": "Lime sock", "cost": 150, "src": "shop", "a": Color("8fd14f"), "b": Color(0.97, 0.97, 0.95)},
	{"id": "meadow", "name": "Meadow sock", "cost": 0, "src": "mastery", "ap": 0, "rank": 5, "from": "Grass Strip, rank 5", "a": Color("5aa84a"), "b": Color("f6e27a")},
	{"id": "sky", "name": "Sky sock", "cost": 0, "src": "mastery", "ap": 2, "rank": 5, "from": "Regional, rank 5", "a": Color("4f9fe0"), "b": Color(0.97, 0.97, 0.95)},
	{"id": "coral", "name": "Coral sock", "cost": 0, "src": "mastery", "ap": 4, "rank": 5, "from": "Island, rank 5", "a": Color("f08a8a"), "b": Color("fbe9d0")},
	{"id": "rainbow", "name": "Rainbow sock", "cost": 0, "src": "ach", "ach": "a_l5000", "from": "Achievement: 5,000 landings", "a": Color("c05ad8"), "b": Color("f2d83a")},
	{"id": "midnight", "name": "Midnight sock", "cost": 0, "src": "ach", "ach": "s_noeng_intl", "from": "Achievement: No engines at International", "a": Color("27356b"), "b": Color("c8d2f0")},
]
const PAINTS := [
	{"id": "standard", "name": "Airport paint", "cost": 0, "src": "shop", "color": null},
	{"id": "cream", "name": "Cream roof", "cost": 200, "src": "shop", "color": Color("efe2bd")},
	{"id": "barley", "name": "Barley roof", "cost": 0, "src": "mastery", "ap": 1, "rank": 5, "from": "County, rank 5", "color": Color("d9b44a")},
	{"id": "pine", "name": "Pine roof", "cost": 0, "src": "mastery", "ap": 3, "rank": 5, "from": "Mountain Field, rank 5", "color": Color("3f7a52")},
	{"id": "steel", "name": "Steel roof", "cost": 0, "src": "mastery", "ap": 5, "rank": 5, "from": "International, rank 5", "color": Color("6f86a0")},
	{"id": "plum", "name": "Plum roof", "cost": 0, "src": "ach", "ach": "p_imp_one", "from": "Achievement: every improvement at one airport", "color": Color("8a4f7d")},
	{"id": "teal", "name": "Teal roof", "cost": 0, "src": "ach", "ach": "p_imp_all", "from": "Achievement: every improvement everywhere", "color": Color("2f8f93")},
]

## The list of items of a kind ("theme", "livery", "windsock" or "hangar").
static func items(kind: String) -> Array:
	match kind:
		"theme": return THEMES
		"livery": return LIVERIES
		"windsock": return SOCKS
		_: return PAINTS

static func index_of(kind: String, id: String) -> int:
	var list := items(kind)
	for i in list.size():
		if list[i]["id"] == id:
			return i
	return 0

static func source(d: Dictionary) -> String:
	return str(d.get("src", "shop"))

## What a locked item says about where it comes from: its price, or the rank or achievement that gives it.
static func source_line(d: Dictionary) -> String:
	match source(d):
		"mastery": return "Mastery: " + str(d.get("from", ""))
		"ach": return str(d.get("from", "Achievement"))
		_: return "%d coins" % int(d.get("cost", 0))
