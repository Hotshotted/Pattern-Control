class_name Report
extends RefCounted
## "Report a problem" (pause menu, for everyone): a text block with the build, the airport, the level, the coins and the last 20 game events, copied to
## the clipboard and ready to paste into a message, plus a screenshot saved next to it (on the web it downloads as a picture file, since a picture
## cannot ride in text). The event log is a small ring: Main._note_event feeds it.

const KEEP := 20

static var events: Array[String] = []
static var last_shot_path := ""         # where the last screenshot went (the file's name on a download)
static var last_text := ""              # what was last copied (the tests read it)

## One line in the log, stamped with the shift's clock when a shift is running.
static func log_event(text: String, shift_time: float = -1.0) -> void:
	var stamp := "%5.1fs" % shift_time if shift_time >= 0.0 else "  menu"
	events.append("%s  %s" % [stamp, text])
	while events.size() > KEEP:
		events.pop_front()

## The block to paste. `ctx` comes from Main.report_context().
static func build_text(ctx: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("PATTERN WORK REPORT")
	lines.append("build: %s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME])
	lines.append("device: %s, %s, screen %s" % [OS.get_name(), str(ctx.get("renderer", "")), str(ctx.get("screen_size", ""))])
	lines.append("airport: %s  (level %d)" % [str(ctx.get("airport", "")), int(ctx.get("level", 1))])
	lines.append("coins: %d    shifts played: %d    stars: %d" % [int(ctx.get("coins", 0)), int(ctx.get("shifts", 0)), int(ctx.get("stars", 0))])
	lines.append("screen: %s" % str(ctx.get("where", "")))
	if str(ctx.get("shift", "")) != "":
		lines.append("shift: %s" % str(ctx.get("shift", "")))
	lines.append("last %d events:" % events.size())
	for e in events:
		lines.append("  " + e)
	if last_shot_path != "":
		lines.append("screenshot: %s (attach it)" % last_shot_path)
	return "\n".join(lines)

## Save a picture of the screen as it is now. Returns the file name ("" if the picture could not be taken).
static func save_screenshot(vp: Viewport) -> String:
	if DisplayServer.get_name() == "headless":          # (the tests and the checks draw nothing: there is no picture to take)
		return ""
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return ""
	var w := mini(img.get_width(), 780)
	if img.get_width() > w:
		img.resize(w, int(float(img.get_height()) * float(w) / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	var name := "pattern_work_report_%d.png" % Save.now_unix()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), name, "image/png")
		return name + " (downloaded)"
	var path := "user://" + name
	img.save_png(path)
	return ProjectSettings.globalize_path(path)

## The whole action: picture, text, clipboard. Returns the text.
static func send(vp: Viewport, ctx: Dictionary) -> String:
	last_shot_path = save_screenshot(vp)
	last_text = build_text(ctx)
	DisplayServer.clipboard_set(last_text)
	return last_text
