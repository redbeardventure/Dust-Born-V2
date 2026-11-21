class_name MapRenderer
extends Node2D
## Builds the visual (and optionally physical) scene for a map Dictionary.
## Layers: terrain polygons -> walls -> props -> lights, plus a CanvasModulate for ambient light.

var data: Dictionary = {}
var physics_enabled := false
var lighting_enabled := true

var _terrain := Node2D.new()
var _walls := Node2D.new()
var _props := Node2D.new()
var _npcs := Node2D.new()
var _openings := Node2D.new()
var _lights := Node2D.new()
var _roofs := Node2D.new()
var _roof_items: Array = []  # [{node: Node2D, pts: PackedVector2Array, mats: Array[ShaderMaterial], alpha: float}]
var roofs_visible := true
var _mod := CanvasModulate.new()
var _flicker: Array = []
var _time := 0.0
var _canopies: Array = []

const CANOPY_FADE_ALPHA := 0.4

static var _light_tex: Texture2D
static var _water_shader: Shader

## Terrain types drawn with the animated water shader.
const WATER_TYPES := ["water", "oasis", "icy_water", "bog", "ocean", "lagoon", "sewer"]

## Water types drawn with the rough-sea shader (whitecaps) instead of the calm caustic one.
const ROUGH_WATER_TYPES := ["ocean"]

static var _ocean_shader: Shader


## Churning sea: warped, tileable fractal noise gives dark troughs and white foam streaks.
static func ocean_shader() -> Shader:
	if _ocean_shader == null:
		_ocean_shader = Shader.new()
		_ocean_shader.code = """
shader_type canvas_item;

float hash21(vec2 p, float per) {
	p = mod(p, per);
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i, per), hash21(i + vec2(1.0, 0.0), per), f.x),
			mix(hash21(i + vec2(0.0, 1.0), per), hash21(i + vec2(1.0, 1.0), per), f.x), f.y);
}

float fbm(vec2 p, float per) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p, per);
		p *= 2.0;
		per *= 2.0;
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.05;
	vec2 p = uv * 4.0;
	vec2 q = vec2(fbm(p + vec2(t, 0.0), 4.0), fbm(p + vec2(0.0, -t) + 3.7, 4.0));
	float n = fbm(p + 2.2 * (q - 0.5) + vec2(t * 0.5), 4.0);
	vec4 c = texture(TEXTURE, uv);
	// dark troughs and lighter swells
	c.rgb *= 0.65 + 0.8 * n;
	// foam: thin bright crests where the warped noise peaks, plus fine spray
	float crest = smoothstep(0.58, 0.72, n);
	float spray = smoothstep(0.62, 0.9, fbm(p * 3.0 + 4.0 * q + vec2(-t, t), 12.0));
	vec3 foam = vec3(0.88, 0.96, 1.0);
	c.rgb = mix(c.rgb, foam, clamp(crest * 0.7 + spray * 0.5 * crest, 0.0, 0.9));
	COLOR = c;
}
"""
	return _ocean_shader


## Ripples the texture and adds drifting light glints. Texture UVs are in 0..1 per tile.
static func water_shader() -> Shader:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = """
shader_type canvas_item;

// Tileable caustic web: bright wobbly light lines over deeper water (pool-surface look).
float caustic(vec2 uv, float t) {
	const float TAU_C = 6.28318530718;
	vec2 p = fract(uv) * TAU_C - 250.0;
	vec2 i = p;
	float c = 1.0;
	float inten = 0.012;
	for (int n = 0; n < 5; n++) {
		float tt = t * (1.0 - 3.5 / float(n + 1));
		i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x));
		c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / inten), p.y / (cos(i.y + tt) / inten)));
	}
	c /= 5.0;
	c = 1.17 - pow(c, 1.4);
	return clamp(pow(abs(c), 8.0), 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV;
	// slow wobble of the base texture
	uv += 0.004 * vec2(sin(uv.y * 40.0 + TIME * 0.2), cos(uv.x * 36.0 + TIME * 0.17));
	vec4 c = texture(TEXTURE, uv);
	float t = TIME * 0.06 + 23.0;
	float k = caustic(uv, t);
	float soft = caustic(uv * 1.0 + 0.02, t * 0.8);
	c.rgb *= 0.88 + 0.08 * sin(TIME * 0.6 + uv.x * 12.0);
	// pale cyan glow around lines plus sharp bright cores
	c.rgb += vec3(0.25, 0.55, 0.75) * soft * 0.35;
	c.rgb = mix(c.rgb, vec3(0.8, 0.95, 1.0), clamp(k * 0.85, 0.0, 1.0));
	COLOR = c;
}
"""
	return _water_shader


