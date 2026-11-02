#!/usr/bin/env python3
"""Make an older checkout readable by tools/ui_overlap_check.gd: the same text recorder the Hud now has (every draw_string / draw_multiline_string /
draw_set_transform / draw_style_box / glyph call of the drawn interface goes through a helper that notes its rectangle), added to a copy of the
old scripts. Used once, to run the audit over the game as it was before the fixes (docs/ui_audit.md, "How the before numbers were made").
   python3 tools/ui_audit_instrument.py <checkout dir>
It edits scripts/Hud.gd and scripts/Style.gd of that checkout in place."""
import sys

root = sys.argv[1]
hp = root + "/scripts/Hud.gd"
sp = root + "/scripts/Style.gd"
s = open(hp).read()
a = s.index("class Art extends Control:")
b = s.index("class SplashDraw extends Control:")
art = s[a:b]
art = art.replace("draw_string(", "_ds(").replace("draw_multiline_string(", "_dms(").replace("draw_set_transform(", "_dst(").replace("draw_style_box(", "_dsb(")
helper = '''
	# ---------- the audit's recorder ----------
	var rec_on := false
	var rec_texts: Array = []
	var rec_glyphs: Array = []
	var rec_boxes: Array = []
	var rec_xf := Transform2D.IDENTITY

	func _dst(pos: Vector2, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> void:
		rec_xf = Transform2D(rot, scl, 0.0, pos)
		draw_set_transform(pos, rot, scl)

	func _dsb(sb: StyleBox, r: Rect2) -> void:
		if rec_on:
			rec_boxes.append(rec_xf * r)
		draw_style_box(sb, r)

	func _ds(f: Font, pos: Vector2, s: String, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, size_px: int = 16, col: Color = Color.WHITE) -> void:
		if rec_on and s != "" and col.a > 0.05:
			rec_text(f, pos, s, align, width, size_px, 1)
		draw_string(f, pos, s, align, width, size_px, col)

	func _dms(f: Font, pos: Vector2, s: String, align: int, width: float, size_px: int, max_lines: int, col: Color = Color.WHITE) -> void:
		if rec_on and s != "" and col.a > 0.05:
			rec_text(f, pos, s, align, width, size_px, max_lines)
		draw_multiline_string(f, pos, s, align, width, size_px, max_lines, col)

	func _has_descender(s: String) -> bool:
		for ch in "gjpqyQ,;()":
			if s.contains(ch):
				return true
		return false

	func rec_text(f: Font, pos: Vector2, s: String, align: int, width: float, size_px: int, max_lines: int) -> void:
		var asc := f.get_ascent(size_px)
		var h := asc + f.get_descent(size_px)
		var nat := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		var lines := 1
		var tw := nat
		if max_lines > 1 and width > 0.0:
			var ms := f.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, size_px, -1)
			lines = maxi(roundi(ms.y / maxf(f.get_height(size_px), 1.0)), 1)
			tw = minf(nat, width) if lines > 1 else nat
		var x0 := pos.x
		if width > 0.0:
			match align:
				HORIZONTAL_ALIGNMENT_CENTER:
					x0 = pos.x + (width - tw) * 0.5
				HORIZONTAL_ALIGNMENT_RIGHT:
					x0 = pos.x + width - tw
		var over := (width > 0.0 and max_lines <= 1 and nat > width + 0.5) or (max_lines > 1 and lines > max_lines)
		var nl := float(mini(lines, maxi(max_lines, 1)))
		var ink_top := pos.y - 0.74 * float(size_px)
		var ink_bot := pos.y + (h - asc) * (nl - 1.0) + float(size_px) * (0.22 if _has_descender(s) else 0.04)
		var rr := rec_xf * Rect2(x0, ink_top, tw, maxf(ink_bot - ink_top, 4.0))
		rec_texts.append({"text": s, "rect": rr, "size": roundi(float(size_px) * rec_xf.get_scale().y), "limit": width * rec_xf.get_scale().x, "natural": nat * rec_xf.get_scale().x, "over": over})
'''
k = art.index("	# ---------- text ----------")
art = art[:k] + helper.lstrip("\n") + "\n" + art[k:]
art = art.replace('''	func glyph(id: String, c: Vector2, r: float, col: Color = Color.WHITE) -> void:
		var w := maxf(r * 0.16, 3.0)''', '''	func glyph(id: String, c: Vector2, r: float, col: Color = Color.WHITE) -> void:
		if rec_on and col.a > 0.05:
			var gr := r * (1.0 if id == "coin" or id == "star" or id == "star_off" else 0.8)
			rec_glyphs.append({"id": id, "rect": rec_xf * Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0)})
		var w := maxf(r * 0.16, 3.0)''', 1)
art = art.replace('''	func _draw() -> void:
		var t_start := Time.get_ticks_usec()
		_draw_all()''', '''	func _draw() -> void:
		var t_start := Time.get_ticks_usec()
		if rec_on:
			rec_texts.clear()
			rec_glyphs.clear()
			rec_boxes.clear()
			rec_xf = Transform2D.IDENTITY
		_draw_all()''', 1)
s = s[:a] + art + s[b:]
open(hp, "w").write(s)

t = open(sp).read()
t = t.replace("static func set_safe(top: float", '''static var px_per_pt := 2.77
const TAP_PT := 44.0
const MIN_TEXT := 22

static func tap_px() -> float:
	return TAP_PT * px_per_pt

static func set_safe(top: float''', 1)
t = t.replace('''	var f := display()
	var step := maxf(size_px / 28.0, 1.5)''', '''	var f := display()
	if ci.has_method("rec_text") and ci.get("rec_on"):
		ci.rec_text(f, pos, s, align, width, size_px, 1)
	var step := maxf(size_px / 28.0, 1.5)''', 1)
t = t.replace('''		var col := Color(ACCENT if k == 1 else TEXT, a)
		ci.draw_string_outline(f, Vector2(x, y), STUDIO_WORDS[k]''', '''		var col := Color(ACCENT if k == 1 else TEXT, a)
		if ci.has_method("rec_text") and ci.get("rec_on"):
			ci.rec_text(f, Vector2(x, y), STUDIO_WORDS[k], HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, 1)
		ci.draw_string_outline(f, Vector2(x, y), STUDIO_WORDS[k]''', 1)
open(sp, "w").write(t)
print("instrumented", root)
