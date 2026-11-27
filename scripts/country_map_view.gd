extends Control
## Draws the country map: an old parchment with ground patches, lakes, rivers, a rail line, mountains,
## dashed trails and a compass, plus the named locations on top. Everything is drawn in code.
##
## set_map() takes the country map Dictionary (see country_map.gd). The view edits its arrays in
## place when `editable`. `tool` chooses what the mouse edits:
##   "locations" and "mountains": click to select, drag to move.
##   "river", "lake", "rail", "ground": click a shape to select it, drag its points. With `adding`
##   on, a click adds a point (inserted if it lands on the outline, else appended). Right-click
##   a point to remove it.
## In read-only mode a click on a location emits location_pressed.

signal location_pressed(index: int)
signal location_moved(index: int)
signal mountain_pressed(index: int)
signal mountain_moved(index: int)
signal feature_pressed(index: int)
signal feature_changed
signal background_pressed(norm_pos: Vector2)

const CountryMap := preload("res://scripts/country_map.gd")

const WOOD := Color(0.14, 0.09, 0.055)
const INK := Color(0.17, 0.1, 0.05)
const INK_SOFT := Color(0.3, 0.19, 0.1, 0.8)
const FILL := Color(0.9, 0.77, 0.52)
const MOUNTAIN_FILL := Color(0.74, 0.57, 0.35, 0.75)
const RIVER := Color(0.45, 0.55, 0.55)
const LAKE := Color(0.5, 0.6, 0.6, 0.9)
const RED := Color(0.75, 0.15, 0.1)
const GROUND_COLORS := {
	"grass": Color(0.45, 0.6, 0.25, 0.3),
	"desert": Color(0.92, 0.72, 0.36, 0.34),
	"rock": Color(0.35, 0.3, 0.28, 0.3),
	"snow": Color(0.96, 0.98, 1.0, 0.5),
	"swamp": Color(0.3, 0.45, 0.35, 0.34),
}

static var _paper: ImageTexture

var locations: Array = []
var sequence: Array = []      # location ids in journey order (first = start)
## Play mode: draw each location's state ("done", "current", "locked") from `states` (id -> state).
var progress_enabled := false:
	set(v):
		progress_enabled = v
		set_process(v)
var states: Dictionary = {}
var features: Array = []
var mountains: Array = []
var map_seed := 7

var editable := false
var tool := "locations"
var adding := false
var selected := -1            # location
var selected_mountain := -1
var selected_feature := -1

var _pulse := 0.0
var _hover := -1
var _drag_kind := ""          # "loc", "mtn" or "vtx" while something is being dragged
var _drag := -1
var _drag_vertex := -1
var _drag_moved := false
var _grab := Vector2.ZERO     # pointer-to-object offset (normalised) when the drag started
var _press_pos := Vector2.ZERO
var _press_hit := -1

var _paper_poly := PackedVector2Array()
var _paper_uvs := PackedVector2Array()
var _paper_colors := PackedColorArray()
var _shadow_poly := PackedVector2Array()
var _fx: Array = []          # one entry per feature: {kind, style, line, ok, ties}
var _mtn_draw: Array = []    # {outline, lines}, back to front
var _trail_dashes := PackedVector2Array()  # pairs of points
var _marks := PackedVector2Array()         # grass tufts and cacti, pairs of points


func _ready() -> void:
	resized.connect(queue_redraw)
	set_process(progress_enabled)  # only the play screen needs the pulsing ring
	if _paper_poly.is_empty():
		rebuild()


func set_map(d: Dictionary) -> void:
	map_seed = int(d["seed"])
	locations = d["locations"]
	sequence = d["sequence"]
	features = d["features"]
	mountains = d["mountains"]
	selected = -1
	selected_mountain = -1
	selected_feature = -1
	adding = false
	refresh()


## Rebuilds everything generated (call after locations or the landscape changed).
func refresh() -> void:
	rebuild()
	queue_redraw()


## Cheaper rebuild of just the feature and mountain shapes (used while dragging).
func update_shapes() -> void:
	_rebuild_shapes()
	queue_redraw()


# ---------------------------------------------------------------- generated drawing data

