extends RefCounted
## Data for the country (overworld) map: a hand-drawn parchment map with named locations, each of
## which can be linked to a playable map.
##
## The map is a Dictionary:
##   seed: int                      (decides the generated mountains, rivers, rail line and trails)
##   locations: [{name, pos, icon, map}]
##     pos:  Vector2, normalised 0..1 across the map
##     icon: key of ICON_LABELS
##     map:  "" (nothing linked), "sample:<theme>" (a built-in sample map) or a map file path

## Per-device copy (what the editor writes).
const USER_PATH := "user://country_map.json"
## Copy that ships with the game. The editor also writes it when run from the Godot editor,
## so exported builds (e.g. a phone) get the map made on the PC.
const BUNDLED_PATH := "res://country_map.json"

## Size of the map in drawing units (16:9, same shape as the game window).
const MAP_SIZE := Vector2(1600, 900)

const SAMPLE_THEMES := ["fantasy", "train", "desert", "snow", "town", "swamp", "wagon"]

const ICON_ORDER := ["town", "station", "mine", "ranch", "fort", "camp", "wilderness"]
const ICON_LABELS := {
	"town": "Town",
	"station": "Rail station",
	"mine": "Mine",
	"ranch": "Ranch",
	"fort": "Fort",
	"camp": "Camp",
	"wilderness": "Wilderness",
}


## Landscape features, all editable: "river" and "rail" are open paths, "lake" and "ground" are
## closed shapes. A feature is {kind, pts: [Vector2 normalised], style?}; style is a GROUND_STYLES key.
const FEATURE_KINDS := ["river", "lake", "rail", "ground"]
const GROUND_ORDER := ["grass", "desert", "rock", "snow", "swamp"]
const GROUND_STYLES := {
	"grass": "Grassland",
	"desert": "Desert",
	"rock": "Rocky",
	"snow": "Snow",
	"swamp": "Marsh",
}
const COMPASS_POS := Vector2(1440, 770)


## Set when a map is started from a location on the country map. If that map is won, the game
## marks the location complete (see mark_complete). -1 = not started from the country map.
static var pending_id := -1
## Set by the game screen so the main menu opens straight on the country map.
static var open_map_screen := false

const PROGRESS_PATH := "user://country_progress.json"


static func _loc(id: int, loc_name: String, pos: Vector2, icon: String, map: String, description := "") -> Dictionary:
	return {"id": id, "name": loc_name, "pos": pos, "icon": icon, "map": map, "description": description}


static func default_data() -> Dictionary:
	var locs: Array = [
		_loc(1, "Dusty Creek", Vector2(0.27, 0.24), "town", "sample:town", "A quiet town on the creek. Word is the Redd gang rode in last night."),
		_loc(2, "Red Rock Station", Vector2(0.5, 0.4), "station", "sample:train", "The railroad stop. A payroll train is due, and not everyone on the platform is waiting to board."),
		_loc(3, "Silver Canyon", Vector2(0.2, 0.68), "mine", "sample:fantasy", "An abandoned silver mine, now a hideout for outlaws."),
		_loc(4, "Cactus Springs", Vector2(0.5, 0.78), "camp", "sample:desert", "A dry camp around the last water for fifty miles."),
		_loc(5, "Copper Ridge", Vector2(0.78, 0.3), "ranch", "sample:wagon", "A wagon trail through the ridge. Keep your eyes on the hills."),
	]
	var d := {"seed": 7, "locations": locs, "sequence": [1, 2, 4, 3, 5]}
	d.merge(generate_scenery(7, locs))
	return d