func _init() -> void:
	_terrain.name = "Terrain"
	_walls.name = "Walls"
	_props.name = "Props"
	_npcs.name = "Npcs"
	_openings.name = "Openings"
	_lights.name = "Lights"
	add_child(_mod)
	add_child(_terrain)
	add_child(_walls)
	add_child(_openings)
	add_child(_props)
	add_child(_npcs)
	add_child(_lights)
	_roofs.name = "Roofs"
	_roofs.z_index = ROOF_Z
	add_child(_roofs)


static func light_texture() -> Texture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.4, 0.4, 0.4, 0.4), Color(0, 0, 0, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 256
		t.height = 256
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_light_tex = t
	return _light_tex


func build(d: Dictionary) -> void:
	data = d
	rebuild_all()


func rebuild_all() -> void:
	rebuild_terrain()
	rebuild_openings()  # also rebuilds the walls, which are cut around openings
	rebuild_props()
	rebuild_npcs()
	rebuild_roofs()
	refresh_ambient()


func set_lighting(on: bool) -> void:
	lighting_enabled = on
	refresh_ambient()
	for l in _lights.get_children():
		l.visible = on


func refresh_ambient() -> void:
	var amb: Color = data.get("ambient", Color.WHITE)
	_mod.color = amb if lighting_enabled else Color.WHITE


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ---------------------------------------------------------------- terrain

func rebuild_terrain() -> void:
	_clear(_terrain)
	var size: Vector2 = data["size"]
	var bg := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	_terrain.add_child(_make_poly(str(data["background"]), bg, true))
	for p in data["polygons"]:
		var pts: PackedVector2Array = p["points"]
		if pts.size() >= 3:
			_terrain.add_child(_make_poly(p["type"], pts))
	if physics_enabled:
		_build_water_blockers()


## The player may wade only this far (pixels) into water from the shore.
const WADE_DEPTH := 28.0


## Solid collision over the deep part of each water polygon (the polygon shrunk by WADE_DEPTH).
## Solid terrain drawn later on top (ice, wood bridges, stone...) is cut out so it stays walkable.
func _build_water_blockers() -> void:
	var polys: Array = data["polygons"]
	for i in polys.size():
		var p: Dictionary = polys[i]
		if not WATER_TYPES.has(p["type"]) or p["points"].size() < 3:
			continue
		var pieces: Array = Geometry2D.offset_polygon(p["points"], -WADE_DEPTH, Geometry2D.JOIN_ROUND)
		for j in range(i + 1, polys.size()):
			var t: String = polys[j]["type"]
			var tdef: Dictionary = MapData.TERRAIN.get(t, {})
			if WATER_TYPES.has(t) or not tdef.get("blocks_scatter", false) or polys[j]["points"].size() < 3:
				continue
			pieces = _subtract_solid(pieces, polys[j]["points"])
		var body := StaticBody2D.new()
		body.collision_layer = 2  # layer 2 = water: blocks walking, not projectiles or line of sight
		for piece in pieces:
			if piece.size() < 3:
				continue
			var cp := CollisionPolygon2D.new()
			cp.polygon = piece
			body.add_child(cp)
		_terrain.add_child(body)


static func _signed_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a * 0.5


## Subtracts `sub` from every polygon in `pieces`. Results never contain holes: when the cut
## leaves one, the shape is split along a vertical line through the hole so every piece is solid.
static func _subtract_solid(pieces: Array, sub: PackedVector2Array) -> Array:
	var out: Array = []
	for piece in pieces:
		var res: Array = Geometry2D.clip_polygons(piece, sub)
		var ref := signf(_signed_area(piece))
		var outers: Array = []
		var holes: Array = []
		for r in res:
			if signf(_signed_area(r)) == ref:
				outers.append(r)
			else:
				holes.append(r)
		for h in holes:
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for v in h:
				lo = lo.min(v)
				hi = hi.max(v)
			var cx := (lo.x + hi.x) * 0.5
			var big := 100000.0
			var left := PackedVector2Array([Vector2(-big, -big), Vector2(cx, -big), Vector2(cx, big), Vector2(-big, big)])
			var right := PackedVector2Array([Vector2(cx, -big), Vector2(big, -big), Vector2(big, big), Vector2(cx, big)])
			var split: Array = []
			for o in outers:
				for half in [left, right]:
					for part in Geometry2D.intersect_polygons(o, half):
						if signf(_signed_area(part)) == ref:
							split.append_array(Geometry2D.clip_polygons(part, h))
			outers = split
		out.append_array(outers)
	return out


const DEPTH_STEPS := 32
const DEPTH_ALPHA := 0.045
const DEPTH_COLOR := Color(0.01, 0.05, 0.16)


## Water depth: stacked, progressively smaller copies of the shape, each tinted dark.
## Every ring adds a little darkness, so the water gets deeper toward the centre. The step
## size follows the shape's width so even large lakes reach full depth in the middle.
func _add_depth_rings(holder: Node2D, pts: PackedVector2Array) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in pts:
		lo = lo.min(v)
		hi = hi.max(v)
	var span := minf(hi.x - lo.x, hi.y - lo.y)
	var step := clampf(span * 0.5 / float(DEPTH_STEPS), 3.0, 40.0)
	for i in range(1, DEPTH_STEPS + 1):
		var pieces: Array = Geometry2D.offset_polygon(pts, -step * float(i), Geometry2D.JOIN_ROUND)
		if pieces.is_empty():
			break
		for piece in pieces:
			if piece.size() < 3 or _signed_area(piece) * _signed_area(pts) < 0.0:
				continue
			var ring := Polygon2D.new()
			ring.polygon = piece
			ring.color = Color(DEPTH_COLOR, DEPTH_ALPHA)
			holder.add_child(ring)


func _make_poly(type: String, pts: PackedVector2Array, is_background := false) -> Node2D:
	var holder := Node2D.new()
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.uv = pts
	poly.texture = MapData.get_texture(type)
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if WATER_TYPES.has(type):
		var mat := ShaderMaterial.new()
		mat.shader = ocean_shader() if ROUGH_WATER_TYPES.has(type) else water_shader()
		poly.material = mat
		if not is_background:
			_add_water_edge(holder, poly, type, pts)
	holder.add_child(poly)
	if WATER_TYPES.has(type) and not is_background:
		_add_depth_rings(holder, pts)
	var def: Dictionary = MapData.TERRAIN.get(type, MapData.TERRAIN["grass"])
	var oc: Color = def["outline"]
	if oc.a > 0.0:
		var line := Line2D.new()
		line.points = pts
		line.closed = true
		line.width = 3.0
		line.default_color = oc
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		holder.add_child(line)
	return holder


## Shoreline colours per water type: bank (outside), pebbles, shallow band and foam (inside).
const WATER_EDGE := {
	"water": {"bank": Color("7a6a4c"), "pebble_a": Color("8d8a80"), "pebble_b": Color("b8b2a2"), "shallow": Color("7fd0dc"), "foam": Color("eafcff")},
	"oasis": {"bank": Color("c9a46a"), "pebble_a": Color("b08a5a"), "pebble_b": Color("dcc294"), "shallow": Color("86dcc8"), "foam": Color("f0fff8")},
	"icy_water": {"bank": Color("b8cfdc"), "pebble_a": Color("8a96a0"), "pebble_b": Color("dfeaf2"), "shallow": Color("9fd2ea"), "foam": Color("ffffff")},
	"bog": {"bank": Color("4e3f2b"), "pebble_a": Color("5a5040"), "pebble_b": Color("7a6e58"), "shallow": Color("66783e"), "foam": Color("9aa860")},
	"ocean": {"bank": Color("6f6c66"), "pebble_a": Color("5f5d58"), "pebble_b": Color("9a968d"), "shallow": Color("5fc4e0"), "foam": Color("ffffff")},
	"lagoon": {"bank": Color("e0c58a"), "pebble_a": Color("c9a468"), "pebble_b": Color("f0e0b0"), "shallow": Color("8ff0e0"), "foam": Color("f4fffc")},
	"sewer": {"bank": Color("5a5650"), "pebble_a": Color("46433e"), "pebble_b": Color("6e6a62"), "shallow": Color("6f8a52"), "foam": Color("b0bf78")},
}


## Builds the shoreline: a bank strip with pebbles under the water, and a lighter shallow band
## plus a foam line clipped to the inside of the water polygon.
func _add_water_edge(holder: Node2D, poly: Polygon2D, type: String, pts: PackedVector2Array) -> void:
	var e: Dictionary = WATER_EDGE[type]
	# Bank: lines centred on the edge, drawn under the water so only the outer half shows.
	holder.add_child(_edge_line(pts, 34.0, Color(0, 0, 0, 0.22)))
	holder.add_child(_edge_line(pts, 28.0, e["bank"]))
	holder.add_child(_edge_line(pts, 14.0, Color(e["bank"]).lightened(0.15)))
	# Pebbles scattered just outside the edge (seeded from the shape so they don't change on rebuild).
	var pebbles := Node2D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pts)
	var stones: Array = []
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var seg := b - a
		var length := seg.length()
		if length < 1.0:
			continue
		var nrm := seg.orthogonal().normalized()
		if Geometry2D.is_point_in_polygon(a + seg * 0.5 + nrm * 4.0, pts):
			nrm = -nrm
		var count := int(length / 9.0)
		for k in count:
			var p := a + seg * rng.randf() + nrm * rng.randf_range(3.0, 13.0)
			stones.append([p, rng.randf_range(1.6, 3.6), Color(e["pebble_a"]).lerp(e["pebble_b"], rng.randf())])
	pebbles.draw.connect(func() -> void:
		for s in stones:
			pebbles.draw_circle(s[0] + Vector2(0.8, 1.0), s[1], Color(0, 0, 0, 0.3))
			pebbles.draw_circle(s[0], s[1], s[2])
			pebbles.draw_circle(s[0] - Vector2(0.5, 0.6), s[1] * 0.45, Color(s[2]).lightened(0.25)))
	holder.add_child(pebbles)
	# Inside the water: shallow band and foam, clipped to the polygon.
	poly.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var shallow: Color = e["shallow"]
	poly.add_child(_edge_line(pts, 46.0, Color(shallow, 0.25)))
	poly.add_child(_edge_line(pts, 26.0, Color(shallow, 0.45)))
	poly.add_child(_edge_line(pts, 9.0, Color(e["foam"], 0.55)))
	poly.add_child(_edge_line(pts, 3.5, Color(e["foam"], 0.85)))


