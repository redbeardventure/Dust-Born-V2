extends RefCounted
## Top-down hair styles (no hats) for the player and NPCs, drawn like the hats (see hat_art.gd).
## Drawn in a local frame where +x is the front of the head; light stays upper-left in world space.
## Hair is a base mass plus strand lines fanning out from the crown so it reads as hair, not a ball.

const DEFAULT_FRONT := 7.8
const SKIN := Color("e8c9a0")
const OUTLINE := Color(0.1, 0.07, 0.04, 0.9)

## kind picks the drawing routine; col/light/dark are the hair tones.
## Optional: front = how far the head reaches forward, face = colour of the face dot.
const STYLES := [
	# Short brown keeps its old slot (third) so NPC heads saved in existing maps don't change.
	{"name": "Short black", "kind": "fringe", "col": Color("2a2420"), "light": Color("4d443d"), "dark": Color("110d0b")},
	{"name": "Short blonde", "kind": "fringe", "col": Color("e0b84e"), "light": Color("f8e08a"), "dark": Color("a8802c")},
	{"name": "Short brown", "kind": "fringe", "col": Color("6a4428"), "light": Color("8e6440"), "dark": Color("3a2412")},
	{"name": "Short auburn", "kind": "fringe", "col": Color("8c3a1c"), "light": Color("b85e36"), "dark": Color("4e1c0c")},
]


static func count() -> int:
	return STYLES.size()


static func style_name(idx: int) -> String:
	return str(STYLES[clampi(idx, 0, STYLES.size() - 1)]["name"])


static func front(idx: int) -> float:
	return float(STYLES[clampi(idx, 0, STYLES.size() - 1)].get("front", DEFAULT_FRONT))


static func face_color(idx: int) -> Color:
	return STYLES[clampi(idx, 0, STYLES.size() - 1)].get("face", SKIN)


## Draws hair style `idx` on `ci` centred at `pos`, front pointing along `angle`, scaled by `s`.
static func draw(ci: CanvasItem, idx: int, pos: Vector2, angle: float, s: float = 1.0) -> void:
	var st: Dictionary = STYLES[clampi(idx, 0, STYLES.size() - 1)]
	var col: Color = st["col"]
	var light: Color = st["light"]
	var dark: Color = st["dark"]
	var hl := Vector2(-2.6, -2.6).rotated(-angle)  # world-space highlight offset
	ci.draw_set_transform(pos, angle, Vector2(s, s))
	ci.draw_circle(Vector2(2, 3).rotated(-angle), 8.6, Color(0, 0, 0, 0.3))
	match st["kind"]:
		"elder":
			# Long hair streaming out behind, centre parting, a few loose flyaways.
			_blob(ci, Vector2(-7.0, 0), 12.0, 10.2, dark, col)
			_strands(ci, Vector2(-2, 0), 5.0, 20.0, 24, dark, light, 0.8)
			_scalp(ci, 8.2, col, light, dark, hl)
			_strands(ci, Vector2(-1.5, 0), 4.0, 8.0, 14, dark, light, 0.9)
			ci.draw_line(Vector2(7.0, 0), Vector2(-2, 0), Color(dark, 0.8), 1.0)
			ci.draw_line(Vector2(-12, -8), Vector2(-17, -10), Color(light, 0.8), 0.8)
			ci.draw_line(Vector2(-13, 7), Vector2(-18, 10), Color(light, 0.8), 0.8)
		"swept":
			# Shoulder-length, swept back and to one side.
			_blob(ci, Vector2(-4.0, 1.0), 10.6, 10.0, dark, col)
			_strands(ci, Vector2(0.5, -1.0), 4.0, 13.0, 20, dark, light, 0.85)
			_scalp(ci, 7.8, col, light, dark, hl)
			for i in 4:
				var y := -4.5 + float(i) * 2.6
				ci.draw_polyline(PackedVector2Array([Vector2(6.0, y * 0.5), Vector2(1.0, y), Vector2(-5.0, y + 1.8)]), Color(light if i % 2 == 0 else dark, 0.85), 0.9)
		"fringe":
			# Short hair with a side-swept fringe.
			_scalp(ci, 8.2, col, light, dark, hl)
			_strands(ci, Vector2(-2.0, 0), 3.0, 7.8, 18, dark, light, 0.95)
			for i in 4:
				var y := -4.8 + float(i) * 3.2
				ci.draw_polyline(PackedVector2Array([Vector2(1.5, y - 0.5), Vector2(5.0, y), Vector2(7.2, y + 1.6)]), Color(dark, 0.95), 1.1)
			ci.draw_line(Vector2(7.0, -3.2), Vector2(-1.0, -4.5), Color(light, 0.7), 0.9)  # side parting
		"tousled":
			# Loose medium hair, messy ends sticking out around the edge.
			_blob(ci, Vector2(-2.5, 0), 10.4, 10.6, dark, col)
			_strands(ci, Vector2(-1.0, 0), 4.0, 11.0, 22, dark, light, 0.85)
			_scalp(ci, 7.8, col, light, dark, hl)
			_strands(ci, Vector2(-1.0, 0), 3.5, 7.4, 12, dark, light, 0.9)
			for i in 7:
				var a := 0.9 + (TAU - 1.8) * float(i) / 6.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(d * 9.4, d * 12.4, Color(dark, 0.9), 0.9)
			ci.draw_line(Vector2(6.0, 2.5), Vector2(-3, 1.0), Color(dark, 0.7), 0.9)  # side parting
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Rounded scalp: dark base, mid tone, small lit patch, outline.
static func _scalp(ci: CanvasItem, r: float, col: Color, light: Color, dark: Color, hl: Vector2) -> void:
	ci.draw_circle(Vector2.ZERO, r, dark)
	ci.draw_circle(Vector2(-0.5, 0), r * 0.9, col)
	ci.draw_circle(hl * 0.9, r * 0.36, Color(light, 0.85))
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, OUTLINE, 1.2)


## Strand lines fanning out from `origin`. Strands near the front are skipped so the face stays clear.
## Length runs from `front_len` (toward the face) to `back_len` (behind the head).
static func _strands(ci: CanvasItem, origin: Vector2, front_len: float, back_len: float, n: int, dark: Color, light: Color, alpha: float) -> void:
	for i in n:
		var a := 0.7 + (TAU - 1.4) * float(i) / float(maxi(n - 1, 1))
		var dir := Vector2(cos(a), sin(a))
		var t := (1.0 - cos(a)) * 0.5
		var length := lerpf(front_len, back_len, t) * (0.9 + 0.1 * sin(float(i) * 2.7))
		var bend := dir.orthogonal() * 0.12 * length * (1.0 if i % 2 == 0 else -1.0)
		var line := PackedVector2Array([origin + dir * length * 0.25, origin + dir * length * 0.65 + bend, origin + dir * length])
		ci.draw_polyline(line, Color(light if i % 2 == 0 else dark, alpha), 0.9)


static func _blob(ci: CanvasItem, c: Vector2, rx: float, ry: float, dark: Color, col: Color) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 22:
		var a := TAU * float(i) / 22.0
		outer.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		inner.append(c + Vector2(cos(a) * rx * 0.88, sin(a) * ry * 0.84))
	ci.draw_colored_polygon(outer, dark)
	ci.draw_colored_polygon(inner, col)
	outer.append(outer[0])
	ci.draw_polyline(outer, OUTLINE, 1.0)
