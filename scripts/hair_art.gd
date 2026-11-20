extends RefCounted
## Top-down hair styles for the player, drawn like the hats (see hat_art.gd).
## Drawn in a local frame where +x is the front of the head; light stays upper-left in world space.

const FRONT := 7.8  # how far the head reaches toward the front (the face dot sits here)
const SKIN := Color("e8c9a0")

const STYLES := [
	{"name": "Bald", "kind": "bald", "col": Color("e8c9a0"), "light": Color("f4dcb8"), "dark": Color("b8946a")},
	{"name": "Short crop", "kind": "crop", "col": Color("5a3a22"), "light": Color("7a5436"), "dark": Color("3a2414")},
	{"name": "Long hair", "kind": "long", "col": Color("d9b45a"), "light": Color("f0d27c"), "dark": Color("a8843a")},
	{"name": "Ponytail", "kind": "ponytail", "col": Color("a8452a"), "light": Color("c8643e"), "dark": Color("7a2c18"), "tie": Color("2f6fb0")},
	{"name": "Mohawk", "kind": "mohawk", "col": Color("2fa89a"), "light": Color("66d8c8"), "dark": Color("1a6a60")},
	{"name": "Curly", "kind": "curly", "col": Color("2a2020"), "light": Color("4a3c3c"), "dark": Color("120c0c")},
	{"name": "Bun", "kind": "bun", "col": Color("b8b8c0"), "light": Color("dcdce4"), "dark": Color("84848e")},
]


static func count() -> int:
	return STYLES.size()


static func style_name(idx: int) -> String:
	return str(STYLES[clampi(idx, 0, STYLES.size() - 1)]["name"])


## Draws hair style `idx` on `ci` centred at `pos`, front pointing along `angle`, scaled by `s`.
static func draw(ci: CanvasItem, idx: int, pos: Vector2, angle: float, s: float = 1.0) -> void:
	var st: Dictionary = STYLES[clampi(idx, 0, STYLES.size() - 1)]
	var col: Color = st["col"]
	var light: Color = st["light"]
	var dark: Color = st["dark"]
	var hl := Vector2(-2.6, -2.6).rotated(-angle)  # world-space highlight offset
	ci.draw_set_transform(pos, angle, Vector2(s, s))
	ci.draw_circle(Vector2(2, 3).rotated(-angle), 8.4, Color(0, 0, 0, 0.3))
	match st["kind"]:
		"bald":
			_ball(ci, Vector2.ZERO, 7.6, col, light, dark, hl)
		"crop":
			_ball(ci, Vector2.ZERO, 8.2, col, light, dark, hl)
			ci.draw_arc(Vector2.ZERO, 5.4, -1.1, 1.1, 8, dark, 1.0)  # hairline
		"long":
			_blob(ci, Vector2(-5.5, 0), 10.0, 9.8, dark, col)
			_ball(ci, Vector2.ZERO, 8.2, col, light, dark, hl)
			ci.draw_line(Vector2(-1, 0), Vector2(-12, 0), dark, 0.9)  # parting
		"ponytail":
			_blob(ci, Vector2(-13.5, 0), 6.5, 3.0, dark, col)
			ci.draw_circle(Vector2(-8.6, 0), 1.6, st["tie"])
			_ball(ci, Vector2.ZERO, 8.0, col, light, dark, hl)
		"mohawk":
			_ball(ci, Vector2.ZERO, 7.4, SKIN, Color("f4dcb8"), Color("b8946a"), hl)
			_blob(ci, Vector2(-0.5, 0), 9.0, 2.9, dark, col)
			ci.draw_line(Vector2(-7, 0), Vector2(7, 0), light, 1.2)
		"curly":
			for i in 8:
				var a := TAU * float(i) / 8.0
				var c := Vector2(cos(a), sin(a)) * 6.2
				ci.draw_circle(c, 4.8, dark)
			for i in 8:
				var a2 := TAU * float(i) / 8.0 + 0.2
				ci.draw_circle(Vector2(cos(a2), sin(a2)) * 6.2 - Vector2(0.4, 0.4), 4.0, col)
			_ball(ci, Vector2.ZERO, 6.4, col, light, dark, hl)
		"bun":
			ci.draw_circle(Vector2(-7.0, 0), 4.6, dark)
			ci.draw_circle(Vector2(-7.0, 0), 3.8, col)
			ci.draw_arc(Vector2(-7.0, 0), 2.2, 0.5, 4.8, 8, dark, 0.9)
			_ball(ci, Vector2.ZERO, 8.0, col, light, dark, hl)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Rounded shape: dark base, mid tone, small lit patch, outline.
static func _ball(ci: CanvasItem, c: Vector2, r: float, col: Color, light: Color, dark: Color, hl: Vector2) -> void:
	ci.draw_circle(c, r, dark)
	ci.draw_circle(c + Vector2(-0.5, 0), r * 0.88, col)
	ci.draw_circle(c + hl * 0.9, r * 0.38, light)
	ci.draw_arc(c, r, 0.0, TAU, 20, Color(0.1, 0.07, 0.04, 0.9), 1.2)


static func _blob(ci: CanvasItem, c: Vector2, rx: float, ry: float, dark: Color, col: Color) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		outer.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		inner.append(c + Vector2(cos(a) * rx * 0.86, sin(a) * ry * 0.82))
	ci.draw_colored_polygon(outer, dark)
	ci.draw_colored_polygon(inner, col)
	outer.append(outer[0])
	ci.draw_polyline(outer, Color(0.1, 0.07, 0.04, 0.9), 1.0)