func _edge_line(pts: PackedVector2Array, width: float, col: Color) -> Line2D:
	var line := Line2D.new()
	line.points = pts
	line.closed = true
	line.width = width
	line.default_color = col
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	return line


# ---------------------------------------------------------------- walls

func rebuild_walls() -> void:
	_clear(_walls)
	var openings: Array = data.get("openings", [])
	for w in data["walls"]:
		var pts: PackedVector2Array = w["points"]
		if pts.size() < 2:
			continue
		var closed: bool = w["closed"]
		var width: float = w["width"]
		var style: String = w.get("style", "wall")
		if style == "rail":
			# Tracks are decoration only: no light occluder, no collision.
			var rn := RailNode.new()
			rn.points = pts
			rn.closed = closed
			rn.width = width
			_walls.add_child(rn)
			continue
		# Doors and windows cut a gap in the wall they sit on.
		var cuts: Array = []
		for o in openings:
			if MapData.dist_to_path(o["pos"], pts, closed) < OPENING_SNAP:
				cuts.append(o)
		if cuts.is_empty():
			_add_wall_piece(pts, closed, width, style)
			continue
		var path := PackedVector2Array(pts)
		if closed:
			path.append(pts[0])
		var pieces: Array = [path]
		for o in cuts:
			pieces = _cut_pieces(pieces, o["pos"], float(o["width"]) * 0.5)
		for pc in pieces:
			_add_wall_piece(pc, false, width, style, true)