## A random landscape for the seed: two rivers, a rail line, a lake, two ground patches and a
## scatter of mountains kept clear of the locations. Returns {features, mountains}.
static func generate_scenery(map_seed: int, locs: Array) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var w := MAP_SIZE.x
	var h := MAP_SIZE.y
	var features: Array = []

	features.append(_river_feature(rng, rng.randf_range(260.0, 520.0), rng.randf_range(520.0, 760.0)))
	features.append(_river_feature(rng, rng.randf_range(1000.0, 1300.0), rng.randf_range(900.0, 1150.0)))

	var rail: Array = []
	var base_y := h * rng.randf_range(0.48, 0.6)
	var phase := rng.randf() * TAU
	var x := 40.0
	while x < w - 100.0:
		rail.append(Vector2(x, base_y + sin(x * 0.004 + phase) * 50.0) / MAP_SIZE)
		x += 130.0
	rail.append(Vector2(w - 40.0, base_y + sin((w - 40.0) * 0.004 + phase) * 50.0) / MAP_SIZE)
	features.append({"kind": "rail", "pts": rail})

	# What mountains and the lake must stay away from.
	var obstacles: Array = []  # Vector3(x, y, radius), map units
	for loc: Dictionary in locs:
		var lp: Vector2 = (loc["pos"] as Vector2) * MAP_SIZE
		obstacles.append(Vector3(lp.x, lp.y, 105.0))
	obstacles.append(Vector3(COMPASS_POS.x, COMPASS_POS.y, 125.0))
	for f: Dictionary in features:
		var pts: Array = f["pts"]
		for i in pts.size() - 1:
			var a: Vector2 = (pts[i] as Vector2) * MAP_SIZE
			var b: Vector2 = (pts[i + 1] as Vector2) * MAP_SIZE
			var steps := maxi(int(a.distance_to(b) / 24.0), 1)
			for k in steps + 1:
				var q := a.lerp(b, float(k) / steps)
				obstacles.append(Vector3(q.x, q.y, 48.0))

	# One lake, somewhere free.
	for attempt in 40:
		var c := Vector2(rng.randf_range(200.0, w - 300.0), rng.randf_range(200.0, h - 160.0))
		var blocked := false
		for o: Vector3 in obstacles:
			if c.distance_to(Vector2(o.x, o.y)) < o.z + 90.0:
				blocked = true
				break
		if blocked:
			continue
		var rx := rng.randf_range(60.0, 100.0)
		var ry := rng.randf_range(35.0, 60.0)
		var lake: Array = []
		for k in 10:
			var ang := TAU * k / 10.0
			var j := rng.randf_range(0.8, 1.2)
			lake.append((c + Vector2(cos(ang) * rx, sin(ang) * ry) * j) / MAP_SIZE)
		features.append({"kind": "lake", "pts": lake})
		for k in 8:
			var ang := TAU * k / 8.0
			obstacles.append(Vector3(c.x + cos(ang) * rx * 0.7, c.y + sin(ang) * ry * 0.7, 60.0))
		break

	# Ground patches: dry in the south-east, grassy in the north-west.
	var j2 := func() -> float: return rng.randf_range(-0.02, 0.02)
	features.append({"kind": "ground", "style": "desert", "pts": [
		Vector2(0.62 + j2.call(), 0.64 + j2.call()), Vector2(0.97, 0.56 + j2.call()),
		Vector2(0.97, 0.95), Vector2(0.55 + j2.call(), 0.95), Vector2(0.5 + j2.call(), 0.78 + j2.call()),
	]})
	features.append({"kind": "ground", "style": "grass", "pts": [
		Vector2(0.04, 0.08), Vector2(0.42 + j2.call(), 0.06), Vector2(0.38 + j2.call(), 0.32 + j2.call()),
		Vector2(0.04, 0.42 + j2.call()),
	]})

	var mountains: Array = []
	var placed := PackedVector2Array()
	var tries := 0
	while mountains.size() < 34 and tries < 700:
		tries += 1
		var p := Vector2(rng.randf_range(100.0, w - 100.0), rng.randf_range(150.0, h - 80.0))
		var center := p + Vector2(0, -30)
		var bad := false
		for o: Vector3 in obstacles:
			if center.distance_to(Vector2(o.x, o.y)) < o.z:
				bad = true
				break
		if bad:
			continue
		for q in placed:
			if p.distance_to(q) < 64.0:
				bad = true
				break
		if bad:
			continue
		placed.append(p)
		mountains.append({"pos": p / MAP_SIZE, "size": rng.randf_range(0.75, 1.3), "seed": rng.randi() % 100000})
	return {"features": features, "mountains": mountains}