func rebuild() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var w := CountryMap.MAP_SIZE.x
	var h := CountryMap.MAP_SIZE.y

	_paper_poly = _torn_rect(rng, Rect2(22, 22, w - 44, h - 44), 26.0)
	_paper_uvs = PackedVector2Array()
	_paper_colors = PackedColorArray()
	_shadow_poly = PackedVector2Array()
	for p in _paper_poly:
		_paper_uvs.append(p / CountryMap.MAP_SIZE)
		_paper_colors.append(Color.WHITE)
		_shadow_poly.append(p + Vector2(10, 12))

	_rebuild_shapes()

	# Keep plants and trails' surroundings clear of the landscape features.
	var blocked: Array = []  # Vector3(x, y, radius)
	for fx: Dictionary in _fx:
		if not fx["ok"] or fx["kind"] == "ground":
			continue
		var line: PackedVector2Array = fx["line"]
		for i in range(0, line.size(), 2):
			blocked.append(Vector3(line[i].x, line[i].y, 40.0))

	# Dashed trail between each pair of locations that follow each other in the journey.
	# Without a journey, every location is joined to its nearest neighbour instead.
	_trail_dashes = PackedVector2Array()
	var links: Array = []  # [index a, index b]
	var seq_idx: Array = []
	for id: int in sequence:
		var li := _index_of_id(id)
		if li >= 0:
			seq_idx.append(li)
	if seq_idx.size() >= 2:
		for k in seq_idx.size() - 1:
			links.append([seq_idx[k], seq_idx[k + 1]])
	elif sequence.is_empty():
		var done := {}
		for i in locations.size():
			var best := -1
			var best_d := INF
			var pi := _map_pos(i)
			for j in locations.size():
				if j == i:
					continue
				var d := pi.distance_to(_map_pos(j))
				if d < best_d:
					best_d = d
					best = j
			if best < 0:
				continue
			var key := "%d_%d" % [mini(i, best), maxi(i, best)]
			if done.has(key):
				continue
			done[key] = true
			links.append([i, best])
	for link: Array in links:
		var pi := _map_pos(link[0])
		var pj := _map_pos(link[1])
		var ctrl := (pi + pj) * 0.5 + (pj - pi).orthogonal() * rng.randf_range(-0.22, 0.22)
		var pts := PackedVector2Array()
		for k in 41:
			var t := k / 40.0
			pts.append(pi.lerp(ctrl, t).lerp(ctrl.lerp(pj, t), t))
		for k in range(0, 40, 2):
			_trail_dashes.append(pts[k])
			_trail_dashes.append(pts[k + 1])
		for k in range(0, 41, 3):
			blocked.append(Vector3(pts[k].x, pts[k].y, 30.0))

	for i in locations.size():
		blocked.append(Vector3(_map_pos(i).x, _map_pos(i).y, 80.0))
	blocked.append(Vector3(CountryMap.COMPASS_POS.x, CountryMap.COMPASS_POS.y, 125.0))
	for m: Dictionary in mountains:
		var mp: Vector2 = (m["pos"] as Vector2) * CountryMap.MAP_SIZE
		blocked.append(Vector3(mp.x, mp.y - 25.0, 42.0 * float(m["size"])))

	# Grass tufts and cacti, kept off lakes, features and mountains.
	_marks = PackedVector2Array()
	var plants := 0
	var tries := 0
	while plants < 64 and tries < 500:
		tries += 1
		var p := Vector2(rng.randf_range(90.0, w - 90.0), rng.randf_range(110.0, h - 70.0))
		if _is_blocked(p, blocked) or _in_lake(p):
			continue
		if plants % 7 == 0:
			_add_cactus(p)
		else:
			_marks.append(p)
			_marks.append(p + Vector2(-5, -9))
			_marks.append(p)
			_marks.append(p + Vector2(0, -12))
			_marks.append(p)
			_marks.append(p + Vector2(5, -9))
		blocked.append(Vector3(p.x, p.y, 18.0))
		plants += 1


## Smooths the control points of every feature and builds the mountain outlines.
func _rebuild_shapes() -> void:
	_fx = []
	for f: Dictionary in features:
		var kind := str(f["kind"])
		var closed := kind == "lake" or kind == "ground"
		var ctrl := PackedVector2Array()
		for v: Vector2 in f["pts"]:
			ctrl.append(v * CountryMap.MAP_SIZE)
		var item := {"kind": kind, "style": str(f.get("style", "grass")), "line": PackedVector2Array(), "ties": PackedVector2Array(), "ok": false}
		if ctrl.size() >= (3 if closed else 2):
			var line := _smooth(ctrl, closed)
			item["line"] = line
			# A polygon that crosses itself can't be filled; skip it instead of erroring every frame.
			item["ok"] = (not closed) or (not Geometry2D.triangulate_polygon(line).is_empty())
			if kind == "rail":
				var ties := PackedVector2Array()
				for i in range(0, line.size(), 4):
					var a := line[maxi(i - 1, 0)]
					var b := line[mini(i + 1, line.size() - 1)]
					var n := (b - a).normalized().orthogonal() * 9.0
					ties.append(line[i] + n)
					ties.append(line[i] - n)
				item["ties"] = ties
		_fx.append(item)

	_mtn_draw = []
	var rng := RandomNumberGenerator.new()
	for m: Dictionary in mountains:
		rng.seed = int(m["seed"])
		var shape := _make_mountain(rng, (m["pos"] as Vector2) * CountryMap.MAP_SIZE, float(m["size"]))
		shape["pos_y"] = (m["pos"] as Vector2).y
		_mtn_draw.append(shape)
	# Back to front, so nearer mountains overlap the ones behind them.
	_mtn_draw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["pos_y"]) < float(b["pos_y"]))