## How close (px) an opening must be to a wall's centre line to cut it.
const OPENING_SNAP := 6.0


static func _path_length(pts: PackedVector2Array) -> float:
	var l := 0.0
	for i in pts.size() - 1:
		l += pts[i].distance_to(pts[i + 1])
	return l


## Removes the stretch of every open path in `pieces` that lies within `hw` of `center` along the wall.
static func _cut_pieces(pieces: Array, center: Vector2, hw: float) -> Array:
	var out: Array = []
	for pc in pieces:
		var pts: PackedVector2Array = pc
		var best_i := -1
		var best_d := OPENING_SNAP
		for i in pts.size() - 1:
			var d := center.distance_to(Geometry2D.get_closest_point_to_segment(center, pts[i], pts[i + 1]))
			if d < best_d:
				best_d = d
				best_i = i
		if best_i < 0:
			out.append(pts)
			continue
		var a := pts[best_i]
		var seg := pts[best_i + 1] - a
		var seg_len := seg.length()
		if seg_len < 0.01:
			out.append(pts)
			continue
		var dir := seg / seg_len
		var t := clampf((center - a).dot(dir), 0.0, seg_len)
		var first := PackedVector2Array()
		for k in range(0, best_i + 1):
			first.append(pts[k])
		first.append(a + dir * maxf(t - hw, 0.0))
		var second := PackedVector2Array([a + dir * minf(t + hw, seg_len)])
		for k in range(best_i + 1, pts.size()):
			second.append(pts[k])
		if _path_length(first) > 1.0:
			out.append(first)
		if _path_length(second) > 1.0:
			out.append(second)
	return out


