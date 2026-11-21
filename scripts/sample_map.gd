class_name SampleMap
extends RefCounted
## Builds a sample map modelled on a forest manor battlemap (coordinates authored on a 1024x864 grid, scaled x2).

const S := 2.0
const MoreMaps := preload("res://scripts/sample_map_more.gd")


static func _v(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(p[0], p[1]) * S)
	return out


static func _rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return _v([[x, y], [x + w, y], [x + w, y + h], [x, y + h]])


static func _organic(pts: PackedVector2Array, rng: RandomNumberGenerator, amount: float, passes: int) -> PackedVector2Array:
	var cur := pts
	for _i in passes:
		var nxt := PackedVector2Array()
		for i in cur.size():
			var a := cur[i]
			var b := cur[(i + 1) % cur.size()]
			nxt.append(a)
			var nrm := (b - a).orthogonal().normalized()
			nxt.append((a + b) * 0.5 + nrm * rng.randf_range(-amount, amount))
		cur = nxt
		amount *= 0.6
	return cur


static func _blob(c: Vector2, r: float, rng: RandomNumberGenerator, n: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.7, 1.2))
	return pts


static func _wall(d: Dictionary, x1: float, y1: float, x2: float, y2: float) -> void:
	d["walls"].append(MapData.new_wall(_v([[x1, y1], [x2, y2]]), false, 12.0))


## Builds the sample map for a theme.
static func create(theme: String = "fantasy") -> Dictionary:
	match theme:
		"train":
			return create_train()
		"desert":
			return MoreMaps.create_desert()
		"snow":
			return MoreMaps.create_snow()
		"town":
			return MoreMaps.create_town()
		"swamp":
			return MoreMaps.create_swamp()
		"wagon":
			return MoreMaps.create_wagon()
	return create_fantasy()


# ---------------------------------------------------------------- train theme (pixel coordinates, no scaling)