static func _smooth(pts: PackedVector2Array, closed: bool, per: int = 6) -> PackedVector2Array:
	var n := pts.size()
	if n < 3:
		return pts
	var out := PackedVector2Array()
	var count := n if closed else n - 1
	for i in count:
		var p0 := pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n] if closed else pts[i + 1]
		var p3 := pts[(i + 2) % n] if closed else pts[mini(i + 2, n - 1)]
		for k in per:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(k) / per))
	if not closed:
		out.append(pts[n - 1])
	return out


func _index_of_id(id: int) -> int:
	for i in locations.size():
		if int(locations[i]["id"]) == id:
			return i
	return -1


## "done", "current" or "locked" for location i (always "current" outside play mode).
func state_of(i: int) -> String:
	if not progress_enabled:
		return "current"
	return str(states.get(int(locations[i]["id"]), "locked"))


func _process(delta: float) -> void:
	# Keeps the "play this next" ring pulsing.
	_pulse += delta
	queue_redraw()


func _map_pos(i: int) -> Vector2:
	return (locations[i]["pos"] as Vector2) * CountryMap.MAP_SIZE


func _is_blocked(p: Vector2, blocked: Array) -> bool:
	for b: Vector3 in blocked:
		var r := b.z
		if p.distance_squared_to(Vector2(b.x, b.y)) < r * r:
			return true
	return false


func _in_lake(p: Vector2) -> bool:
	for fx: Dictionary in _fx:
		if fx["kind"] == "lake" and fx["ok"] and Geometry2D.is_point_in_polygon(p, fx["line"]):
			return true
	return false