## Draws one wall (or one piece of a cut wall) with its shadow, light occluder and collision.
## `flat_ends` squares off the ends (used where a door/window gap was cut) so the wall stops exactly at the frame.
func _add_wall_piece(pts: PackedVector2Array, closed: bool, width: float, style: String, flat_ends: bool = false) -> void:
	var edge := Color(0.12, 0.1, 0.09)
	var col_body := Color(0.52, 0.49, 0.44)
	var hi := Color(0.7, 0.67, 0.6)
	if style == "hull":
		edge = Color(0.05, 0.05, 0.06)
		col_body = Color(0.24, 0.26, 0.31)
		hi = Color(0.38, 0.41, 0.48)
	elif style == "wagon":  # wooden side boards of a wagon bed
		edge = Color(0.1, 0.06, 0.03)
		col_body = Color(0.42, 0.27, 0.15)
		hi = Color(0.58, 0.4, 0.23)
	_walls.add_child(_wall_line(pts, closed, width + 8.0, Color(0, 0, 0, 0.28), Vector2(5, 7), flat_ends))
	_walls.add_child(_wall_line(pts, closed, width + 5.0, edge, Vector2.ZERO, flat_ends))
	_walls.add_child(_wall_line(pts, closed, width, col_body, Vector2.ZERO, flat_ends))
	_walls.add_child(_wall_line(pts, closed, width * 0.4, hi, Vector2.ZERO, flat_ends))
	var path := PackedVector2Array(pts)
	if closed:
		path.append(pts[0])
	var occ := OccluderPolygon2D.new()
	occ.closed = false
	occ.polygon = path
	var lo := LightOccluder2D.new()
	lo.occluder = occ
	_walls.add_child(lo)
	if physics_enabled:
		var body := StaticBody2D.new()
		for i in path.size() - 1:
			var cs := CollisionShape2D.new()
			var seg := SegmentShape2D.new()
			seg.a = path[i]
			seg.b = path[i + 1]
			cs.shape = seg
			body.add_child(cs)
		_walls.add_child(body)


func _wall_line(pts: PackedVector2Array, closed: bool, width: float, col: Color, off: Vector2, flat_ends: bool = false) -> Line2D:
	var line := Line2D.new()
	line.points = pts
	line.closed = closed
	line.width = width
	line.default_color = col
	line.position = off
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	var cap := Line2D.LINE_CAP_NONE if flat_ends else Line2D.LINE_CAP_ROUND
	line.begin_cap_mode = cap
	line.end_cap_mode = cap
	return line


# ---------------------------------------------------------------- props

func rebuild_props() -> void:
	_clear(_props)
	_canopies.clear()
	for pr in data["props"]:
		var def: Dictionary = MapData.PROPS.get(pr["type"], MapData.PROPS["tree"])
		var sc: float = pr["scale"]
		var is_horse := MapData.HORSE_PROPS.has(pr["type"])
		if physics_enabled and (is_horse or MapData.COW_PROPS.has(pr["type"])):
			# Play-test: a live animal that wanders; horses can also be ridden (the editor shows a still prop).
			var horse := HorseNode.new()
			horse.rideable = is_horse
			horse.kind = pr["type"]
			horse.seed_v = pr["seed"]
			horse.size_scale = sc
			horse.heading = pr["rot"]
			horse.position = pr["pos"]
			_props.add_child(horse)
			continue
		var node := PropNode.new()
		node.kind = pr["type"]
		node.seed_v = pr["seed"]
		node.position = pr["pos"]
		node.rotation = pr["rot"]
		node.scale = Vector2(sc, sc)
		if physics_enabled and MapData.LOOT_PROPS.has(pr["type"]):
			node.make_interactive(str(pr.get("loot", "none")))  # selectable; barrels can be shot
		if def.get("fade", false):
			# Canopies and smoke draw above the player and fade when covering them.
			node.z_index = 10
			_canopies.append(node)
		_props.add_child(node)
		var solid: float = def["solid"]
		var rect: Vector2 = def.get("rect", Vector2.ZERO)
		var occ_pts := PackedVector2Array()
		if rect != Vector2.ZERO:
			var h := rect * 0.5
			occ_pts = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
		elif solid > 0.0:
			for i in 8:
				var a := TAU * float(i) / 8.0
				occ_pts.append(Vector2(cos(a), sin(a)) * solid * 0.9)
		if occ_pts.size() > 0:
			var occ := OccluderPolygon2D.new()
			occ.polygon = occ_pts
			var lo := LightOccluder2D.new()
			lo.occluder = occ
			node.add_child(lo)
			if physics_enabled:
				var body := StaticBody2D.new()
				var cs := CollisionShape2D.new()
				if rect != Vector2.ZERO:
					var rs := RectangleShape2D.new()
					rs.size = rect
					cs.shape = rs
				else:
					var circ := CircleShape2D.new()
					circ.radius = solid
					cs.shape = circ
				body.add_child(cs)
				node.add_child(body)
	rebuild_lights()


# ---------------------------------------------------------------- doors and windows

