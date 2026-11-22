class_name SampleMapMore
extends RefCounted
## Sample maps for the desert, snow, town, swamp and covered wagon themes (pixel coordinates on a 2048x1728 map).


static func _scatter_blobs(d: Dictionary, rng: RandomNumberGenerator, type: String, count: int, rmin: float, rmax: float) -> void:
	for i in count:
		var c := Vector2(rng.randf_range(0, 2048), rng.randf_range(0, 1728))
		d["polygons"].append(MapData.new_poly(type, SampleMap._blob(c, rng.randf_range(rmin, rmax), rng)))


## Walled room with a door gap in the bottom wall centred on `door_x` (the wall is one open polyline).
static func _room(d: Dictionary, x0: float, y0: float, x1: float, y1: float, door_x: float, width: float = 14.0) -> void:
	var pts := SampleMap._px([[door_x + 30, y1], [x1, y1], [x1, y0], [x0, y0], [x0, y1], [door_x - 30, y1]])
	d["walls"].append(MapData.new_wall(pts, false, width, "wall"))


static func _lights(d: Dictionary, list: Array, color: Color, energy: float, radius: float, flicker: bool) -> void:
	for p in list:
		d["lights"].append(MapData.new_light(Vector2(p[0], p[1]), radius, color, energy, flicker))


# ---------------------------------------------------------------- desert ruins

static func create_desert() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var d := MapData.empty("desert")
	d["spawn"] = Vector2(700, 1000)
	var P := MapData.new_prop

	_scatter_blobs(d, rng, "sand_dune", 18, 120, 280)
	_scatter_blobs(d, rng, "sandstone", 7, 60, 130)

	# Oasis with a sand rim
	var oasis_c := Vector2(380, 1300)
	d["polygons"].append(MapData.new_poly("sand_dune", SampleMap._organic(SampleMap._blob(oasis_c, 250, rng, 10), rng, 16.0, 2)))
	d["polygons"].append(MapData.new_poly("oasis", SampleMap._organic(SampleMap._blob(oasis_c, 175, rng, 10), rng, 14.0, 3)))

	# Ruined courtyard: tiles buried by drifting sand
	d["polygons"].append(MapData.new_poly("ruin_tile", SampleMap._prect(1000, 460, 1560, 960)))
	d["polygons"].append(MapData.new_poly("ruin_tile", SampleMap._prect(1220, 960, 1340, 1260)))  # processional road
	d["polygons"].append(MapData.new_poly("dark", SampleMap._prect(1180, 520, 1380, 640)))      # altar dais
	for c in [[1010, 470], [1550, 470], [1550, 950], [1000, 940], [1280, 960]]:
		d["polygons"].append(MapData.new_poly("sand_dune", SampleMap._blob(Vector2(c[0], c[1]), rng.randf_range(70, 120), rng)))
	d["polygons"].append(MapData.new_poly("shadow", SampleMap._prect(1000, 460, 1560, 478)))

	# Broken temple walls (gaps where they have collapsed)
	for seg in [
		[[1000, 460], [1160, 460]], [[1240, 460], [1420, 460]], [[1480, 460], [1560, 460]],
		[[1560, 460], [1560, 620]], [[1560, 700], [1560, 960]],
		[[1000, 460], [1000, 560]], [[1000, 640], [1000, 800]], [[1000, 860], [1000, 960]],
		[[1000, 960], [1200, 960]], [[1360, 960], [1560, 960]],
	]:
		d["walls"].append(MapData.new_wall(SampleMap._px(seg), false, 22.0, "wall"))

	# Pillar rows
	for i in 5:
		var y := 540.0 + i * 100.0
		var kind := "pillar" if i != 2 else "broken_pillar"
		d["props"].append(P.call(kind, Vector2(1100, y), 1.0, 0.0, 10 + i))
		d["props"].append(P.call("broken_pillar" if i == 3 else "pillar", Vector2(1460, y), 1.0, 0.0, 20 + i))
	for i in 3:
		d["props"].append(P.call("pillar", Vector2(1190 if i % 2 == 0 else 1370, 1010 + i * 100.0), 1.0, 0.0, 30 + i))
	d["props"].append(P.call("table", Vector2(1280, 580), 1.2, 0.0, 40))
	for t in [[1060, 520], [1500, 520], [1060, 900], [1500, 900], [1280, 700]]:
		d["props"].append(P.call("torch", Vector2(t[0], t[1]), 1.0, 0.0, 50))
	for i in 12:
		var a := rng.randf() * TAU
		d["props"].append(P.call("rubble", Vector2(1280, 720) + Vector2(cos(a), sin(a)) * rng.randf_range(60, 300), rng.randf_range(0.8, 1.4), rng.randf() * TAU, 60 + i))

	# Palms around the oasis
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.3
		d["props"].append(P.call("palm", oasis_c + Vector2(cos(a), sin(a)) * rng.randf_range(200, 250), rng.randf_range(0.9, 1.3), rng.randf() * TAU, 80 + i))
	d["props"].append(P.call("crate", Vector2(560, 1130), 1.1, 0.3, 90))
	d["props"].append(P.call("barrel", Vector2(600, 1160), 1.0, 0.0, 91))

	_lights(d, [[1280, 580], [1280, 820]], Color(1.0, 0.75, 0.45), 0.8, 380.0, true)
	d["lights"].append(MapData.new_light(oasis_c, 300.0, Color(0.5, 0.9, 0.85), 0.5, false))

	MapData.scatter_props(d, 20, 12, 14, 31)
	return d