## Rectangle outline with ragged, burnt-looking edges.
func _torn_rect(rng: RandomNumberGenerator, r: Rect2, step: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var inward := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var inw: Vector2 = inward[k]
		var n := maxi(int(a.distance_to(b) / step), 1)
		for i in n:
			var p := a.lerp(b, float(i) / n)
			if i > 0:
				p += inw * rng.randf_range(0.0, 9.0) + (b - a).normalized() * rng.randf_range(-5.0, 5.0)
			pts.append(p)
	return pts


func _make_mountain(rng: RandomNumberGenerator, base: Vector2, s: float) -> Dictionary:
	var half := 38.0 * s
	var hgt := 56.0 * s
	var peak := base + Vector2(rng.randf_range(-6.0, 6.0) * s, -hgt)
	var bl := base + Vector2(-half, 0)
	var br := base + Vector2(half, 0)
	var left_mid := bl.lerp(peak, 0.55) + Vector2(rng.randf_range(-5.0, 2.0), rng.randf_range(-3.0, 3.0))
	var right_mid := br.lerp(peak, 0.5) + Vector2(rng.randf_range(-2.0, 5.0), rng.randf_range(-3.0, 3.0))
	var outline := PackedVector2Array([bl, left_mid, peak, right_mid, br])
	var lines := PackedVector2Array()
	# Shading hatches on the right slope, and a ridge line down from the peak.
	for j in range(1, 5):
		var a := peak.lerp(br, j / 5.0) + Vector2(-2, 3)
		lines.append(a)
		lines.append(a + Vector2(-half * 0.28, hgt * 0.24))
	var ridge_mid := peak + Vector2(-half * 0.12, hgt * 0.35)
	lines.append(peak)
	lines.append(ridge_mid)
	lines.append(ridge_mid)
	lines.append(peak + Vector2(-half * 0.2, hgt * 0.75))
	return {"outline": outline, "lines": lines}


func _add_cactus(p: Vector2) -> void:
	var pairs := [
		[Vector2(0, 0), Vector2(0, -22)],
		[Vector2(0, -9), Vector2(-8, -9)], [Vector2(-8, -9), Vector2(-8, -17)],
		[Vector2(0, -13), Vector2(8, -13)], [Vector2(8, -13), Vector2(8, -20)],
	]
	for pr: Array in pairs:
		_marks.append(p + (pr[0] as Vector2))
		_marks.append(p + (pr[1] as Vector2))


static func _get_paper() -> ImageTexture:
	if _paper != null:
		return _paper
	var w := 320
	var h := 180
	var base := FastNoiseLite.new()
	base.seed = 5
	base.frequency = 0.012
	base.fractal_octaves = 4
	var grain := FastNoiseLite.new()
	grain.seed = 17
	grain.frequency = 0.35
	var light := Color("dcc08a")
	var dark := Color("b8935a")
	var burn := Color("5a3a1c")
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v := base.get_noise_2d(x, y) * 0.5 + 0.5
			var c := dark.lerp(light, clampf(v * 1.3 - 0.1, 0.0, 1.0))
			var g := grain.get_noise_2d(x, y) * 0.05
			c = Color(c.r + g, c.g + g, c.b + g)
			var e := maxf(absf(x / float(w) - 0.5), absf(y / float(h) - 0.5)) * 2.0
			var t := clampf((e - 0.78) / 0.22, 0.0, 1.0)
			c = c.lerp(burn, t * t * 0.7)
			img.set_pixel(x, y, c)
	_paper = ImageTexture.create_from_image(img)
	return _paper


# ---------------------------------------------------------------- drawing

## Where the map sits inside this control (letterboxed, keeps the 16:9 shape).
func _map_rect() -> Rect2:
	var avail := size - Vector2(24, 24)
	var s := maxf(minf(avail.x / CountryMap.MAP_SIZE.x, avail.y / CountryMap.MAP_SIZE.y), 0.01)
	var sz := CountryMap.MAP_SIZE * s
	return Rect2((size - sz) * 0.5, sz)


func _draw() -> void:
	var rect := _map_rect()
	var s := rect.size.x / CountryMap.MAP_SIZE.x
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), WOOD)

	draw_set_transform(rect.position, 0.0, Vector2(s, s))
	draw_colored_polygon(_shadow_poly, Color(0, 0, 0, 0.4))
	draw_polygon(_paper_poly, _paper_colors, _paper_uvs, _get_paper())
	var edge: PackedVector2Array = _paper_poly.duplicate()
	edge.append(_paper_poly[0])
	draw_polyline(edge, Color(0.25, 0.15, 0.08, 0.9), 2.0, true)

	# Ground patches, then lakes, rivers and rails.
	for fx: Dictionary in _fx:
		if fx["kind"] == "ground" and fx["ok"]:
			var col: Color = GROUND_COLORS.get(fx["style"], GROUND_COLORS["grass"])
			var line: PackedVector2Array = fx["line"]
			draw_colored_polygon(line, col)
			var loop: PackedVector2Array = line.duplicate()
			loop.append(line[0])
			draw_polyline(loop, Color(col, 0.55), 3.0, true)
	for fx: Dictionary in _fx:
		var line: PackedVector2Array = fx["line"]
		match fx["kind"]:
			"lake":
				if fx["ok"]:
					draw_colored_polygon(line, LAKE)
					var loop: PackedVector2Array = line.duplicate()
					loop.append(line[0])
					draw_polyline(loop, INK, 3.5, true)
					# A few ripple lines inside the lake.
					var bounds := Rect2(line[0], Vector2.ZERO)
					for q in line:
						bounds = bounds.expand(q)
					var c := bounds.get_center()
					for k in range(1, 3):
						var y := c.y + (k - 1.5) * bounds.size.y * 0.25
						draw_line(Vector2(c.x - bounds.size.x * 0.18, y), Vector2(c.x + bounds.size.x * 0.18, y), Color(INK, 0.45), 1.5, true)
			"river":
				if line.size() >= 2:
					draw_polyline(line, INK_SOFT, 11.0, true)
					draw_polyline(line, RIVER, 6.0, true)
			"rail":
				if line.size() >= 2:
					draw_polyline(line, INK, 3.0, true)
					draw_multiline(fx["ties"], INK, 2.0)

	draw_multiline(_trail_dashes, INK_SOFT, 3.0)

	for m: Dictionary in _mtn_draw:
		var outline: PackedVector2Array = m["outline"]
		draw_colored_polygon(outline, MOUNTAIN_FILL)
		draw_polyline(outline, INK, 2.5, true)
		draw_multiline(m["lines"], INK_SOFT, 1.6)
	draw_multiline(_marks, INK_SOFT, 1.8)

	_draw_compass(font)
	draw_rect(Rect2(50, 50, CountryMap.MAP_SIZE.x - 100, CountryMap.MAP_SIZE.y - 100), INK, false, 4.0)
	draw_rect(Rect2(58, 58, CountryMap.MAP_SIZE.x - 116, CountryMap.MAP_SIZE.y - 116), INK_SOFT, false, 1.5)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in locations.size():
		_draw_location(i, rect, font)
	if editable:
		_draw_edit_overlay(rect)


