class_name DebugFlags
extends RefCounted
## Debug switches, read from the page URL on web (or "--flag=value" user args elsewhere), so a
## suspected cause of a hitch can be switched off from a phone without a new build:
##   ?nofx=burst,ripple,popup,haptic,glow,hold,sound   turn those effects off ("all" = every one)
##   ?noprewarm                                  skip the start-up pre-warm and splash
##   ?perf                                       show a worst-frame-time readout
##   ?tune                                       show the on-screen tuning panel (TUNE button, top-right)
##   ?god                                        planes never collide or run dry (to look at the traffic)
##   ?debug                                      show the build stamp (it also shows with ?tune and ?perf)
## Combine with "&", e.g.  ?perf&tune. The active flags are printed under the build stamp.

const EFFECTS := ["burst", "ripple", "popup", "haptic", "glow", "hold", "sound"]

static var _loaded := false
static var _off := {}                  # effect name -> true
static var _bad: Array[String] = []    # unknown names (typos), shown in the summary
static var noprewarm := false
static var perf := false
static var tune := false
static var god := false
static var debug := false

## True if the named effect has been switched off.
static func off(effect: String) -> bool:
	_load()
	return _off.has(effect)

static func prewarm_enabled() -> bool:
	_load()
	return not noprewarm

static func perf_enabled() -> bool:
	_load()
	return perf

static func tune_enabled() -> bool:
	_load()
	return tune

## The build stamp is only for people debugging: ?debug, ?tune or ?perf.
static func stamp_enabled() -> bool:
	_load()
	return debug or tune or perf

static func god_enabled() -> bool:
	_load()
	return god

## One-line description of the active flags ("" when none), shown next to the build stamp.
static func summary() -> String:
	_load()
	var parts: Array[String] = []
	if not _off.is_empty():
		var names: Array[String] = []
		for e in EFFECTS:
			if _off.has(e):
				names.append(e)
		parts.append("nofx=" + ",".join(names))
	if noprewarm:
		parts.append("noprewarm")
	if perf:
		parts.append("perf")
	if tune:
		parts.append("tune")
	if god:
		parts.append("god")
	if debug:
		parts.append("debug")
	for b in _bad:
		parts.append("?" + b)
	return " ".join(parts)

static func _load() -> void:
	if _loaded:
		return
	var args: Array[String] = []
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search")
		if q is String:
			for part in (q as String).trim_prefix("?").split("&", false):
				args.append(part)
	for a in OS.get_cmdline_user_args():
		args.append(a.trim_prefix("--"))
	parse(args)

## Parse "key" / "key=value" strings. Public so tests can feed it.
static func parse(args: Array[String]) -> void:
	_loaded = true
	_off.clear()
	_bad.clear()
	noprewarm = false
	perf = false
	tune = false
	god = false
	debug = false
	for a in args:
		var kv := a.split("=", true, 1)
		var key := kv[0].uri_decode().to_lower()
		var val := kv[1].uri_decode().to_lower() if kv.size() > 1 else ""
		match key:
			"nofx":
				for name in val.split(",", false):
					if name == "all":
						for e in EFFECTS:
							_off[e] = true
					elif EFFECTS.has(name):
						_off[name] = true
					else:
						_bad.append(name)
			"noprewarm":
				noprewarm = true
			"perf":
				perf = true
			"tune":
				tune = true
			"god":
				god = true
			"debug":
				debug = true
			"v":
				pass  # cache-busting parameter added by the page, not a flag
			_:
				_bad.append(key)
