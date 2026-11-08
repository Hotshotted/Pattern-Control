class_name Cosmetics
extends RefCounted
## Purely visual things bought with coins: airport THEMES (palette + scenery) and airline LIVERIES (tail and
## body and stripe colours (the fuselage and the stripe only: the nose, wingtips and fin always keep the runway's colour), with an animal pilot whose portrait shows up on the shop cards, the HUD and the results).
## Pure data: no Tuning / Save references.

const THEME_COUNT := 9
const LIVERY_COUNT := 23
const SOCK_COUNT := 25
const PAINT_COUNT := 37

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
	{"id": "lark", "name": "Meadow Lark", "pilot": "Captain Lark", "animal": 1, "cost": 0, "src": "level", "ap": 0, "level": 6, "from": "Grass Strip, level 6", "body": Color("f1efe0"), "stripe": Color("4f9a3a"), "quote": "Fields below, sky ahead."},
	{"id": "wren", "name": "County Wren", "pilot": "Captain Wren", "animal": 2, "cost": 0, "src": "level", "ap": 1, "level": 6, "from": "County, level 6", "body": Color("f4e9a8"), "stripe": Color("7a4a22"), "quote": "Small, quick, on the numbers."},
	{"id": "swift", "name": "Regional Swift", "pilot": "Captain Swift", "animal": 3, "cost": 0, "src": "level", "ap": 2, "level": 6, "from": "Regional, level 6", "body": Color("cfe6f7"), "stripe": Color("333a44"), "quote": "Fast and lined up."},
	{"id": "ibex", "name": "Peak Ibex", "pilot": "Captain Ibex", "animal": 4, "cost": 0, "src": "level", "ap": 3, "level": 6, "from": "Mountain Field, level 6", "body": Color("b9bcc2"), "stripe": Color("6b4a2a"), "quote": "Steady on the ridge."},
	{"id": "gull", "name": "Island Gull", "pilot": "Captain Gull", "animal": 5, "cost": 0, "src": "level", "ap": 4, "level": 6, "from": "Island, level 6", "body": Color("ffffff"), "stripe": Color("5a7a6a"), "quote": "Salt air and short rolls."},
	{"id": "eagle", "name": "Global Eagle", "pilot": "Captain Eagle", "animal": 6, "cost": 0, "src": "level", "ap": 5, "level": 6, "from": "International, level 6", "body": Color("e9e5d8"), "stripe": Color("16161c"), "quote": "Long haul, soft touch."},
]

static func theme_index(id: String) -> int:
	for i in THEME_COUNT:
		if THEMES[i]["id"] == id:
			return i
	return 0