## Rebuilds the door/window nodes and the walls (walls are cut open where an opening sits).
func rebuild_openings() -> void:
	rebuild_walls()
	_clear(_openings)
	for o in data.get("openings", []):
		var node := OpeningNode.new()
		node.kind = str(o["kind"])
		node.width = float(o["width"])
		node.thick = float(o["thick"])
		node.physics = physics_enabled
		node.position = o["pos"]
		node.rotation = float(o["rot"])
		_openings.add_child(node)


## Closest door to `pos` that is within its own reach, or null.
func nearest_door(pos: Vector2, reach: float = 36.0) -> OpeningNode:
	var best: OpeningNode = null
	var best_d := INF
	for n in _openings.get_children():
		var op := n as OpeningNode
		if op == null or op.kind != "door":
			continue
		var d := op.position.distance_to(pos)
		if d < op.width * 0.5 + reach and d < best_d:
			best_d = d
			best = op
	return best


# ---------------------------------------------------------------- npcs

## NPCs only wander when physics_enabled is on (play-test); in the editor they stand still.
func rebuild_npcs() -> void:
	_clear(_npcs)
	for n in data.get("npcs", []):
		var node := NpcNode.new()
		node.npc_name = str(n["name"])
		node.weapon = str(n["weapon"])
		node.disposition = str(n["disposition"])
		node.loot = str(n.get("loot", "none"))
		node.patrol = n["patrol"]
		node.head = int(n.get("head", -1))
		node.animate = physics_enabled
		node.position = n["pos"]
		_npcs.add_child(node)


# ---------------------------------------------------------------- lights

func rebuild_lights() -> void:
	_clear(_lights)
	_flicker.clear()
	for l in data["lights"]:
		_add_light(l["pos"], l["radius"], l["color"], l["energy"], l["flicker"])
	for pr in data["props"]:
		var lt: Dictionary = MapData.PROPS.get(pr["type"], {}).get("light", {})
		if not lt.is_empty():
			_add_light(pr["pos"], float(lt["r"]) * float(pr["scale"]), lt["c"], float(lt["e"]), true)


func _add_light(pos: Vector2, radius: float, color: Color, energy: float, flicker: bool) -> void:
	var l := PointLight2D.new()
	l.texture = light_texture()
	l.texture_scale = radius / 128.0
	l.position = pos
	l.color = color
	l.energy = energy
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.visible = lighting_enabled
	_lights.add_child(l)
	if flicker:
		_flicker.append([l, energy, randf() * TAU])


# ---------------------------------------------------------------- roofs

## Roofs draw above props, characters and projectiles (but below the on-map markers).
const ROOF_Z := 18
## Up to this many windows / open doors can be seen through at once, per roof.
const MAX_VIEW_CONES := 8
## Farthest a viewer can see into a building through an opening (px).
const MAX_VIEW_DIST := 900.0
## Roofs are slightly see-through in the editor so the floor plan stays readable.
const EDITOR_ROOF_ALPHA := 0.88

static var _roof_shader: Shader


## Roof shader: ordinary textured polygon, except pixels inside a "view cone" are discarded.
## A cone starts at the viewer and passes through an opening (e1..e2); everything beyond the
## opening inside the cone is cut away, so you can see the inside of the building through it.
static func roof_shader() -> Shader:
	if _roof_shader == null:
		_roof_shader = Shader.new()
		_roof_shader.code = """
shader_type canvas_item;

uniform vec2 viewer = vec2(0.0);
uniform int cone_count = 0;
uniform vec2 edge_a[8];
uniform vec2 edge_b[8];

varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 v = wpos - viewer;
	for (int i = 0; i < 8; i++) {
		if (i >= cone_count) {
			break;
		}
		vec2 da = edge_a[i] - viewer;
		vec2 db = edge_b[i] - viewer;
		float ca = da.x * v.y - da.y * v.x;
		float cb = db.x * v.y - db.y * v.x;
		vec2 mid = (edge_a[i] + edge_b[i]) * 0.5;
		bool between = ca * cb <= 0.0;
		bool beyond = dot(wpos - mid, mid - viewer) > 0.0;
		if (between && beyond) {
			discard;
		}
	}
}
"""
	return _roof_shader


func _roof_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = roof_shader()
	return m


## Max roof outline vertices the shaded shader handles (extra vertices are ignored).
const ROOF_MAX_SEGS := 64

static var _roof_shaded_shader: Shader