# ---------------------------------------------------------------- snow / winter

static func create_snow() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1357
	var d := MapData.empty("snow")
	d["spawn"] = Vector2(560, 820)
	var P := MapData.new_prop

	_scatter_blobs(d, rng, "snow_deep", 22, 100, 240)

	# Frozen lake
	var lake_c := Vector2(1500, 1180)
	d["polygons"].append(MapData.new_poly("icy_water", SampleMap._organic(SampleMap._blob(lake_c, 300, rng, 10), rng, 20.0, 3)))
	d["polygons"].append(MapData.new_poly("ice", SampleMap._organic(SampleMap._blob(lake_c, 260, rng, 10), rng, 16.0, 3)))

	# Trodden path from the cabin to the lake
	var path := SampleMap._px([[520, 660], [620, 660], [700, 800], [900, 900], [1150, 1000], [1250, 1120], [1180, 1160], [1080, 1090], [880, 1020], [650, 930], [540, 790]])
	d["polygons"].append(MapData.new_poly("frozen_dirt", SampleMap._organic(path, rng, 10.0, 3)))

	# Cabin
	d["polygons"].append(MapData.new_poly("wood", SampleMap._prect(380, 380, 760, 660)))
	d["polygons"].append(MapData.new_poly("stone", SampleMap._prect(640, 400, 740, 480)))  # hearth
	d["polygons"].append(MapData.new_poly("carpet", SampleMap._prect(430, 450, 580, 560)))
	d["polygons"].append(MapData.new_poly("shadow", SampleMap._prect(380, 380, 760, 396)))
	_room(d, 380, 380, 760, 660, 570)
	d["props"].append(P.call("table", Vector2(505, 505), 1.0, 0.0, 1))
	d["props"].append(P.call("barrel", Vector2(410, 420), 1.0, 0.0, 2))
	d["props"].append(P.call("crate", Vector2(450, 415), 1.0, 0.2, 3))
	d["props"].append(P.call("crate", Vector2(725, 620), 1.0, 0.5, 4))
	d["props"].append(P.call("torch", Vector2(400, 640), 1.0, 0.0, 5))
	d["props"].append(P.call("torch", Vector2(740, 640), 1.0, 0.0, 6))
	d["props"].append(P.call("campfire", Vector2(690, 440), 0.8, 0.0, 7))

	# Camp outside
	d["props"].append(P.call("campfire", Vector2(900, 780), 1.0, 0.0, 8))
	d["props"].append(P.call("stump", Vector2(850, 740), 1.0, 0.0, 9))
	d["props"].append(P.call("stump", Vector2(950, 820), 1.0, 0.0, 10))
	d["props"].append(P.call("stump", Vector2(860, 840), 1.0, 0.0, 11))
	d["props"].append(P.call("snowman", Vector2(650, 740), 1.0, 0.0, 12))
	d["props"].append(P.call("snowman", Vector2(1010, 640), 1.2, 0.5, 13))
	d["props"].append(P.call("crate", Vector2(980, 760), 0.9, 0.1, 14))

	_lights(d, [[570, 520]], Color(1.0, 0.72, 0.42), 0.9, 360.0, true)
	d["lights"].append(MapData.new_light(lake_c, 360.0, Color(0.6, 0.8, 1.0), 0.35, false))

	MapData.scatter_props(d, 55, 12, 26, 41)
	return d