static func _river_feature(rng: RandomNumberGenerator, x0: float, x1: float) -> Dictionary:
	var pts: Array = []
	var phase := rng.randf() * TAU
	var steps := 12
	for i in steps + 1:
		var t := float(i) / steps
		var y := lerpf(40.0, MAP_SIZE.y - 40.0, t)
		var cx := lerpf(x0, x1, t) + sin(t * 6.0 + phase) * 55.0 + sin(t * 15.0 + phase * 2.0) * 14.0
		pts.append(Vector2(cx, y) / MAP_SIZE)
	return {"kind": "river", "pts": pts}


## The saved country map, else the bundled one, else the built-in default.
static func load_data() -> Dictionary:
	for path in [USER_PATH, BUNDLED_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return _from_json(parsed)
	return default_data()


static func _from_json(d: Dictionary) -> Dictionary:
	var locs: Array = []
	var raw: Variant = d.get("locations", [])
	if raw is Array:
		for item: Variant in raw:
			if not (item is Dictionary):
				continue
			var pos := Vector2(0.5, 0.5)
			var p: Variant = item.get("pos", [])
			if p is Array and p.size() >= 2:
				pos = Vector2(clampf(float(p[0]), 0.0, 1.0), clampf(float(p[1]), 0.0, 1.0))
			var icon := str(item.get("icon", "town"))
			if not ICON_LABELS.has(icon):
				icon = "town"
			locs.append(_loc(int(item.get("id", -1)), str(item.get("name", "Location")), pos, icon, str(item.get("map", "")), str(item.get("description", ""))))
	# Every location needs a unique id (older files have none).
	var used := {}
	var max_id := 0
	for loc: Dictionary in locs:
		max_id = maxi(max_id, int(loc["id"]))
	for loc: Dictionary in locs:
		var id := int(loc["id"])
		if id <= 0 or used.has(id):
			max_id += 1
			loc["id"] = max_id
		used[int(loc["id"])] = true
	# Journey order: ids of the locations, first = start. Files without one use the list order.
	var seq: Array = []
	var raw_seq: Variant = d.get("sequence", null)
	if raw_seq is Array:
		for v: Variant in raw_seq:
			if used.has(int(v)) and not seq.has(int(v)):
				seq.append(int(v))
	else:
		for loc: Dictionary in locs:
			seq.append(int(loc["id"]))
	var map_seed := int(d.get("seed", 7))
	var out := {"seed": map_seed, "locations": locs, "sequence": seq}

	# Older files have no editable landscape yet: generate it from the seed.
	var raw_features: Variant = d.get("features", null)
	var raw_mountains: Variant = d.get("mountains", null)
	if not (raw_features is Array) or not (raw_mountains is Array):
		out.merge(generate_scenery(map_seed, locs))
		return out

	var features: Array = []
	for item: Variant in raw_features:
		if not (item is Dictionary):
			continue
		var kind := str(item.get("kind", ""))
		if not FEATURE_KINDS.has(kind):
			continue
		var f := {"kind": kind, "pts": _pts_from_json(item.get("pts", []))}
		if kind == "ground":
			var style := str(item.get("style", "grass"))
			f["style"] = style if GROUND_STYLES.has(style) else "grass"
		features.append(f)
	var mountains: Array = []
	for item: Variant in raw_mountains:
		if not (item is Dictionary):
			continue
		var pts := _pts_from_json([item.get("pos", [])])
		if pts.is_empty():
			continue
		mountains.append({
			"pos": pts[0],
			"size": clampf(float(item.get("size", 1.0)), 0.5, 2.0),
			"seed": int(item.get("seed", 0)),
		})
	out["features"] = features
	out["mountains"] = mountains
	return out


static func _pts_from_json(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		for p: Variant in raw:
			if p is Array and p.size() >= 2:
				out.append(Vector2(clampf(float(p[0]), 0.0, 1.0), clampf(float(p[1]), 0.0, 1.0)))
	return out


static func _pts_to_json(pts: Array) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append([snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)])
	return out


static func save_data(d: Dictionary) -> bool:
	var locs: Array = []
	for loc: Dictionary in d["locations"]:
		var pos: Vector2 = loc["pos"]
		locs.append({
			"id": loc["id"],
			"name": loc["name"],
			"pos": [snappedf(pos.x, 0.0001), snappedf(pos.y, 0.0001)],
			"icon": loc["icon"],
			"map": loc["map"],
			"description": loc["description"],
		})
	var features: Array = []
	for f: Dictionary in d["features"]:
		var item := {"kind": f["kind"], "pts": _pts_to_json(f["pts"])}
		if f.has("style"):
			item["style"] = f["style"]
		features.append(item)
	var mountains: Array = []
	for m: Dictionary in d["mountains"]:
		mountains.append({"pos": _pts_to_json([m["pos"]])[0], "size": snappedf(float(m["size"]), 0.01), "seed": m["seed"]})
	var text := JSON.stringify({"seed": d["seed"], "locations": locs, "sequence": d["sequence"], "features": features, "mountains": mountains}, "\t")
	var ok := _write(USER_PATH, text)
	if OS.has_feature("editor"):
		_write(BUNDLED_PATH, text)
	return ok


# ---------------------------------------------------------------- journey order and progress

static func next_id(d: Dictionary) -> int:
	var m := 0
	for loc: Dictionary in d["locations"]:
		m = maxi(m, int(loc["id"]))
	return m + 1


## 1-based place of a location in the journey (1 = start), 0 if it isn't part of it.
static func sequence_position(d: Dictionary, id: int) -> int:
	return (d["sequence"] as Array).find(id) + 1


## Puts a location at a place in the journey (1 = start). 0 takes it out of the journey.
static func set_sequence_position(d: Dictionary, id: int, place: int) -> void:
	var seq: Array = d["sequence"]
	seq.erase(id)
	if place > 0:
		seq.insert(mini(place - 1, seq.size()), id)


static func load_progress() -> Array:
	var out: Array = []
	if FileAccess.file_exists(PROGRESS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROGRESS_PATH))
		if parsed is Dictionary and parsed.get("completed") is Array:
			for v: Variant in parsed["completed"]:
				out.append(int(v))
	return out