static func livery_index(id: String) -> int:
	for i in LIVERIES.size():
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
	{"id": "sunset", "name": "Sunset sock", "cost": 0, "src": "level", "ap": 0, "level": 8, "from": "Grass Strip, level 8", "a": Color("f08a3d"), "b": Color("fbe0b0")},
	{"id": "ocean", "name": "Ocean sock", "cost": 0, "src": "level", "ap": 1, "level": 8, "from": "County, level 8", "a": Color("2f7fd0"), "b": Color("e8f3ff")},
	{"id": "berry", "name": "Berry sock", "cost": 0, "src": "level", "ap": 2, "level": 8, "from": "Regional, level 8", "a": Color("b03a7a"), "b": Color("f9e0ee")},
	{"id": "mint", "name": "Mint sock", "cost": 0, "src": "level", "ap": 3, "level": 8, "from": "Mountain Field, level 8", "a": Color("4fc7a0"), "b": Color("effff8")},
	{"id": "slate", "name": "Slate sock", "cost": 0, "src": "level", "ap": 4, "level": 8, "from": "Island, level 8", "a": Color("58667a"), "b": Color("dfe4ec")},
	{"id": "gold", "name": "Gold sock", "cost": 0, "src": "level", "ap": 5, "level": 8, "from": "International, level 8", "a": Color("e0b030"), "b": Color("fff4c8")},
	{"id": "hay", "name": "Hay sock", "cost": 30, "src": "shop", "ap": 0, "a": Color("e8c15a"), "b": Color("fff3cf")},
	{"id": "clover", "name": "Clover sock", "cost": 90, "src": "shop", "ap": 0, "a": Color("4f9a3a"), "b": Color("e9f5d8")},
	{"id": "wheat", "name": "Wheat sock", "cost": 45, "src": "shop", "ap": 1, "a": Color("d9a441"), "b": Color("fdf1d2")},
	{"id": "barn", "name": "Barn sock", "cost": 135, "src": "shop", "ap": 1, "a": Color("b5483a"), "b": Color("f6e6dc")},
	{"id": "steel2", "name": "Runway sock", "cost": 55, "src": "shop", "ap": 2, "a": Color("6d7f94"), "b": Color("e6ebf2")},
	{"id": "signal", "name": "Signal sock", "cost": 165, "src": "shop", "ap": 2, "a": Color("e0502f"), "b": Color("ffe9c9")},
	{"id": "pine2", "name": "Pine sock", "cost": 65, "src": "shop", "ap": 3, "a": Color("3f7a52"), "b": Color("e3f0e6")},
	{"id": "rock", "name": "Rock sock", "cost": 195, "src": "shop", "ap": 3, "a": Color("8a8576"), "b": Color("ece8dd")},
	{"id": "shell", "name": "Shell sock", "cost": 85, "src": "shop", "ap": 4, "a": Color("f2a58f"), "b": Color("fff0e6")},
	{"id": "lagoon2", "name": "Lagoon sock", "cost": 255, "src": "shop", "ap": 4, "a": Color("2fa7b0"), "b": Color("e2f8fa")},
	{"id": "jet", "name": "Jet sock", "cost": 100, "src": "shop", "ap": 5, "a": Color("2b3a67"), "b": Color("dfe6fa")},
	{"id": "platinum", "name": "Platinum sock", "cost": 300, "src": "shop", "ap": 5, "a": Color("aeb6c2"), "b": Color("f4f6f9")},
]
const PAINTS := [
	{"id": "standard", "name": "Airport paint", "cost": 0, "src": "shop", "color": null},
	{"id": "cream", "name": "Cream roof", "cost": 200, "src": "shop", "color": Color("efe2bd")},
	{"id": "barley", "name": "Barley roof", "cost": 0, "src": "mastery", "ap": 1, "rank": 5, "from": "County, rank 5", "color": Color("d9b44a")},
	{"id": "pine", "name": "Pine roof", "cost": 0, "src": "mastery", "ap": 3, "rank": 5, "from": "Mountain Field, rank 5", "color": Color("3f7a52")},
	{"id": "steel", "name": "Steel roof", "cost": 0, "src": "mastery", "ap": 5, "rank": 5, "from": "International, rank 5", "color": Color("6f86a0")},
	{"id": "plum", "name": "Plum roof", "cost": 0, "src": "ach", "ach": "p_imp_one", "from": "Achievement: every improvement at one airport", "color": Color("8a4f7d")},
	{"id": "teal", "name": "Teal roof", "cost": 0, "src": "ach", "ach": "p_imp_all", "from": "Achievement: every improvement everywhere", "color": Color("2f8f93")},
	{"id": "sand", "name": "Sand roof", "cost": 0, "src": "level", "ap": 0, "level": 18, "from": "Grass Strip, level 18", "color": Color("d8c79a")},
	{"id": "brick", "name": "Brick roof", "cost": 0, "src": "level", "ap": 1, "level": 18, "from": "County, level 18", "color": Color("b4533a")},
	{"id": "sage", "name": "Sage roof", "cost": 0, "src": "level", "ap": 2, "level": 18, "from": "Regional, level 18", "color": Color("8aa886")},
	{"id": "navy", "name": "Navy roof", "cost": 0, "src": "level", "ap": 3, "level": 18, "from": "Mountain Field, level 18", "color": Color("2c3e6b")},
	{"id": "rose", "name": "Rose roof", "cost": 0, "src": "level", "ap": 4, "level": 18, "from": "Island, level 18", "color": Color("d98aa0")},
	{"id": "ivory", "name": "Ivory roof", "cost": 0, "src": "level", "ap": 5, "level": 18, "from": "International, level 18", "color": Color("f3eedc")},
	{"id": "clay", "name": "Clay roof", "cost": 0, "src": "level", "ap": 0, "level": 20, "from": "Grass Strip, level 20", "color": Color("c4784f")},
	{"id": "moss", "name": "Moss roof", "cost": 0, "src": "level", "ap": 1, "level": 20, "from": "County, level 20", "color": Color("5d7a3a")},
	{"id": "sky", "name": "Cloud roof", "cost": 0, "src": "level", "ap": 2, "level": 20, "from": "Regional, level 20", "color": Color("aab9d4")},
	{"id": "ink", "name": "Ink roof", "cost": 0, "src": "level", "ap": 3, "level": 20, "from": "Mountain Field, level 20", "color": Color("353b48")},
	{"id": "lilac", "name": "Lilac roof", "cost": 0, "src": "level", "ap": 4, "level": 20, "from": "Island, level 20", "color": Color("a58fc4")},
	{"id": "amber", "name": "Amber roof", "cost": 0, "src": "level", "ap": 5, "level": 20, "from": "International, level 20", "color": Color("e0a23a")},
	{"id": "fern", "name": "Fern roof", "cost": 60, "src": "shop", "ap": 0, "color": Color("5f8f4e")},
	{"id": "sunrise", "name": "Sunrise roof", "cost": 150, "src": "shop", "ap": 0, "color": Color("e8935a")},
	{"id": "harvest", "name": "Harvest roof", "cost": 360, "src": "shop", "ap": 0, "color": Color("b8862f")},
	{"id": "cornflower", "name": "Cornflower roof", "cost": 90, "src": "shop", "ap": 1, "color": Color("6f93d1")},
	{"id": "poppy", "name": "Poppy roof", "cost": 225, "src": "shop", "ap": 1, "color": Color("d0443a")},
	{"id": "oat", "name": "Oat roof", "cost": 540, "src": "shop", "ap": 1, "color": Color("d8cfae")},
	{"id": "graphite", "name": "Graphite roof", "cost": 110, "src": "shop", "ap": 2, "color": Color("545b66")},
	{"id": "mint2", "name": "Mint roof", "cost": 275, "src": "shop", "ap": 2, "color": Color("7ec8a8")},
	{"id": "signal2", "name": "Signal roof", "cost": 660, "src": "shop", "ap": 2, "color": Color("e3a21a")},
	{"id": "alder", "name": "Alder roof", "cost": 130, "src": "shop", "ap": 3, "color": Color("7a5a3a")},
	{"id": "slate2", "name": "Slate roof", "cost": 325, "src": "shop", "ap": 3, "color": Color("647084")},
	{"id": "glacier", "name": "Glacier roof", "cost": 780, "src": "shop", "ap": 3, "color": Color("bcd6e4")},
	{"id": "coral2", "name": "Coral roof", "cost": 170, "src": "shop", "ap": 4, "color": Color("e5796b")},
	{"id": "tide", "name": "Tide roof", "cost": 425, "src": "shop", "ap": 4, "color": Color("3a8fb5")},
	{"id": "dune", "name": "Dune roof", "cost": 1020, "src": "shop", "ap": 4, "color": Color("e0c58a")},
	{"id": "onyx", "name": "Onyx roof", "cost": 200, "src": "shop", "ap": 5, "color": Color("262a33")},
	{"id": "chrome", "name": "Chrome roof", "cost": 500, "src": "shop", "ap": 5, "color": Color("b9c2cc")},
	{"id": "gold2", "name": "Gold roof", "cost": 1200, "src": "shop", "ap": 5, "color": Color("d9b54a")},
]