# ---------------------------------------------------------------- town / village

static func create_town() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8642
	var d := MapData.empty("town")
	d["spawn"] = Vector2(1024, 1080)
	var P := MapData.new_prop

	_scatter_blobs(d, rng, "grass_dark", 16, 90, 200)

	# Pond in the corner
	d["polygons"].append(MapData.new_poly("water", SampleMap._organic(SampleMap._blob(Vector2(1750, 1500), 170, rng, 10), rng, 12.0, 3)))

	# Roads: main street east-west, lane north-south, dirt track out of town
	d["polygons"].append(MapData.new_poly("cobble", SampleMap._prect(0, 1000, 2048, 1120)))
	d["polygons"].append(MapData.new_poly("cobble", SampleMap._prect(964, 160, 1084, 1728)))
	d["polygons"].append(MapData.new_poly("dirt", SampleMap._organic(SampleMap._px([[964, 1728], [1084, 1728], [1120, 1600], [1300, 1500], [1160, 1450], [980, 1560]]), rng, 12.0, 2)))
	# Plaza
	d["polygons"].append(MapData.new_poly("plaza", SampleMap._prect(804, 800, 1244, 1200)))
	d["polygons"].append(MapData.new_poly("shadow", SampleMap._prect(804, 800, 1244, 812)))

	# Houses: [x0, y0, x1, y1, floor, door_x]
	var houses := [
		[260, 640, 640, 940, "wood", 450],
		[1400, 620, 1800, 940, "wood", 1600],
		[260, 1230, 560, 1530, "wood", 410],
		[1400, 1230, 1740, 1480, "stone", 1570],
		[1160, 200, 1560, 460, "wood", 1360],
		[400, 180, 800, 440, "stone", 600],
	]
	for h in houses:
		d["polygons"].append(MapData.new_poly(h[4], SampleMap._prect(h[0], h[1], h[2], h[3])))
		d["polygons"].append(MapData.new_poly("shadow", SampleMap._prect(h[0], h[1], h[2], h[1] + 14)))
		_room(d, h[0], h[1], h[2], h[3], h[5])
	# Inner partition in the tavern
	d["walls"].append(MapData.new_wall(SampleMap._px([[1600, 620], [1600, 740]]), false, 10.0, "wall"))
	d["polygons"].append(MapData.new_poly("carpet", SampleMap._prect(1440, 780, 1560, 900)))

	# Furniture
	d["props"].append(P.call("table", Vector2(1500, 700), 1.2, 0.0, 1))
	d["props"].append(P.call("table", Vector2(1700, 820), 1.0, 0.4, 2))
	d["props"].append(P.call("barrel", Vector2(1430, 650), 1.0, 0.0, 3))
	d["props"].append(P.call("barrel", Vector2(1465, 650), 1.0, 0.0, 4))
	d["props"].append(P.call("table", Vector2(450, 780), 1.0, 0.0, 5))
	d["props"].append(P.call("crate", Vector2(290, 670), 1.0, 0.2, 6))
	d["props"].append(P.call("crate", Vector2(300, 1260), 1.0, 0.3, 7))
	d["props"].append(P.call("table", Vector2(1570, 1340), 1.0, 0.0, 8))
	d["props"].append(P.call("table", Vector2(1360, 330), 1.4, 0.0, 9))
	d["props"].append(P.call("barrel", Vector2(1190, 230), 1.0, 0.0, 10))
	d["props"].append(P.call("crate", Vector2(430, 215), 1.1, 0.2, 11))
	d["props"].append(P.call("torch", Vector2(1420, 640), 1.0, 0.0, 12))
	d["props"].append(P.call("torch", Vector2(1780, 640), 1.0, 0.0, 13))
	d["props"].append(P.call("torch", Vector2(280, 660), 1.0, 0.0, 14))

	# Plaza
	d["props"].append(P.call("fountain", Vector2(1024, 1000), 1.0, 0.0, 20))
	d["props"].append(P.call("stall", Vector2(880, 880), 1.0, 0.1, 21))
	d["props"].append(P.call("stall", Vector2(1168, 884), 1.0, -0.1, 22))
	d["props"].append(P.call("stall", Vector2(880, 1130), 1.0, PI, 23))
	d["props"].append(P.call("cart", Vector2(1170, 1140), 1.0, 0.3, 24))
	d["props"].append(P.call("haybale", Vector2(1215, 1090), 1.0, 0.2, 25))
	d["props"].append(P.call("well", Vector2(700, 1060), 1.0, 0.0, 26))
	d["props"].append(P.call("crate", Vector2(920, 840), 0.8, 0.0, 27))
	d["props"].append(P.call("barrel", Vector2(1210, 845), 0.9, 0.0, 28))
	for lp in [[830, 830], [1218, 830], [830, 1170], [1218, 1170], [980, 360], [980, 1450], [300, 1060], [1800, 1060]]:
		d["props"].append(P.call("lamppost", Vector2(lp[0], lp[1]), 1.0, 0.0, 30))
	for i in 5:
		d["props"].append(P.call("haybale", Vector2(1900 + (i % 2) * 40.0, 330 + i * 38.0), 1.0, rng.randf() * TAU, 40 + i))

	d["lights"].append(MapData.new_light(Vector2(1024, 1000), 420.0, Color(0.9, 0.92, 1.0), 0.45, false))
	_lights(d, [[1500, 780], [450, 790], [1360, 340]], Color(1.0, 0.75, 0.45), 0.8, 320.0, true)

	MapData.scatter_props(d, 34, 6, 28, 12)
	return d


