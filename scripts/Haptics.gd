class_name Haptics
extends RefCounted
## Every buzz the game makes goes through here, so the platform's own haptic API is used the right way on each:
##   iOS     Input.vibrate_handheld(ms, amplitude): Godot drives the Taptic Engine through Core Haptics, so the strength matters (a light
##           tap is not a full buzz); a short tap is a few tens of milliseconds at 0.3 to 1.0
##   web     the browser's navigator.vibrate (Godot's own call is a no-op on some browsers)
##   others  Input.vibrate_handheld(ms) (Android's vibrator has no amplitude control we use)
## Pure statics, no autoloads. `calls` keeps what was asked for (the tests read it); `force_platform` ("ios") stands in for the device.

const LIGHT := 0.35      # a button press, a star, a path snapping on
const MEDIUM := 0.7      # a landing, a go-around, a purchase
const HEAVY := 1.0       # a fine, a crash, the results card

static var force_platform := ""        # tests: "ios", "web" or "" (the real one)
static var calls: Array = []           # [[ms, strength, platform]] (the last 64)

static func platform() -> String:
	if force_platform != "":
		return force_platform
	if OS.has_feature("web"):
		return "web"
	if OS.get_name() == "iOS":
		return "ios"
	return "other"

static func play(ms: int, strength: float = MEDIUM) -> void:
	var p := platform()
	calls.append([ms, strength, p])
	if calls.size() > 64:
		calls.pop_front()
	if force_platform != "":
		return                          # (a test: record, do not touch the device)
	match p:
		"web":
			JavaScriptBridge.eval("if (navigator.vibrate) navigator.vibrate(%d)" % ms)
		"ios":
			Input.vibrate_handheld(ms, clampf(strength, 0.05, 1.0))
		_:
			Input.vibrate_handheld(ms)
