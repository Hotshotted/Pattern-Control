class_name Boot
extends RefCounted
## Start-up timing. Every step of the boot calls `Boot.mark("name")`; the log line (also in the browser console, and in
## `window.__boot` on the web for the timing check) says how long that step took and when it ended, in ms since the engine
## started. Costs nothing noticeable (one clock read and one print per step).

static var marks: Array = []
static var _last := 0
## How far through the start-up each step is (0..1): the loading page's bar follows it, after the download's share.
const PROGRESS := {
	"engine up, scene loaded": 0.08, "airfield ready": 0.30, "traffic: 14 ramp models": 0.42, "hud built": 0.52, "main: diorama": 0.58,
	"main: sounds loaded": 0.66, "prewarm: everything shown": 0.70, "prewarm: finished": 0.96, "menu shown": 1.0,
}

## Tell the loading page how far the start-up is.
static func progress(f: float) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__pwProgress && window.__pwProgress(%.3f)" % clampf(f, 0.0, 1.0))

static func mark(step: String) -> void:
	var now := Time.get_ticks_msec()
	var took := now - _last if _last > 0 else now
	_last = now
	marks.append([step, took, now])
	print("[boot] %-34s +%5d ms  (at %5d ms)" % [step, took, now])
	if PROGRESS.has(step):
		progress(PROGRESS[step])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(window.__boot = window.__boot || []).push([%s, %d, %d, performance.now()])" % [JSON.stringify(step), took, now])

## A step that ran from `since` (a Time.get_ticks_msec() reading) until now, when other steps happened in between.
static func span(step: String, since: int) -> void:
	var now := Time.get_ticks_msec()
	marks.append([step, now - since, now])
	print("[boot] %-34s +%5d ms  (at %5d ms)" % [step, now - since, now])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(window.__boot = window.__boot || []).push([%s, %d, %d, performance.now()])" % [JSON.stringify(step), now - since, now])