static func _px(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in a:
		out.append(Vector2(p[0], p[1]))
	return out


static func _prect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return _px([[x0, y0], [x1, y0], [x1, y1], [x0, y1]])


static func _hull_seg(d: Dictionary, a: Array, b: Array) -> void:
	d["walls"].append(MapData.new_wall(_px([a, b]), false, 16.0, "hull"))


## Open-ended train car hull: doors at both ends (centred), optional gaps in the side walls (y range).
static func _hull_car(d: Dictionary, x0: float, y0: float, x1: float, y1: float, left_gap := Vector2.ZERO, right_gap := Vector2.ZERO) -> void:
	var cx := (x0 + x1) * 0.5
	var dh := 26.0
	for y in [y0, y1]:
		_hull_seg(d, [x0, y], [cx - dh, y])
		_hull_seg(d, [cx + dh, y], [x1, y])
	for side in [[x0, left_gap], [x1, right_gap]]:
		var x: float = side[0]
		var g: Vector2 = side[1]
		if g == Vector2.ZERO:
			_hull_seg(d, [x, y0], [x, y1])
		else:
			_hull_seg(d, [x, y0], [x, g.x])
			_hull_seg(d, [x, g.y], [x, y1])


static func _rail(d: Dictionary, pts: PackedVector2Array) -> void:
	d["walls"].append(MapData.new_wall(pts, false, 70.0, "rail"))


static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, n: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / float(n)
		out.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	return out


static func create_train() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321
	var d := MapData.empty("train")
	d["spawn"] = Vector2(760, 1030)

	# Ground variation
	for i in 14:
		var c := Vector2(rng.randf_range(0, 2048), rng.randf_range(0, 1728))
		d["polygons"].append(MapData.new_poly("grass_dark", _blob(c, rng.randf_range(90, 220), rng)))
	for i in 8:
		var c2 := Vector2(rng.randf_range(0, 2048), rng.randf_range(0, 1728))
		d["polygons"].append(MapData.new_poly("cliff", _blob(c2, rng.randf_range(50, 120), rng)))
	# River on the far left
	var river := _px([[0, 500], [240, 560], [330, 900], [230, 1300], [0, 1400]])
	d["polygons"].append(MapData.new_poly("river", _organic(river, rng, 22.0, 3)))

	# Gravel beds under both tracks
	d["polygons"].append(MapData.new_poly("gravel", _prect(850, 0, 1150, 1728)))
	d["polygons"].append(MapData.new_poly("gravel", _prect(1350, 0, 1650, 1728)))

	# Track under the main train (hidden by the train where it overlaps) plus a curving branch
	_rail(d, _px([[1000, 0], [1000, 790]]))
	_rail(d, _px([[1000, 1350], [1000, 1500]]))
	_rail(d, _bezier(Vector2(1000, 1500), Vector2(1000, 1640), Vector2(1180, 1728)))
	_rail(d, _px([[1500, 0], [1500, 500]]))
	_rail(d, _px([[1500, 1100], [1500, 1728]]))

	# Passenger car (wood floor, benches)
	d["polygons"].append(MapData.new_poly("train_black", _prect(880, 790, 1120, 1350)))
	d["polygons"].append(MapData.new_poly("train_wood", _prect(888, 798, 1112, 1342)))
	var left_gap := Vector2(1000, 1060)
	_hull_car(d, 880, 790, 1120, 1350, left_gap, Vector2.ZERO)

	# Luxury car on the siding (blue carpet, red seats)
	d["polygons"].append(MapData.new_poly("train_black", _prect(1380, 500, 1620, 1100)))
	d["polygons"].append(MapData.new_poly("train_blue", _prect(1388, 508, 1612, 1092)))
	for i in 4:
		var y := 540.0 + i * 135.0
		d["polygons"].append(MapData.new_poly("train_red", _prect(1392, y, 1438, y + 84)))
		d["polygons"].append(MapData.new_poly("train_red", _prect(1562, y, 1608, y + 84)))
	_hull_car(d, 1380, 500, 1620, 1100, Vector2.ZERO, Vector2(780, 840))

	var P := MapData.new_prop
	# Locomotive, coal tender and smoke
	d["props"].append(P.call("locomotive", Vector2(1000, 330), 1.0, 0.0, 1))
	d["props"].append(P.call("coal_car", Vector2(1000, 670), 1.0, 0.0, 2))
	d["props"].append(P.call("smoke", Vector2(985, 60), 1.3, 0.0, 3))
	d["props"].append(P.call("smoke", Vector2(930, -10), 1.6, 1.0, 4))
	d["props"].append(P.call("smoke", Vector2(860, 40), 1.2, 2.0, 5))

	# Passenger car furniture
	for i in 9:
		var y := 835.0 + i * 60.0
		if not (y > left_gap.x - 40.0 and y < left_gap.y + 40.0):
			d["props"].append(P.call("bench", Vector2(923, y), 1.0, 0.0, 10 + i))
			d["props"].append(P.call("window", Vector2(880, y), 1.0, PI * 0.5, 40 + i))
		d["props"].append(P.call("bench", Vector2(1077, y), 1.0, PI, 20 + i))
		d["props"].append(P.call("window", Vector2(1120, y), 1.0, PI * 0.5, 60 + i))
	# Luxury car windows
	for i in 4:
		var wy := 582.0 + i * 135.0
		d["props"].append(P.call("window", Vector2(1380, wy), 1.0, PI * 0.5, 80 + i))
		if not (wy > 760.0 and wy < 860.0):
			d["props"].append(P.call("window", Vector2(1620, wy), 1.0, PI * 0.5, 90 + i))

	# Yard clutter
	d["props"].append(P.call("crate", Vector2(770, 1460), 1.2, 0.2, 100))
	d["props"].append(P.call("crate", Vector2(812, 1480), 1.0, 0.5, 101))
	d["props"].append(P.call("barrel", Vector2(790, 1430), 1.0, 0.0, 102))
	d["props"].append(P.call("crate", Vector2(1250, 1380), 1.1, 0.4, 103))
	d["props"].append(P.call("barrel", Vector2(1230, 1420), 1.0, 0.0, 104))
	d["props"].append(P.call("torch", Vector2(840, 1200), 1.0, 0.0, 105))
	d["props"].append(P.call("torch", Vector2(1160, 640), 1.0, 0.0, 106))

	# Lights
	d["lights"].append(MapData.new_light(Vector2(1000, 940), 340.0, Color(1.0, 0.82, 0.55), 0.9, false))
	d["lights"].append(MapData.new_light(Vector2(1000, 1220), 340.0, Color(1.0, 0.82, 0.55), 0.9, false))
	d["lights"].append(MapData.new_light(Vector2(1500, 700), 340.0, Color(0.85, 0.9, 1.0), 0.8, false))
	d["lights"].append(MapData.new_light(Vector2(1500, 920), 340.0, Color(0.85, 0.9, 1.0), 0.8, false))

	MapData.scatter_props(d, 14, 18, 22, 55)
	return d


# ---------------------------------------------------------------- fantasy theme

static func create_fantasy() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var d := MapData.empty()
	d["ambient"] = Color(0.6, 0.62, 0.72)
	d["spawn"] = Vector2(445, 590) * S

	# Grass variation and shadows
	for i in 22:
		var c := Vector2(rng.randf_range(0, 2048), rng.randf_range(0, 1728))
		d["polygons"].append(MapData.new_poly("grass_dark", _blob(c, rng.randf_range(80, 200), rng)))
	for i in 6:
		var c := Vector2(rng.randf_range(0, 2048), rng.randf_range(0, 1728))
		d["polygons"].append(MapData.new_poly("moss", _blob(c, rng.randf_range(50, 110), rng)))

	# Dirt paths
	var north := _v([[370, 0], [450, 0], [465, 120], [520, 170], [690, 175], [720, 215], [710, 330], [685, 330], [685, 200], [480, 200], [430, 190], [400, 110]])
	var south := _v([[360, 500], [530, 500], [560, 580], [700, 600], [900, 570], [960, 560], [960, 600], [700, 650], [520, 640], [520, 760], [580, 864], [300, 864], [380, 700], [400, 600]])
	d["polygons"].append(MapData.new_poly("dirt", _organic(north, rng, 14.0, 3)))
	d["polygons"].append(MapData.new_poly("dirt", _organic(south, rng, 16.0, 3)))

	# Manor floor (outer outline) + room floors
	var outline := _v([[205, 205], [685, 205], [685, 520], [525, 520], [525, 430], [365, 430], [365, 520], [205, 520]])
	d["polygons"].append(MapData.new_poly("wood", outline))
	d["polygons"].append(MapData.new_poly("dark", _rect(275, 205, 225, 90)))   # great hall
	d["polygons"].append(MapData.new_poly("dark", _rect(205, 205, 70, 90)))    # storage
	d["polygons"].append(MapData.new_poly("stone", _rect(385, 390, 115, 40)))  # foyer
	d["polygons"].append(MapData.new_poly("stone", _rect(610, 295, 75, 70)))   # bathroom
	d["polygons"].append(MapData.new_poly("carpet", _rect(415, 320, 55, 65)))  # hall runner
	d["polygons"].append(MapData.new_poly("carpet", _rect(540, 365, 85, 155))) # throne room carpet
	d["polygons"].append(MapData.new_poly("shadow", _rect(205, 205, 480, 14)))

	# Outbuilding
	var shed := _v([[725, 293], [955, 293], [955, 570], [885, 570], [885, 385], [725, 385]])
	d["polygons"].append(MapData.new_poly("wood", shed))
	d["polygons"].append(MapData.new_poly("blood", _blob(Vector2(1800, 660), 40, rng)))

	# Walls
	d["walls"].append(MapData.new_wall(outline, true, 14.0))
	d["walls"].append(MapData.new_wall(shed, true, 14.0))
	_wall(d, 275, 205, 275, 295)
	_wall(d, 275, 295, 380, 295)
	_wall(d, 440, 295, 500, 295)
	_wall(d, 505, 205, 505, 275)
	_wall(d, 505, 275, 600, 275)
	_wall(d, 630, 275, 685, 275)
	_wall(d, 205, 295, 365, 295)
	_wall(d, 320, 295, 320, 335)
	_wall(d, 320, 355, 320, 405)
	_wall(d, 205, 350, 320, 350)
	_wall(d, 205, 405, 330, 405)
	_wall(d, 350, 405, 365, 405)
	_wall(d, 365, 295, 365, 380)
	_wall(d, 525, 295, 525, 350)
	_wall(d, 525, 370, 525, 430)
	_wall(d, 610, 295, 610, 360)
	_wall(d, 525, 365, 560, 365)
	_wall(d, 590, 365, 685, 365)

	# Furniture and decoration
	var P := MapData.new_prop
	d["props"].append(P.call("table", Vector2(270, 448) * S, 1.5, 0.0, 11))
	d["props"].append(P.call("barrel", Vector2(215, 218) * S, 1.0, 0.0, 1))
	d["props"].append(P.call("barrel", Vector2(232, 218) * S, 1.0, 0.0, 2))
	d["props"].append(P.call("crate", Vector2(255, 222) * S, 1.0, 0.2, 3))
	d["props"].append(P.call("crate", Vector2(215, 245) * S, 0.9, 0.5, 4))
	d["props"].append(P.call("table", Vector2(380, 235) * S, 1.6, 0.0, 12))
	d["props"].append(P.call("table", Vector2(640, 410) * S, 1.0, 0.3, 13))
	d["props"].append(P.call("well", Vector2(790, 470) * S, 1.0, 0.0, 14))
	for t in [[270, 300], [405, 300], [580, 515], [310, 515], [650, 330], [455, 215]]:
		d["props"].append(P.call("torch", Vector2(t[0], t[1]) * S, 1.0, 0.0, 5))

	# Lights
	d["lights"].append(MapData.new_light(Vector2(390, 250) * S, 320.0, Color(1.0, 0.7, 0.4), 0.9, true))
	d["lights"].append(MapData.new_light(Vector2(580, 450) * S, 360.0, Color(1.0, 0.75, 0.45), 0.9, true))
	d["lights"].append(MapData.new_light(Vector2(270, 465) * S, 300.0, Color(1.0, 0.72, 0.4), 0.8, true))

	# Surrounding forest
	MapData.scatter_props(d, 95, 14, 14, 77)
	return d