# ---------------------------------------------------------------- swamp

static func create_swamp() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9753
	var d := MapData.empty("swamp")
	d["spawn"] = Vector2(300, 860)
	var P := MapData.new_prop

	_scatter_blobs(d, rng, "swamp_grass", 18, 100, 220)
	_scatter_blobs(d, rng, "mud", 8, 70, 150)

	# Bog pools
	var pools: Array = []
	for pc in [[700, 500, 230], [1300, 400, 190], [1500, 1000, 280], [800, 1300, 220], [1750, 1450, 150], [350, 300, 150]]:
		var c := Vector2(pc[0], pc[1])
		d["polygons"].append(MapData.new_poly("bog", SampleMap._organic(SampleMap._blob(c, pc[2], rng, 10), rng, 16.0, 3)))
		d["polygons"].append(MapData.new_poly("algae", SampleMap._organic(SampleMap._blob(c + Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30)), pc[2] * 0.75, rng, 9), rng, 10.0, 2)))
		pools.append([c, pc[2]])

	# Boardwalk across the swamp
	var board := SampleMap._px([[260, 840], [900, 840], [900, 780], [1000, 780], [1000, 1000], [1250, 1000], [1250, 1150], [1450, 1150], [1450, 1230], [1200, 1230], [1200, 1060], [940, 1060], [940, 900], [260, 900]])
	d["polygons"].append(MapData.new_poly("wood", board))

	# Stilt hut
	d["polygons"].append(MapData.new_poly("wood", SampleMap._prect(1300, 650, 1640, 880)))
	d["polygons"].append(MapData.new_poly("shadow", SampleMap._prect(1300, 650, 1640, 664)))
	d["polygons"].append(MapData.new_poly("wood", SampleMap._prect(1010, 780, 1300, 840)))  # bridge to hut
	_room(d, 1300, 650, 1640, 880, 1470, 12.0)
	d["props"].append(P.call("crate", Vector2(1340, 690), 1.0, 0.2, 1))
	d["props"].append(P.call("barrel", Vector2(1600, 690), 1.0, 0.0, 2))
	d["props"].append(P.call("barrel", Vector2(1570, 690), 1.0, 0.0, 3))
	d["props"].append(P.call("torch", Vector2(1320, 860), 1.0, 0.0, 4))
	d["props"].append(P.call("torch", Vector2(1620, 860), 1.0, 0.0, 5))
	d["props"].append(P.call("mushroom", Vector2(1580, 780), 1.4, 0.0, 6))

	# Water life and wisps over each pool
	var seed_i := 100
	for pl in pools:
		var c: Vector2 = pl[0]
		var r: float = pl[1]
		for i in 4:
			var a := rng.randf() * TAU
			d["props"].append(P.call("lilypad", c + Vector2(cos(a), sin(a)) * rng.randf_range(0.0, r * 0.55), rng.randf_range(0.9, 1.4), rng.randf() * TAU, seed_i))
			seed_i += 1
		for i in 6:
			var a2 := rng.randf() * TAU
			d["props"].append(P.call("reeds", c + Vector2(cos(a2), sin(a2)) * r * rng.randf_range(0.95, 1.15), rng.randf_range(0.8, 1.3), rng.randf() * TAU, seed_i))
			seed_i += 1
	for w in [[700, 520], [1500, 960], [820, 1280], [1300, 430]]:
		d["props"].append(P.call("wisp", Vector2(w[0], w[1]), 1.0, 0.0, 70))
	# Mist drifting over the water
	for c in [[900, 700], [1400, 1250], [600, 1100]]:
		d["polygons"].append(MapData.new_poly("mist", SampleMap._organic(SampleMap._blob(Vector2(c[0], c[1]), 260, rng, 10), rng, 20.0, 2)))

	MapData.scatter_props(d, 36, 22, 30, 21)
	return d


