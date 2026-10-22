class_name Portraits
extends RefCounted
## Low-poly animal pilot portraits, drawn with a few circles and triangles onto any CanvasItem.
## Animals: 0 duck, 1 fox, 2 owl, 3 penguin, 4 bear, 5 cat. Fixed scratch arrays: nothing is allocated per draw.

static var _tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

static func _poly(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	_tri[0] = a
	_tri[1] = b
	_tri[2] = c
	ci.draw_colored_polygon(_tri, col)

## Draw a portrait centred on `c` with radius `r`.
static func draw(ci: CanvasItem, c: Vector2, r: float, animal: int) -> void:
	var fur: Color = [Color(1.0, 0.85, 0.2), Color(0.95, 0.5, 0.15), Color(0.62, 0.45, 0.3), Color(0.12, 0.13, 0.18), Color(0.5, 0.33, 0.2), Color(0.55, 0.55, 0.62)][animal]
	var face: Color = [Color(1.0, 0.85, 0.2), Color(1.0, 0.95, 0.9), Color(0.92, 0.85, 0.7), Color(0.97, 0.97, 0.97), Color(0.72, 0.55, 0.38), Color(0.95, 0.9, 0.9)][animal]
	ci.draw_circle(c, r + 3.0, Style.INK)
	# Ears / tufts behind the head.
	match animal:
		1, 5:   # fox, cat: pointed ears
			_poly(ci, c + Vector2(-r * 0.95, -r * 0.2), c + Vector2(-r * 0.35, -r * 0.95), c + Vector2(-r * 0.1, -r * 0.55), fur)
			_poly(ci, c + Vector2(r * 0.95, -r * 0.2), c + Vector2(r * 0.35, -r * 0.95), c + Vector2(r * 0.1, -r * 0.55), fur)
		2:      # owl: ear tufts
			_poly(ci, c + Vector2(-r * 0.9, -r * 0.35), c + Vector2(-r * 0.7, -r * 1.05), c + Vector2(-r * 0.3, -r * 0.7), fur)
			_poly(ci, c + Vector2(r * 0.9, -r * 0.35), c + Vector2(r * 0.7, -r * 1.05), c + Vector2(r * 0.3, -r * 0.7), fur)
		4:      # bear: round ears
			ci.draw_circle(c + Vector2(-r * 0.7, -r * 0.7), r * 0.32, fur)
			ci.draw_circle(c + Vector2(r * 0.7, -r * 0.7), r * 0.32, fur)
	ci.draw_circle(c, r, fur)
	ci.draw_circle(c + Vector2(0, r * 0.18), r * 0.72, face)          # the lighter face
	# Eyes.
	var ey := c + Vector2(0, -r * 0.1)
	for s in [-1.0, 1.0]:
		var e: Vector2 = ey + Vector2(s * r * 0.32, 0)
		ci.draw_circle(e, r * (0.2 if animal == 2 else 0.13), Color.WHITE)
		ci.draw_circle(e + Vector2(0, r * 0.02), r * (0.1 if animal == 2 else 0.07), Style.INK)
	# Beak / muzzle.
	match animal:
		0, 3:   # duck, penguin: an orange beak
			_poly(ci, c + Vector2(-r * 0.22, r * 0.25), c + Vector2(r * 0.22, r * 0.25), c + Vector2(0, r * 0.52), Color(1.0, 0.55, 0.1))
		2:      # owl: small beak
			_poly(ci, c + Vector2(-r * 0.1, r * 0.2), c + Vector2(r * 0.1, r * 0.2), c + Vector2(0, r * 0.45), Color(0.95, 0.7, 0.2))
		_:      # a snout and nose
			ci.draw_circle(c + Vector2(0, r * 0.38), r * 0.22, Color(0.98, 0.93, 0.88))
			ci.draw_circle(c + Vector2(0, r * 0.3), r * 0.08, Color(0.1, 0.1, 0.12))
	# The pilot's cap.
	_poly(ci, c + Vector2(-r * 0.85, -r * 0.45), c + Vector2(r * 0.85, -r * 0.45), c + Vector2(0, -r * 1.05), Color(0.12, 0.2, 0.42))
	ci.draw_rect(Rect2(c.x - r * 0.9, c.y - r * 0.5, r * 1.8, r * 0.14), Color(0.08, 0.13, 0.3))
	ci.draw_circle(c + Vector2(0, -r * 0.7), r * 0.1, Color(1.0, 0.82, 0.2))