## Shaded roof: every pixel finds its nearest roof edge. That edge's slope direction picks the
## light/dark facet (so a rectangle becomes a hip roof and a square a pyramid), the spot where
## the nearest edge changes becomes a ridge / hip / valley line, and the texture rows are turned
## to run parallel to the eave. "Round" roofs (wagon canvas, train cars) shade smoothly instead.
static func roof_shaded_shader() -> Shader:
	if _roof_shaded_shader == null:
		_roof_shaded_shader = Shader.new()
		_roof_shaded_shader.code = """
shader_type canvas_item;

uniform vec2 viewer = vec2(0.0);
uniform int cone_count = 0;
uniform vec2 edge_a[8];
uniform vec2 edge_b[8];

uniform int seg_count = 0;
uniform vec2 seg_a[64];
uniform vec2 seg_b[64];
uniform float orient = 1.0;
uniform float max_d = 40.0;
uniform float round_roof = 0.0;
uniform vec2 light_dir = vec2(-0.55, -0.83);

varying vec2 wpos;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vcol = COLOR;  // includes the node's modulate (used for fading)
}

void fragment() {
	vec2 v = wpos - viewer;
	for (int i = 0; i < 8; i++) {
		if (i >= cone_count) {
			break;
		}
		vec2 da = edge_a[i] - viewer;
		vec2 db = edge_b[i] - viewer;
		float ca = da.x * v.y - da.y * v.x;
		float cb = db.x * v.y - db.y * v.x;
		vec2 mid = (edge_a[i] + edge_b[i]) * 0.5;
		if (ca * cb <= 0.0 && dot(wpos - mid, mid - viewer) > 0.0) {
			discard;
		}
	}
	float d1 = 1e9;
	float d2 = 1e9;
	vec2 n1 = vec2(0.0);
	vec2 t1 = vec2(1.0, 0.0);
	for (int i = 0; i < 64; i++) {
		if (i >= seg_count) {
			break;
		}
		vec2 a = seg_a[i];
		vec2 ab = seg_b[i] - a;
		float l2 = max(dot(ab, ab), 0.0001);
		float h = clamp(dot(wpos - a, ab) / l2, 0.0, 1.0);
		float d = length(wpos - a - ab * h);
		vec2 t = ab * inversesqrt(l2);
		vec2 n = vec2(t.y, -t.x) * orient;
		if (d < d1) {
			if (dot(n, n1) < 0.98) {
				d2 = d1;
			}
			d1 = d;
			n1 = n;
			t1 = t;
		} else if (d < d2 && dot(n, n1) < 0.98) {
			d2 = d;
		}
	}
	vec2 q = vec2(dot(wpos, t1), dot(wpos, n1));
	vec4 tex = texture(TEXTURE, q * TEXTURE_PIXEL_SIZE);
	float lit = dot(n1, normalize(light_dir));
	vec3 col;
	if (round_roof > 0.5) {
		// Barrel / curved roof: surface tilts away from the crown, so shading eases off toward the middle.
		float tilt = 1.0 - clamp(d1 / max_d, 0.0, 1.0);
		col = tex.rgb * (1.0 + 0.45 * lit * tilt);
		col *= mix(0.78, 1.0, smoothstep(0.0, max_d, d1));
	} else {
		col = tex.rgb * (1.0 + 0.34 * lit);
		float ridge = 1.0 - smoothstep(0.0, 2.2, d2 - d1);
		col = mix(col, col * 0.6, ridge * 0.85);
		col *= mix(0.84, 1.0, smoothstep(0.0, 16.0, d1));
	}
	COLOR = vec4(col, tex.a) * vcol;
}
"""
	return _roof_shaded_shader