# ---------------------------------------------------------------- covered wagon / trail

## Builds one wagon from parts, centred on `c` and turned by `ang` (0 = hitch pointing up, -y):
## floor-board bed, side-board walls with a gap at the tailgate, four wheels, hitch, driver's seat,
## `cargo` ([[kind, local_x, local_y, loot?], ...]) and an optional curved canvas cover (`cover` = ROOFS key).
static func _wagon(d: Dictionary, c: Vector2, ang: float, cover: String, cargo: Array, seed_base: int) -> void:
	var P := MapData.new_prop
	var xf := Transform2D(ang, c)
	var hw := 42.0  # half width of the bed
	var hh := 84.0  # half length
	var T := func(x, y) -> Vector2: return xf * Vector2(x, y)  # wagon-local -> map position
	d["polygons"].append(MapData.new_poly("wagon_boards", PackedVector2Array([T.call(-hw, -hh), T.call(hw, -hh), T.call(hw, hh), T.call(-hw, hh)])))
	# Side boards all round except a gap at the back to climb in.
	d["walls"].append(MapData.new_wall(PackedVector2Array([T.call(-16, hh), T.call(-hw, hh), T.call(-hw, -hh), T.call(hw, -hh), T.call(hw, hh), T.call(16, hh)]), false, 6.0, "wagon"))
	var s := seed_base
	for wy in [-hh + 30.0, hh - 30.0]:  # front and rear axle
		for sx in [-1.0, 1.0]:
			d["props"].append(P.call("wagon_wheel", T.call(sx * (hw + 6.0), wy), 1.0, ang + (0.0 if sx > 0.0 else PI), s))
			s += 1
	d["props"].append(P.call("wagon_hitch", T.call(0, -hh - 58.0), 1.0, ang, s))
	d["props"].append(P.call("wagon_seat", T.call(0, -hh + 14.0), 1.0, ang, s + 1))
	s += 2
	for item in cargo:
		var loot: String = item[3] if item.size() > 3 else "none"
		var jitter := sin(float(s) * 12.9898) * 0.15  # small fixed tilt so cargo isn't perfectly lined up
		d["props"].append(P.call(item[0], T.call(item[1], item[2]), 1.0, ang + jitter, s, loot))
		s += 1
	if cover != "":
		# Canvas bonnet over the bed, rounded at both ends where the hoops curve down.
		var pts := PackedVector2Array()
		var cw := hw + 4.0
		var top := -hh + 26.0  # the driver's seat stays uncovered
		var bot := hh - 4.0
		for p in [[-cw + 8, top], [cw - 8, top], [cw, top + 10], [cw, bot - 10], [cw - 8, bot], [-cw + 8, bot], [-cw, bot - 10], [-cw, top + 10]]:
			pts.append(T.call(p[0], p[1]))
		d["roofs"].append(MapData.new_roof(cover, pts))


