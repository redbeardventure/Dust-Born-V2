class_name FenceNode
extends Node2D
## Draws a fence along a polyline. `variant` is a wall style key ("fence", "fence_iron", ...).
## Looks: wooden rail, capped posts, iron rail, cube posts, ball posts, stone panels, low stone.

var points := PackedVector2Array()
var closed := false
var width := 4.0
var variant := "fence"

const SHADOW_OFFSET := Vector2(3, 5)

## kind: how posts are drawn ("square", "cap", "pyramid", "hex", "ball", "panel", "rubble").
## gap: distance between posts (px). post: half size of a post in multiples of `width`.
const LOOKS := {
	"fence": {"kind": "square", "gap": 30.0, "post": 0.9, "rail": Color(0.5, 0.35, 0.2), "hi": Color(0.66, 0.5, 0.3),
			"post_col": Color(0.62, 0.45, 0.27), "post_hi": Color(0.74, 0.58, 0.36), "edge": Color(0.1, 0.06, 0.03)},
	"fence_cap": {"kind": "cap", "gap": 70.0, "post": 1.3, "rail": Color(0.5, 0.3, 0.28), "hi": Color(0.62, 0.4, 0.36),
			"post_col": Color(0.55, 0.43, 0.38), "post_hi": Color(0.7, 0.58, 0.52), "edge": Color(0.14, 0.08, 0.07)},
	"fence_iron": {"kind": "pyramid", "gap": 90.0, "post": 1.5, "rail": Color(0.29, 0.31, 0.4), "hi": Color(0.4, 0.42, 0.52),
			"post_col": Color(0.5, 0.52, 0.62), "post_hi": Color(0.62, 0.64, 0.74), "edge": Color(0.08, 0.08, 0.12)},
	"fence_cube": {"kind": "hex", "gap": 90.0, "post": 1.7, "rail": Color(0.3, 0.31, 0.42), "hi": Color(0.4, 0.42, 0.54),
			"post_col": Color(0.4, 0.42, 0.55), "post_hi": Color(0.6, 0.62, 0.74), "edge": Color(0.08, 0.08, 0.12)},
	"fence_ball": {"kind": "ball", "gap": 60.0, "post": 1.1, "rail": Color(0.24, 0.4, 0.34), "hi": Color(0.34, 0.52, 0.45),
			"post_col": Color(0.3, 0.46, 0.4), "post_hi": Color(0.55, 0.72, 0.64), "edge": Color(0.07, 0.14, 0.11)},
	"fence_panel": {"kind": "panel", "gap": 100.0, "post": 1.5, "rail": Color(0.55, 0.56, 0.66), "hi": Color(0.66, 0.67, 0.77),
			"post_col": Color(0.5, 0.52, 0.62), "post_hi": Color(0.64, 0.66, 0.76), "edge": Color(0.1, 0.1, 0.15)},
	"fence_rubble": {"kind": "rubble", "gap": 0.0, "post": 0.0, "rail": Color(0.55, 0.56, 0.63), "hi": Color(0.68, 0.69, 0.76),
			"post_col": Color(0.5, 0.51, 0.58), "post_hi": Color(0.68, 0.69, 0.76), "edge": Color(0.13, 0.13, 0.17)},
}


func _ready() -> void:
	queue_redraw()


func _path() -> PackedVector2Array:
	var p := PackedVector2Array(points)
	if closed and p.size() > 2:
		p.append(p[0])
	return p


func _draw() -> void:
	if points.size() < 2:
		return
	var look: Dictionary = LOOKS.get(variant, LOOKS["fence"])
	var path := _path()
	draw_set_transform(SHADOW_OFFSET)
	_draw_fence(path, look, true)
	draw_set_transform(Vector2.ZERO)
	_draw_fence(path, look, false)


func _draw_fence(path: PackedVector2Array, look: Dictionary, shadow: bool) -> void:
	var kind: String = look["kind"]
	var edge: Color = look["edge"]
	var shade := MapData.shadow_color(0.25)
	if kind == "rubble":
		_draw_rubble(path, look, shadow)
		return
	var posts := _posts(path, float(look["gap"]))
	var half := maxf(width * float(look["post"]), 3.0)
	if kind == "panel":
		# Thin dark bar joining the posts, with stone slabs along it.
		draw_polyline(path, shade if shadow else edge, width * 0.6 + 2.0)
		if not shadow:
			draw_polyline(path, look["post_col"], width * 0.35)
		var n := posts.size()
		for i in (n if closed else n - 1):
			var a: Vector2 = posts[i][0]
			var b: Vector2 = posts[(i + 1) % n][0]
			var span := a.distance_to(b)
			var d := (b - a) / maxf(span, 0.01)
			var inner := span - 2.0 * (half + 2.0)
			if inner < 12.0:
				continue
			var gap := 4.0
			var slab := (inner - 2.0 * gap) / 3.0
			for k in 3:
				var s := a + d * (half + 2.0 + float(k) * (slab + gap))
				var e := s + d * slab
				if shadow:
					draw_line(s, e, shade, width + 2.0)
				else:
					draw_line(s, e, edge, width + 2.0)
					draw_line(s, e, look["rail"], width)
					draw_line(s, e, look["hi"], width * 0.35)
	elif shadow:
		draw_polyline(path, shade, width + 2.0)
	else:
		draw_polyline(path, edge, width + 2.0)
		draw_polyline(path, look["rail"], width)
		draw_polyline(path, look["hi"], width * 0.35)
	for p in posts:
		_draw_post(p[0], p[1], half, kind, look, shadow)