## Selection ring for the selected mountain and handles for the selected feature's points.
func _draw_edit_overlay(rect: Rect2) -> void:
	var s := rect.size.x / CountryMap.MAP_SIZE.x
	if tool == "mountains" and selected_mountain >= 0 and selected_mountain < mountains.size():
		var m: Dictionary = mountains[selected_mountain]
		var c := _mountain_center(m, rect)
		draw_arc(c, 46.0 * float(m["size"]) * s, 0.0, TAU, 40, RED, 3.0, true)
	if selected_feature >= 0 and selected_feature < features.size():
		var f: Dictionary = features[selected_feature]
		if str(f["kind"]) != tool:
			return
		var pts := PackedVector2Array()
		for v: Vector2 in f["pts"]:
			pts.append(rect.position + v * rect.size)
		var closed := tool == "lake" or tool == "ground"
		if pts.size() >= 2:
			var guide: PackedVector2Array = pts.duplicate()
			if closed and pts.size() >= 3:
				guide.append(pts[0])
			draw_polyline(guide, Color(RED, 0.75), 1.5, true)
		for k in pts.size():
			draw_circle(pts[k], 7.0, Color.WHITE)
			draw_arc(pts[k], 7.0, 0.0, TAU, 20, RED, 2.0, true)
		if adding:
			draw_arc(rect.position + Vector2(18, 18), 6.0, 0.0, TAU, 16, RED, 3.0, true)