## The list of items of a kind ("theme", "livery", "windsock" or "hangar").
## Field props sold per airport (flower beds, a pond, a fountain): a prop shows on its airport once bought. Pure coin sinks.
const PROPS := [
	{"id": "flowers0", "name": "Flower beds", "cost": 120, "src": "shop", "ap": 0, "kind": "flowers", "color": Color("e86f9a")},
	{"id": "pond0", "name": "Duck pond", "cost": 240, "src": "shop", "ap": 0, "kind": "pond", "color": Color("4c9fd6")},
	{"id": "fountain0", "name": "Fountain", "cost": 600, "src": "shop", "ap": 0, "kind": "fountain", "color": Color("b9c4d0")},
	{"id": "flowers1", "name": "Flower beds", "cost": 180, "src": "shop", "ap": 1, "kind": "flowers", "color": Color("f2c230")},
	{"id": "pond1", "name": "Farm pond", "cost": 360, "src": "shop", "ap": 1, "kind": "pond", "color": Color("4c9fd6")},
	{"id": "fountain1", "name": "Fountain", "cost": 900, "src": "shop", "ap": 1, "kind": "fountain", "color": Color("b9c4d0")},
	{"id": "flowers2", "name": "Flower beds", "cost": 220, "src": "shop", "ap": 2, "kind": "flowers", "color": Color("a46de0")},
	{"id": "pond2", "name": "Pond", "cost": 440, "src": "shop", "ap": 2, "kind": "pond", "color": Color("4c9fd6")},
	{"id": "fountain2", "name": "Fountain", "cost": 1100, "src": "shop", "ap": 2, "kind": "fountain", "color": Color("b9c4d0")},
	{"id": "flowers3", "name": "Alpine flowers", "cost": 260, "src": "shop", "ap": 3, "kind": "flowers", "color": Color("f0f0ff")},
	{"id": "pond3", "name": "Tarn", "cost": 520, "src": "shop", "ap": 3, "kind": "pond", "color": Color("5aa6d9")},
	{"id": "fountain3", "name": "Fountain", "cost": 1300, "src": "shop", "ap": 3, "kind": "fountain", "color": Color("b9c4d0")},
	{"id": "flowers4", "name": "Beach flowers", "cost": 340, "src": "shop", "ap": 4, "kind": "flowers", "color": Color("ff8fa3")},
	{"id": "pond4", "name": "Lagoon pool", "cost": 680, "src": "shop", "ap": 4, "kind": "pond", "color": Color("3fc0d0")},
	{"id": "fountain4", "name": "Fountain", "cost": 1700, "src": "shop", "ap": 4, "kind": "fountain", "color": Color("b9c4d0")},
	{"id": "flowers5", "name": "Flower beds", "cost": 400, "src": "shop", "ap": 5, "kind": "flowers", "color": Color("ffffff")},
	{"id": "pond5", "name": "Reflecting pool", "cost": 800, "src": "shop", "ap": 5, "kind": "pond", "color": Color("4c9fd6")},
	{"id": "fountain5", "name": "Fountain", "cost": 2000, "src": "shop", "ap": 5, "kind": "fountain", "color": Color("b9c4d0")},
	{"id": "garden0", "name": "Hedge garden", "cost": 1800, "src": "shop", "ap": 0, "kind": "garden", "color": Color("5f9f4f")},
	{"id": "statue0", "name": "Statue", "cost": 3600, "src": "shop", "ap": 0, "kind": "statue", "color": Color("c9bfa8")},
	{"id": "garden1", "name": "Orchard", "cost": 2700, "src": "shop", "ap": 1, "kind": "garden", "color": Color("7fb04a")},
	{"id": "statue1", "name": "Windmill stand", "cost": 5400, "src": "shop", "ap": 1, "kind": "statue", "color": Color("d8cfb0")},
	{"id": "garden2", "name": "Rose garden", "cost": 3300, "src": "shop", "ap": 2, "kind": "garden", "color": Color("d4607a")},
	{"id": "statue2", "name": "Monument", "cost": 6600, "src": "shop", "ap": 2, "kind": "statue", "color": Color("bdc4cf")},
	{"id": "garden3", "name": "Rock garden", "cost": 3900, "src": "shop", "ap": 3, "kind": "garden", "color": Color("8f8a7c")},
	{"id": "statue3", "name": "Cairn", "cost": 7800, "src": "shop", "ap": 3, "kind": "statue", "color": Color("a9a496")},
	{"id": "garden4", "name": "Palm grove", "cost": 5100, "src": "shop", "ap": 4, "kind": "garden", "color": Color("4fb56a")},
	{"id": "statue4", "name": "Beacon stand", "cost": 10200, "src": "shop", "ap": 4, "kind": "statue", "color": Color("e6d8a8")},
	{"id": "garden5", "name": "Sculpture garden", "cost": 6000, "src": "shop", "ap": 5, "kind": "garden", "color": Color("b8c4d8")},
	{"id": "statue5", "name": "Landmark plinth", "cost": 12000, "src": "shop", "ap": 5, "kind": "statue", "color": Color("d9b54a")}
]

static func items(kind: String) -> Array:
	match kind:
		"theme": return THEMES
		"livery": return LIVERIES
		"windsock": return SOCKS
		"prop": return PROPS
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
		"level": return "Airport level: " + str(d.get("from", ""))
		"shop": return "%d coins%s" % [int(d.get("cost", 0)), (" at " + Progression.NAMES[int(d["ap"])]) if d.has("ap") else ""]
		"ach": return str(d.get("from", "Achievement"))
		_: return "%d coins" % int(d.get("cost", 0))
