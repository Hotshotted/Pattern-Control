class_name Cosmetics
extends RefCounted
## Purely visual things bought with coins: airport THEMES (palette + scenery) and airline LIVERIES (tail and
## stripe colours, with an animal pilot whose portrait shows up on the shop cards, the HUD and the results).
## Pure data: no Tuning / Save references.

const THEME_COUNT := 5
const LIVERY_COUNT := 6

const THEMES := [
	{"id": "classic", "name": "Classic", "cost": 0, "ground": null, "tint": Color(1, 1, 1), "leaf": Color(0.2, 0.46, 0.25), "trunk": Color(0.45, 0.3, 0.18),
		"style": 0, "bg": Color(0.2, 0.26, 0.34), "ambient": Color(0.8, 0.82, 0.9), "ambient_energy": 0.5, "sun": 1.0},
	{"id": "autumn", "name": "Autumn", "cost": 300, "ground": Color(0.6, 0.5, 0.26), "tint": Color(1.0, 0.92, 0.8), "leaf": Color(0.88, 0.4, 0.1), "trunk": Color(0.4, 0.26, 0.15),
		"style": 0, "bg": Color(0.3, 0.22, 0.16), "ambient": Color(1.0, 0.88, 0.75), "ambient_energy": 0.55, "sun": 1.0},
	{"id": "desert", "name": "Desert", "cost": 500, "ground": Color(0.86, 0.73, 0.48), "tint": Color(1.0, 0.95, 0.75), "leaf": Color(0.3, 0.58, 0.32), "trunk": Color(0.3, 0.5, 0.3),
		"style": 2, "bg": Color(0.5, 0.4, 0.28), "ambient": Color(1.0, 0.93, 0.8), "ambient_energy": 0.6, "sun": 1.15},
	{"id": "winter", "name": "Winter", "cost": 700, "ground": Color(0.9, 0.93, 0.97), "tint": Color(0.85, 0.92, 1.0), "leaf": Color(0.16, 0.38, 0.32), "trunk": Color(0.35, 0.25, 0.18),
		"style": 1, "bg": Color(0.34, 0.4, 0.5), "ambient": Color(0.85, 0.9, 1.0), "ambient_energy": 0.6, "sun": 0.95},
	{"id": "night", "name": "Night", "cost": 900, "ground": Color(0.13, 0.22, 0.17), "tint": Color(0.3, 0.38, 0.6), "leaf": Color(0.07, 0.18, 0.13), "trunk": Color(0.18, 0.12, 0.08),
		"style": 1, "bg": Color(0.03, 0.04, 0.09), "ambient": Color(0.45, 0.5, 0.8), "ambient_energy": 0.42, "sun": 0.4},
]

const LIVERIES := [
	{"id": "standard", "name": "Pattern Air", "pilot": "Captain Duck", "animal": 0, "cost": 0, "tail": null, "stripe": null, "quote": "Quack. Smooth landings, please."},
	{"id": "fox", "name": "Fox Air", "pilot": "Captain Fox", "animal": 1, "cost": 200, "tail": Color(0.97, 0.97, 0.95), "stripe": Color(0.75, 0.12, 0.12), "quote": "Sly approach, perfect flare."},
	{"id": "owl", "name": "Owl Express", "pilot": "Captain Owl", "animal": 2, "cost": 300, "tail": Color(0.45, 0.3, 0.18), "stripe": Color(0.9, 0.78, 0.5), "quote": "Whoo's landing next?"},
	{"id": "penguin", "name": "Penguin Pacific", "pilot": "Captain Penguin", "animal": 3, "cost": 400, "tail": Color(0.1, 0.1, 0.14), "stripe": Color(1.0, 1.0, 1.0), "quote": "Cool as ice on final."},
	{"id": "bear", "name": "Bear Cargo", "pilot": "Captain Bear", "animal": 4, "cost": 500, "tail": Color(0.14, 0.4, 0.2), "stripe": Color(0.98, 0.85, 0.2), "quote": "Heavy loads, gentle touchdowns."},
	{"id": "cat", "name": "Cat Airways", "pilot": "Captain Cat", "animal": 5, "cost": 600, "tail": Color(0.55, 0.3, 0.75), "stripe": Color(1.0, 0.6, 0.8), "quote": "Always lands on its feet."},
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
