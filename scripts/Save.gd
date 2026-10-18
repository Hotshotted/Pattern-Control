extends Node
## The only thing that persists: the best score. Registered as the autoload `Save`.
## (On the web, user:// lives in the browser's IndexedDB.)

var path := "user://pattern_work.json"
var best := 0

func _ready() -> void:
	load_file()

func load_file() -> void:
	best = 0
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		best = int(data.get("best", 0))

func write_file() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"version": 1, "best": best}))

## Record a finished run's score. Returns true if it is a new best.
func submit(score: int) -> bool:
	if score > best:
		best = score
		write_file()
		return true
	return false

func reset_all() -> void:
	best = 0
	write_file()