## Wagon train camped for the night beside the trail: wagons drawn up in a ring round a fire.
static func create_wagon() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1849
	var d := MapData.empty("wagon")
	d["spawn"] = Vector2(1024, 1060)
	var P := MapData.new_prop

	_scatter_blobs(d, rng, "grass", 16, 110, 240)
	_scatter_blobs(d, rng, "grass_dark", 8, 60, 140)

	# The trail: a band of packed ruts winding across the map.
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in 18:
		var x := -40.0 + i * 128.0
		var y := 300.0 + sin(i * 0.55) * 70.0
		top.append(Vector2(x, y - 70.0))
		bot.append(Vector2(x, y + 70.0))
	bot.reverse()
	d["polygons"].append(MapData.new_poly("wagon_ruts", SampleMap._organic(top + bot, rng, 8.0, 2)))

	# Camp ring round the fire at (1024, 1000).
	var fire := Vector2(1024, 1000)
	var camp := [
		# [angle round the ring, canvas cover (ROOFS key, "" = open wagon), cargo [kind, x, y, loot]]
		# Cargo sits along the sides (x = +/-24) so a walkway stays clear down the middle.
		[-PI * 0.5, "roof_canvas", [["barrel", -25, 30, "none"], ["sacks", 25, 42], ["trunk", 25, -20, "gold"], ["wagon_lantern", 0, 0]]],
		[-PI * 0.1, "roof_canvas_blue", [["crate", -24, 34, "pistol"], ["crate", 24, 34], ["bedroll", -24, -16], ["barrel", 26, -16]]],
		[PI * 0.3, "roof_canvas_dark", [["sacks", -25, 30], ["barrel", 25, 32, "food"], ["trunk", -25, -22, "gems"], ["wagon_lantern", 10, 0]]],
		[PI * 0.75, "", [["crate", -24, -20, "potion"], ["crate", 24, -20], ["barrel", -25, 30], ["sacks", 25, 34], ["haybale", 0, 6]]],
		[PI * 1.2, "roof_canvas", [["bedroll", -24, 10], ["bedroll", 24, 10], ["crate", 24, -40, "gems"], ["wagon_lantern", 0, 40]]],
	]
	var s := 500
	for i in camp.size():
		var a: float = camp[i][0]
		var pos := fire + Vector2(cos(a), sin(a)) * 330.0
		# Each wagon sits side-on to the fire, hitch pointing round the ring.
		_wagon(d, pos, a, camp[i][1], camp[i][2], s)
		s += 40

	# Camp life round the fire.
	d["props"].append(P.call("campfire", fire, 1.2, 0.0, 7))
	for k in 6:
		var a := TAU * float(k) / 6.0 + 0.4
		var kind: String = "stump" if k % 2 == 0 else "bedroll"
		d["props"].append(P.call(kind, fire + Vector2(cos(a), sin(a)) * rng.randf_range(80.0, 110.0), 1.0, a + PI * 0.5, 600 + k))
	d["props"].append(P.call("barrel", fire + Vector2(150, 40), 1.0, 0.0, 620, "none"))
	d["props"].append(P.call("crate", fire + Vector2(-140, 60), 1.0, 0.3, 621, "gold"))
	for h in [[1500, 1500], [560, 1520], [1700, 700]]:
		d["props"].append(P.call("haybale", Vector2(h[0], h[1]), 1.0, rng.randf() * PI, 630 + h[0] % 7))

	# Watering hole off to one side.
	var pond := Vector2(1700, 1350)
	d["polygons"].append(MapData.new_poly("mud", SampleMap._organic(SampleMap._blob(pond, 170, rng, 10), rng, 12.0, 2)))
	d["polygons"].append(MapData.new_poly("water", SampleMap._organic(SampleMap._blob(pond, 120, rng, 10), rng, 10.0, 3)))

	# A couple of hostile riders watching the camp from the trail.
	d["npcs"].append(MapData.new_npc("Outlaw", Vector2(600, 330), "rifle", "rifle", "hostile"))
	d["npcs"].append(MapData.new_npc("Outlaw", Vector2(1450, 280), "shotgun", "gold", "hostile"))
	d["npcs"].append(MapData.new_npc("Trail boss", fire + Vector2(60, 120), "pistol", "none", "friendly"))

	MapData.scatter_props(d, 10, 24, 30, 1849)
	return d