## Post positions and the direction of the segment they sit on: [[pos, dir], ...].
## Posts sit on every corner and end, with evenly spaced ones between (about `gap` apart).
func _posts(path: PackedVector2Array, gap: float) -> Array:
	var out: Array = []
	var segs := path.size() - 1
	for i in segs:
		var a := path[i]
		var b := path[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.01:
			continue
		var d := (b - a) / seg_len
		var spans := maxi(1, roundi(seg_len / gap))
		for k in spans:
			out.append([a + d * (seg_len * float(k) / float(spans)), d])
	if not closed:
		var last := path.size() - 1
		var d_last := (path[last] - path[last - 1]).normalized()
		out.append([path[last], d_last])
	return out


func _draw_post(c: Vector2, d: Vector2, h: float, kind: String, look: Dictionary, shadow: bool) -> void:
	var edge: Color = look["edge"]
	var col: Color = look["post_col"]
	var hi: Color = look["post_hi"]
	var shade := MapData.shadow_color(0.25)
	var n := d.orthogonal()
	if kind == "ball":
		var r := h * 1.15
		if shadow:
			draw_circle(c, r, shade)
			return
		draw_circle(c, r + 1.0, edge)
		draw_circle(c, r, col)
		draw_circle(c - Vector2(r * 0.3, r * 0.3), r * 0.38, hi)
		return
	if kind == "hex":
		var hex := PackedVector2Array()
		for i in 6:
			hex.append(c + Vector2.from_angle(deg_to_rad(30.0 + 60.0 * i)) * h * 1.25)
		if shadow:
			draw_colored_polygon(hex, shade)
			return
		var outer := PackedVector2Array()
		for i in 6:
			outer.append(c + Vector2.from_angle(deg_to_rad(30.0 + 60.0 * i)) * (h * 1.25 + 1.0))
		draw_colored_polygon(outer, edge)
		draw_colored_polygon(hex, col)
		# Top face of the cube: the upper rhombus, lighter.
		draw_colored_polygon(PackedVector2Array([hex[4], hex[5], hex[0], c]), hi)
		draw_colored_polygon(PackedVector2Array([hex[3], hex[4], c]), col.lightened(0.15))
		return
	var sq := PackedVector2Array([c - d * h - n * h, c + d * h - n * h, c + d * h + n * h, c - d * h + n * h])
	if shadow:
		draw_colored_polygon(sq, shade)
		return
	draw_colored_polygon(_grow(sq, c, 1.0), edge)
	draw_colored_polygon(sq, col)
	if kind == "pyramid":
		var q := h * 0.5
		draw_colored_polygon(PackedVector2Array([c - d * q - n * q, c + d * q - n * q, c + d * q + n * q, c - d * q + n * q]), hi)
	elif kind == "cap":
		# Pitched cap seen from above: a lighter triangle on one side.
		draw_colored_polygon(PackedVector2Array([c - d * h - n * h, c + d * h - n * h, c]), hi)
		draw_colored_polygon(PackedVector2Array([c - d * h + n * h, c - d * h - n * h, c]), col.darkened(0.12))
	else:
		draw_colored_polygon(PackedVector2Array([c - d * h - n * h, c + d * h - n * h, c + d * h, c - d * h]), hi)


## `poly` pushed outwards from `c` by `by` px (for outlines).
static func _grow(poly: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * by)
	return out


## A low, rough stone wall: overlapping cobbles along the path.
func _draw_rubble(path: PackedVector2Array, look: Dictionary, shadow: bool) -> void:
	var edge: Color = look["edge"]
	var shade := MapData.shadow_color(0.25)
	var r := width * 0.55
	var step := maxf(r * 1.5, 6.0)
	if shadow:
		draw_polyline(path, shade, width + 2.0)
		return
	draw_polyline(path, edge, width * 0.8)  # dark core so no gaps show between stones
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(variant) + int(path[0].x * 31.0) + int(path[0].y * 17.0)
	var carry := 0.0
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var seg := a.distance_to(b)
		var t := carry
		while t <= seg:
			var c := a + (b - a) / maxf(seg, 0.01) * t
			var rr := r * rng.randf_range(0.8, 1.1)
			var pts := PackedVector2Array()
			var outer := PackedVector2Array()
			var rot := rng.randf() * TAU
			for k in 8:
				var ang := rot + TAU * float(k) / 8.0
				var jr := rr * rng.randf_range(0.8, 1.0)
				pts.append(c + Vector2.from_angle(ang) * jr)
				outer.append(c + Vector2.from_angle(ang) * (jr + 1.2))
			var tone := rng.randf_range(-0.07, 0.07)
			draw_colored_polygon(outer, edge)
			draw_colored_polygon(pts, (look["rail"] as Color).lightened(tone) if tone > 0 else (look["rail"] as Color).darkened(-tone))
			draw_circle(c - Vector2(rr * 0.25, rr * 0.25), rr * 0.35, look["hi"])
			t += step
		carry = t - seg