static func mark_complete(id: int) -> void:
	var done := load_progress()
	if not done.has(id):
		done.append(id)
		_write(PROGRESS_PATH, JSON.stringify({"completed": done}))


static func reset_progress() -> void:
	_write(PROGRESS_PATH, JSON.stringify({"completed": []}))


## id of the location to play next: the first one in the journey that isn't complete. -1 if the
## whole journey is done.
static func current_id(d: Dictionary, completed: Array) -> int:
	for id: int in d["sequence"]:
		if not completed.has(id):
			return id
	return -1


## State of every location by id: "done", "current" (playable next) or "locked".
## A map with no journey set up leaves every location open.
static func states(d: Dictionary, completed: Array) -> Dictionary:
	var out := {}
	var seq: Array = d["sequence"]
	var current := current_id(d, completed)
	for loc: Dictionary in d["locations"]:
		var id := int(loc["id"])
		if seq.is_empty():
			out[id] = "current"
		elif not seq.has(id):
			out[id] = "locked"
		elif completed.has(id):
			out[id] = "done"
		elif id == current:
			out[id] = "current"
		else:
			out[id] = "locked"
	return out


static func location_name(d: Dictionary, id: int) -> String:
	for loc: Dictionary in d["locations"]:
		if int(loc["id"]) == id:
			return str(loc["name"])
	return ""


static func _write(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	return true


## Every map a location can be linked to: saved maps first, then the built-in samples.
## Each entry is {label, link}.
static func available_maps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MapData.MAP_DIR)
	if dir != null:
		var files: Array = Array(dir.get_files())
		files.sort_custom(func(a, b) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)
		for f: String in files:
			if f.get_extension() == "json":
				out.append({"label": f.get_basename(), "link": MapData.MAP_DIR.path_join(f)})
	for t: String in SAMPLE_THEMES:
		out.append({"label": "%s (sample)" % str(MapData.THEMES[t]["label"]), "link": "sample:%s" % t})
	return out