func _roof_shaded_material(pts: PackedVector2Array, round_roof: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = roof_shaded_shader()
	var n := pts.size()
	var area := 0.0
	for i in n:
		area += pts[i].cross(pts[(i + 1) % n])
	var sa := PackedVector2Array()
	var sb := PackedVector2Array()
	for i in mini(n, ROOF_MAX_SEGS):
		sa.append(pts[i])
		sb.append(pts[(i + 1) % n])
	var count := sa.size()
	while sa.size() < ROOF_MAX_SEGS:
		sa.append(Vector2.ZERO)
		sb.append(Vector2.ZERO)
	# Deepest point inside (coarse grid search): how far the roof rises from eave to crown.
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	var best := 8.0
	for gx in 14:
		for gy in 14:
			var p := bb.position + Vector2((gx + 0.5) / 14.0 * bb.size.x, (gy + 0.5) / 14.0 * bb.size.y)
			if Geometry2D.is_point_in_polygon(p, pts):
				best = maxf(best, MapData.dist_to_path(p, pts, true))
	m.set_shader_parameter("seg_a", sa)
	m.set_shader_parameter("seg_b", sb)
	m.set_shader_parameter("seg_count", count)
	m.set_shader_parameter("orient", 1.0 if area >= 0.0 else -1.0)
	m.set_shader_parameter("max_d", best)
	m.set_shader_parameter("round_roof", 1.0 if round_roof else 0.0)
	return m


func rebuild_roofs() -> void:
	_clear(_roofs)
	_roof_items.clear()
	_roofs.visible = roofs_visible
	for r in data.get("roofs", []):
		var pts: PackedVector2Array = r["points"]
		if pts.size() < 3:
			continue
		var type := str(r["type"])
		var def: Dictionary = MapData.ROOFS.get(type, MapData.ROOFS["roof_shingle"])
		var holder := Node2D.new()
		var mats: Array = []
		# Drop shadow cast onto the ground, offset away from the light (top-left).
		var shadow := Polygon2D.new()
		shadow.polygon = pts
		shadow.position = Vector2(9, 12)
		shadow.color = Color(0, 0, 0, 0.35)
		var sm := _roof_material()
		shadow.material = sm
		mats.append(sm)
		holder.add_child(shadow)
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.uv = pts
		poly.texture = MapData.get_texture(type)
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var shape := str(def.get("shape", "hip"))
		# "flat" = plain texture, no pitch shading or ridge lines (e.g. wagon canvas).
		var pm := _roof_material() if shape == "flat" else _roof_shaded_material(pts, shape == "round")
		poly.material = pm
		mats.append(pm)
		holder.add_child(poly)
		var oc: Color = def["outline"]
		var line := Line2D.new()
		line.points = pts
		line.closed = true
		line.width = 3.0
		line.default_color = oc
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		var lm := _roof_material()
		line.material = lm
		mats.append(lm)
		holder.add_child(line)
		holder.modulate.a = 1.0 if physics_enabled else EDITOR_ROOF_ALPHA
		_roofs.add_child(holder)
		_roof_items.append({"node": holder, "pts": pts, "mats": mats, "alpha": 1.0})


func set_roofs_visible(on: bool) -> void:
	roofs_visible = on
	_roofs.visible = on


## Play-test: hides a roof while the player is under it, and otherwise cuts a view cone
## through every window / open door on that roof so the inside can be seen from outside.
func update_roof_fade(pos: Vector2, delta: float) -> void:
	if _roof_items.is_empty():
		return
	var doors: Array = []
	for n in _openings.get_children():
		var op := n as OpeningNode
		if op != null and (op.kind == "window" or op.is_open):
			doors.append(op)
	for item in _roof_items:
		var pts: PackedVector2Array = item["pts"]
		var inside := Geometry2D.is_point_in_polygon(pos, pts)
		var a: float = move_toward(float(item["alpha"]), 0.0 if inside else 1.0, delta * 4.0)
		item["alpha"] = a
		var node: Node2D = item["node"]
		node.modulate.a = a
		node.visible = a > 0.01
		var ea := PackedVector2Array()
		var eb := PackedVector2Array()
		if not inside:
			for op in doors:
				if ea.size() >= MAX_VIEW_CONES:
					break
				if op.position.distance_to(pos) > MAX_VIEW_DIST:
					continue
				if not (Geometry2D.is_point_in_polygon(op.position, pts) or MapData.dist_to_path(op.position, pts, true) < 24.0):
					continue
				ea.append(op.to_global(Vector2(-op.width * 0.5, 0.0)))
				eb.append(op.to_global(Vector2(op.width * 0.5, 0.0)))
		while ea.size() < MAX_VIEW_CONES:
			ea.append(Vector2.ZERO)
			eb.append(Vector2.ZERO)
		var count := 0
		if not inside:
			for k in MAX_VIEW_CONES:
				if ea[k] != eb[k]:
					count += 1
		for m in item["mats"]:
			m.set_shader_parameter("viewer", pos)
			m.set_shader_parameter("cone_count", count)
			m.set_shader_parameter("edge_a", ea)
			m.set_shader_parameter("edge_b", eb)


## Fades tree canopies that cover `pos` so the player stays visible underneath.
func update_canopy_fade(pos: Vector2, delta: float) -> void:
	for n in _canopies:
		var node: PropNode = n
		var base: float = MapData.PROPS.get(node.kind, MapData.PROPS["tree"])["radius"]
		var radius := base * node.scale.x * 0.9
		var target := CANOPY_FADE_ALPHA if node.position.distance_to(pos) < radius else 1.0
		node.modulate.a = move_toward(node.modulate.a, target, delta * 4.0)


func _process(delta: float) -> void:
	if not lighting_enabled or _flicker.is_empty():
		return
	_time += delta
	for f in _flicker:
		var l: PointLight2D = f[0]
		if is_instance_valid(l):
			l.energy = float(f[1]) * (1.0 + 0.10 * sin(_time * 11.0 + float(f[2])) + 0.06 * sin(_time * 23.0 + float(f[2]) * 2.0))
