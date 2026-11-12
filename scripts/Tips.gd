class_name Tips
extends RefCounted
## Every tip of the game, in one place: one short sentence, an optional icon, and when it may first appear. Each is shown once (Save.tips_seen), the first time the
## thing it is about really happens, as a small card near that thing (Main.try_tip). No shift introduces more than MAX_PER_SHIFT new ones, and `after` keeps the
## later ideas out of the first shifts (the number of shifts played before it may show). The Tips page in Settings lists the ones seen.

const MAX_PER_SHIFT := 2

## id: {"text", "icon", "after" (shifts played), "what" (shown on the Tips page when the tip is seen: the topic)}
const LIST := {
	# --- Day 1 (scripted: Tutorial.gd), also kept here so the Tips page can list them ---
	"t_draw": {"text": "Drag a path to the runway.", "icon": "plane", "after": 0, "what": "Drawing a path"},
	"t_land": {"text": "Landed planes park in the hangar. Each landing pays.", "icon": "coin", "after": 0, "what": "Landing and the hangar"},
	"t_apart": {"text": "Keep planes apart. A red ring means a crash is coming.", "icon": "plane", "after": 0, "what": "Keeping apart"},
	"t_stars": {"text": "Hit the score to earn stars.", "icon": "star", "after": 0, "what": "Stars"},
	"t_upgrade": {"text": "Coins buy upgrades. Your first one is ready: open the airport, tap Improve.", "icon": "coin", "after": 0, "what": "Upgrades"},
	"t_hold": {"text": "Press and hold the button to buy.", "icon": "coin", "after": 0, "what": "Buying (hold)"},
	# --- Just in time ---
	"drag": {"text": "Drag from an aircraft to its runway.", "icon": "plane", "after": 0, "what": "Drawing a path"},
	"wind": {"text": "Planes land into the wind. The arrow shows where it blows from.", "icon": "wind", "after": 3, "what": "Wind"},
	"fuel": {"text": "The ring is fuel: when it empties, the plane diverts and you pay a fine.", "icon": "clock", "after": 1, "what": "Fuel"},
	"goaround": {"text": "A go-around is no fine. Draw a new final and try again.", "icon": "plane", "after": 1, "what": "Go-arounds"},
	"fine": {"text": "A ticket is a fine. It cuts this shift's pay, never your bank.", "icon": "ticket", "after": 1, "what": "Fines"},
	"hangar_full": {"text": "Hangar full: planes wait on the ramp. Upgrades add bays.", "icon": "home", "after": 1, "what": "Hangar and ramp"},
	"overtime": {"text": "The clock is red: every second now costs coins.", "icon": "clock", "after": 1, "what": "Overtime"},
	"glider": {"text": "Gliders have no engine: one path, and no holding.", "icon": "glider", "after": 1, "what": "Gliders"},
	"heli": {"text": "Helicopters land on the H pad.", "icon": "heli", "after": 1, "what": "Helicopters"},
	"jet": {"text": "Jets need a long runway.", "icon": "jet", "after": 1, "what": "Jets"},
	"seaplane": {"text": "Seaplanes land on the water lane.", "icon": "seaplane", "after": 1, "what": "Seaplanes"},
	"emergency": {"text": "Flashing planes are emergencies: land them fast.", "icon": "emergency", "after": 1, "what": "Emergencies"},
	"vip": {"text": "VIPs pay a bonus: don't make them wait.", "icon": "vip", "after": 1, "what": "VIPs"},
	"student": {"text": "Students must land into the wind. Use the green end.", "icon": "student", "after": 3, "what": "Student pilots"},
	"levelup": {"text": "Level up! Every level unlocks something new.", "icon": "star", "after": 1, "what": "Airport levels"},
	"goals": {"text": "Daily goals: three small tasks for bonus coins.", "icon": "check", "after": 2, "what": "Daily goals"},
	"event": {"text": "A new event every week changes the rules.", "icon": "star", "after": 2, "what": "The weekly event"},
	"offline": {"text": "Parked planes keep earning while you are away.", "icon": "coin", "after": 0, "what": "Offline income"},
	"cosmetics": {"text": "Liveries and skins are only for looks.", "icon": "star", "after": 2, "what": "The cosmetic shop"},
	"unlock": {"text": "A new airport is open. Pick it from the airport list.", "icon": "airport", "after": 1, "what": "A new airport"},
}

static func text(id: String) -> String:
	return str(LIST[id]["text"]) if LIST.has(id) else ""

static func icon(id: String) -> String:
	return str(LIST[id]["icon"]) if LIST.has(id) else ""

static func after(id: String) -> int:
	return int(LIST[id]["after"]) if LIST.has(id) else 0

## The ids seen, in the order of LIST (for the Tips page).
static func seen_ids(seen: Dictionary) -> Array:
	var out := []
	for id in LIST:
		if seen.has(id):
			out.append(id)
	return out