func _draw_compass(font: Font) -> void:
	var c := CountryMap.COMPASS_POS
	draw_arc(c, 54.0, 0.0, TAU, 48, INK, 2.5, true)
	draw_arc(c, 46.0, 0.0, TAU, 48, INK_SOFT, 1.5, true)
	for k in 8:
		var dir := Vector2.from_angle(k * PI / 4.0 - PI / 2.0)
		var is_long := k % 2 == 0
		var reach := 62.0 if is_long else 34.0
		var perp := dir.orthogonal() * (9.0 if is_long else 6.0)
		var tip := c + dir * reach
		draw_colored_polygon(PackedVector2Array([tip, c + perp, c]), INK)
		draw_colored_polygon(PackedVector2Array([tip, c - perp, c]), FILL)
		draw_polyline(PackedVector2Array([tip, c + perp, c - perp, tip]), INK, 1.5, true)
	draw_string(font, c + Vector2(-8, -70), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(font, c + Vector2(68, 8), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(font, c + Vector2(-7, 94), "S", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
	draw_string(font, c + Vector2(-92, 8), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)


func _draw_location(i: int, rect: Rect2, font: Font) -> void:
	var loc: Dictionary = locations[i]
	var p := rect.position + (loc["pos"] as Vector2) * rect.size
	var s := clampf(rect.size.x / CountryMap.MAP_SIZE.x, 0.7, 1.6)
	var linked := str(loc.get("map", "")) != ""
	var state := state_of(i)
	var dim := 1.0 if (linked or editable) else 0.55
	if state == "locked":
		dim = 0.45
	# Locked locations can't be picked, so they don't react to the pointer.
	var hot := (i == _hover and state != "locked") or i == selected
	var g := s * (1.15 if hot else 1.0)
	var ink := Color(INK, dim)

	# A small clearing so the scenery doesn't run through the icon.
	draw_circle(p, 32.0 * s, Color(0.86, 0.72, 0.47, 0.82))
	if hot:
		draw_arc(p, 38.0 * s, 0.0, TAU, 40, RED, 3.0, true)
	elif state == "current" and progress_enabled:
		var pulse := 0.5 + 0.5 * sin(_pulse * 4.0)
		draw_arc(p, (38.0 + 4.0 * pulse) * s, 0.0, TAU, 40, Color(RED, 0.5 + 0.5 * pulse), 3.0, true)
	_draw_icon(str(loc.get("icon", "town")), p, g, ink, Color(FILL, dim))
	if editable and not linked:
		draw_circle(p + Vector2(24, -24) * s, 6.0 * s, RED)
	if state == "locked" and progress_enabled:
		_draw_lock(p + Vector2(22, -22) * s, s)
	elif state == "done":
		_draw_check(p + Vector2(22, -22) * s, s)
	if editable:
		var place := sequence.find(int(loc["id"])) + 1
		if place > 0:
			var bp := p + Vector2(-26, -26) * s
			draw_circle(bp, 12.0 * s, Color(0.2, 0.5, 0.2) if place == 1 else INK)
			var label := "S" if place == 1 else str(place)
			var bfs := int(16.0 * s)
			var bw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x
			draw_string(font, bp + Vector2(-bw * 0.5, bfs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, Color.WHITE)

	var text := str(loc.get("name", ""))
	var fs := int(24.0 * s)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tpos := Vector2(p.x - tw * 0.5, p.y + 34.0 * s + fs)
	draw_string_outline(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.86, 0.72, 0.47, 0.9 * dim))
	draw_string(font, tpos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)


func _draw_lock(c: Vector2, s: float) -> void:
	draw_circle(c, 12.0 * s, Color(0.17, 0.1, 0.05, 0.85))
	draw_arc(c + Vector2(0, -3) * s, 4.5 * s, PI, TAU, 12, Color.WHITE, 2.0, true)
	draw_rect(Rect2(c + Vector2(-5, -2) * s, Vector2(10, 7) * s), Color.WHITE)


func _draw_check(c: Vector2, s: float) -> void:
	draw_circle(c, 12.0 * s, Color(0.2, 0.5, 0.2))
	draw_polyline(PackedVector2Array([c + Vector2(-5, 0) * s, c + Vector2(-1, 4) * s, c + Vector2(6, -4) * s]), Color.WHITE, 2.5 * s, true)


func _draw_icon(icon: String, p: Vector2, g: float, ink: Color, fill: Color) -> void:
	match icon:
		"station":
			_house(p, g, 0.0, 14.0, 36.0, 17.0, 11.0, fill, ink)
			_poly(p, g, [Vector2(-3, 14), Vector2(-3, 6), Vector2(3, 6), Vector2(3, 14)], Color(ink, 0.7), ink)
			_line(p, g, Vector2(12, -14), Vector2(12, -24), ink)
			_poly(p, g, [Vector2(12, -24), Vector2(21, -21), Vector2(12, -18)], Color(RED, ink.a), ink)
		"mine":
			_poly(p, g, [Vector2(-18, 14), Vector2(-11, -10), Vector2(11, -10), Vector2(18, 14)], fill, ink)
			_poly(p, g, [Vector2(-8, 14), Vector2(-8, -2), Vector2(8, -2), Vector2(8, 14)], Color(ink, 0.85), ink)
			_line(p, g, Vector2(-11, -10), Vector2(-8, 14), ink)
			_line(p, g, Vector2(11, -10), Vector2(8, 14), ink)
			_line(p, g, Vector2(-16, 14), Vector2(16, 14), ink)
		"ranch":
			_house(p, g, -9.0, 14.0, 22.0, 14.0, 10.0, fill, ink)
			_line(p, g, Vector2(5, 8), Vector2(26, 8), ink)
			_line(p, g, Vector2(5, 13), Vector2(26, 13), ink)
			for fx in [6.0, 15.0, 25.0]:
				_line(p, g, Vector2(fx, 4), Vector2(fx, 15), ink)
		"fort":
			_poly(p, g, [Vector2(-17, 14), Vector2(-17, -6), Vector2(17, -6), Vector2(17, 14)], fill, ink)
			for tx in [-17.0, 17.0]:
				_poly(p, g, [Vector2(tx - 6, 14), Vector2(tx - 6, -14), Vector2(tx + 6, -14), Vector2(tx + 6, 14)], fill, ink)
				_line(p, g, Vector2(tx - 6, -14), Vector2(tx - 6, -18), ink)
				_line(p, g, Vector2(tx + 6, -14), Vector2(tx + 6, -18), ink)
			_poly(p, g, [Vector2(-5, 14), Vector2(-5, 3), Vector2(5, 3), Vector2(5, 14)], Color(ink, 0.8), ink)
		"camp":
			_poly(p, g, [Vector2(-18, 14), Vector2(-2, -16), Vector2(14, 14)], fill, ink)
			_poly(p, g, [Vector2(-2, 14), Vector2(-7, 14), Vector2(-2, 0)], Color(ink, 0.85), ink)
			_poly(p, g, [Vector2(19, 14), Vector2(23, 4), Vector2(27, 14)], Color(RED, ink.a), ink)
			_line(p, g, Vector2(17, 15), Vector2(29, 15), ink)
		"wilderness":
			# A rocky hill with two pine trees in front.
			_poly(p, g, [Vector2(-20, 14), Vector2(-6, -14), Vector2(2, -6), Vector2(10, -16), Vector2(22, 14)], fill, ink)
			_line(p, g, Vector2(10, -16), Vector2(7, -2), ink)
			for tx in [-11.0, 8.0]:
				var top := -6.0 if tx < 0.0 else -2.0
				_poly(p, g, [Vector2(tx - 8, 8), Vector2(tx, top), Vector2(tx + 8, 8)], Color(0.38, 0.5, 0.28, fill.a), ink)
				_poly(p, g, [Vector2(tx - 10, 16), Vector2(tx, top + 8), Vector2(tx + 10, 16)], Color(0.38, 0.5, 0.28, fill.a), ink)
				_line(p, g, Vector2(tx, 16), Vector2(tx, 21), ink)
		_:  # town
			_house(p, g, -14.0, 14.0, 13.0, 9.0, 7.0, fill, ink)
			_house(p, g, 14.0, 14.0, 12.0, 8.0, 6.0, fill, ink)
			_house(p, g, 0.0, 16.0, 18.0, 14.0, 10.0, fill, ink)


func _house(p: Vector2, g: float, cx: float, base: float, w: float, h: float, roof: float, fill: Color, ink: Color) -> void:
	_poly(p, g, [Vector2(cx - w / 2, base), Vector2(cx - w / 2, base - h), Vector2(cx + w / 2, base - h), Vector2(cx + w / 2, base)], fill, ink)
	_poly(p, g, [Vector2(cx - w / 2 - 2, base - h), Vector2(cx, base - h - roof), Vector2(cx + w / 2 + 2, base - h)], Color(0.5, 0.33, 0.2, fill.a), ink)


## Filled, outlined polygon given in icon units (scaled by g around p).
func _poly(p: Vector2, g: float, pts: Array, fill: Color, ink: Color) -> void:
	var out := PackedVector2Array()
	for v: Vector2 in pts:
		out.append(p + v * g)
	if fill.a > 0.0 and out.size() >= 3:
		draw_colored_polygon(out, fill)
	out.append(out[0])
	draw_polyline(out, ink, maxf(1.5, 2.0 * g), true)


func _line(p: Vector2, g: float, a: Vector2, b: Vector2, ink: Color) -> void:
	draw_line(p + a * g, p + b * g, ink, maxf(1.5, 2.0 * g), true)


# ---------------------------------------------------------------- hit testing

func _loc_screen(i: int, rect: Rect2) -> Vector2:
	return rect.position + (locations[i]["pos"] as Vector2) * rect.size


func _hit(pos: Vector2) -> int:
	var rect := _map_rect()
	var r := 42.0 * clampf(rect.size.x / CountryMap.MAP_SIZE.x, 0.7, 1.6)
	var best := -1
	var best_d := r
	for i in locations.size():
		var d := pos.distance_to(_loc_screen(i, rect))
		if d <= best_d:
			best_d = d
			best = i
	return best


## Screen position of the middle of a mountain's body.
func _mountain_center(m: Dictionary, rect: Rect2) -> Vector2:
	var s := rect.size.x / CountryMap.MAP_SIZE.x
	return rect.position + (m["pos"] as Vector2) * rect.size + Vector2(0, -28.0 * float(m["size"]) * s)


func _hit_mountain(pos: Vector2) -> int:
	var rect := _map_rect()
	var s := rect.size.x / CountryMap.MAP_SIZE.x
	var best := -1
	var best_d := INF
	for i in mountains.size():
		var m: Dictionary = mountains[i]
		var d := pos.distance_to(_mountain_center(m, rect))
		if d <= maxf(36.0 * float(m["size"]) * s, 22.0) and d < best_d:
			best_d = d
			best = i
	return best


func _feature_screen_pts(f: Dictionary, rect: Rect2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v: Vector2 in f["pts"]:
		pts.append(rect.position + v * rect.size)
	return pts


## Index of the selected feature's point under the pointer, or -1.
func _hit_vertex(pos: Vector2) -> int:
	if selected_feature < 0 or selected_feature >= features.size():
		return -1
	var pts := _feature_screen_pts(features[selected_feature], _map_rect())
	var best := -1
	var best_d := 12.0
	for k in pts.size():
		var d := pos.distance_to(pts[k])
		if d <= best_d:
			best_d = d
			best = k
	return best


func _is_closed(kind: String) -> bool:
	return kind == "lake" or kind == "ground"


## The topmost feature of the current tool's kind under the pointer, or -1.
func _hit_feature(pos: Vector2) -> int:
	var rect := _map_rect()
	for idx in range(features.size() - 1, -1, -1):
		var f: Dictionary = features[idx]
		if str(f["kind"]) != tool:
			continue
		var pts := _feature_screen_pts(f, rect)
		var closed := _is_closed(tool)
		if closed and pts.size() >= 3 and Geometry2D.is_point_in_polygon(pos, pts):
			return idx
		var segs := pts.size() if closed else pts.size() - 1
		for k in segs:
			var a := pts[k]
			var b := pts[(k + 1) % pts.size()]
			if pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b)) <= 12.0:
				return idx
		if pts.size() == 1 and pos.distance_to(pts[0]) <= 12.0:
			return idx
	return -1


## Adds a point to the selected feature at the pointer (inserted if it is on the outline).
func _add_point(pos: Vector2) -> void:
	var f: Dictionary = features[selected_feature]
	var pts: Array = f["pts"]
	var rect := _map_rect()
	var closed := _is_closed(str(f["kind"]))
	var sp := _feature_screen_pts(f, rect)
	var segs := sp.size() if closed else sp.size() - 1
	for k in segs:
		var a := sp[k]
		var b := sp[(k + 1) % sp.size()]
		var q := Geometry2D.get_closest_point_to_segment(pos, a, b)
		if pos.distance_to(q) <= 14.0:
			pts.insert(k + 1, _to_norm(q))
			refresh()
			feature_changed.emit()
			return
	pts.append(_to_norm(pos))
	refresh()
	feature_changed.emit()


func _to_norm(pos: Vector2) -> Vector2:
	var rect := _map_rect()
	var n := (pos - rect.position) / rect.size
	return Vector2(clampf(n.x, 0.03, 0.97), clampf(n.y, 0.05, 0.95))


func _to_norm_raw(pos: Vector2) -> Vector2:
	var rect := _map_rect()
	return (pos - rect.position) / rect.size


# ---------------------------------------------------------------- input

func _set_hover(i: int) -> void:
	if i == _hover:
		return
	_hover = i
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if i >= 0 else Control.CURSOR_ARROW
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hover(-1)


func _start_drag(kind: String, index: int, obj_pos: Vector2, pointer: Vector2) -> void:
	_drag_kind = kind
	_drag = index
	_drag_moved = false
	_grab = obj_pos - _to_norm_raw(pointer)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if _drag_kind != "":
			if not _drag_moved and m.position.distance_to(_press_pos) > 4.0:
				_drag_moved = true
			if _drag_moved:
				_drag_to(_to_norm(m.position + _grab * _map_rect().size))
		elif not editable:
			_set_hover(_hit(m.position))
		elif tool == "locations":
			_set_hover(_hit(m.position))
	elif event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_LEFT:
			if b.pressed:
				_press(b.position)
			else:
				_release(b.position)
		elif b.button_index == MOUSE_BUTTON_RIGHT and b.pressed and editable:
			var v := _hit_vertex(b.position)
			if v >= 0:
				(features[selected_feature]["pts"] as Array).remove_at(v)
				refresh()
				feature_changed.emit()


func _drag_to(n: Vector2) -> void:
	match _drag_kind:
		"loc":
			locations[_drag]["pos"] = n
			queue_redraw()
		"mtn":
			mountains[_drag]["pos"] = n
			update_shapes()
		"vtx":
			(features[selected_feature]["pts"] as Array)[_drag_vertex] = n
			update_shapes()


func _press(pos: Vector2) -> void:
	_press_pos = pos
	_press_hit = -1
	_drag_kind = ""
	if not editable:
		_press_hit = _hit(pos)
		return
	var rect := _map_rect()
	match tool:
		"locations":
			_press_hit = _hit(pos)
			if _press_hit >= 0:
				selected = _press_hit
				_start_drag("loc", _press_hit, locations[_press_hit]["pos"], pos)
				location_pressed.emit(_press_hit)
				queue_redraw()
			elif rect.has_point(pos):
				background_pressed.emit(_to_norm(pos))
		"mountains":
			var i := _hit_mountain(pos)
			if i >= 0:
				selected_mountain = i
				_start_drag("mtn", i, mountains[i]["pos"], pos)
				mountain_pressed.emit(i)
				queue_redraw()
			elif rect.has_point(pos):
				background_pressed.emit(_to_norm(pos))
		_:
			_press_feature(pos, rect)


func _press_feature(pos: Vector2, rect: Rect2) -> void:
	if selected_feature >= 0 and selected_feature < features.size() and str(features[selected_feature]["kind"]) == tool:
		var v := _hit_vertex(pos)
		if v >= 0:
			_drag_vertex = v
			_start_drag("vtx", selected_feature, features[selected_feature]["pts"][v], pos)
			return
		if adding:
			if rect.has_point(pos):
				_add_point(pos)
			return
	var f := _hit_feature(pos)
	if f >= 0:
		selected_feature = f
		feature_pressed.emit(f)
		queue_redraw()
	elif rect.has_point(pos):
		background_pressed.emit(_to_norm(pos))


func _release(pos: Vector2) -> void:
	if _drag_kind != "":
		var kind := _drag_kind
		var i := _drag
		_drag_kind = ""
		if _drag_moved:
			refresh()
			match kind:
				"loc":
					location_moved.emit(i)
				"mtn":
					mountain_moved.emit(i)
				"vtx":
					feature_changed.emit()
	elif not editable and _press_hit >= 0 and _hit(pos) == _press_hit:
		location_pressed.emit(_press_hit)
	_press_hit = -1
