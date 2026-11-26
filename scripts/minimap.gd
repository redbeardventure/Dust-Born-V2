class_name Minimap
extends Control
## Small overview map for the corner of the play-test screen: the ground, walls and solid props
## (drawn once) plus live dots for the player, NPCs and weapon pickups.

const MAX_SIZE := Vector2(210, 160)
const MARGIN := 12.0
const REFRESH := 0.1  # seconds between redraws
const FOG_CELL := 24.0  # world pixels per fog cell
const SEE_RADIUS := 300.0  # world pixels around the player that get revealed
const FOG_COLOR := Color(0.05, 0.045, 0.04, 1.0)

var _fog_img: Image  # alpha 1 = unexplored, 0 = explored
var _fog_tex: ImageTexture
var _fog_w := 1
var _fog_h := 1
var _scale := 1.0
var _map_size := Vector2.ONE
var _bg := Color(0.3, 0.3, 0.3)
var _polys: Array = []  # [{pts: PackedVector2Array, color: Color}] already scaled to the minimap
var _walls: Array = []  # [{pts: PackedVector2Array, closed: bool, width: float}]
var _blocks: Array = []  # [{pos: Vector2, r: float}] solid props
var _since := 0.0


static func create(data: Dictionary) -> Minimap:
	var m := Minimap.new()
	m._setup(data)
	return m


func _setup(data: Dictionary) -> void:
	_map_size = data["size"]
	_scale = minf(MAX_SIZE.x / _map_size.x, MAX_SIZE.y / _map_size.y)
	custom_minimum_size = _map_size * _scale
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks pass through to the game
	# Top-right corner.
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -size.x - MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + size.y
	_fog_w = maxi(ceili(_map_size.x / FOG_CELL), 1)
	_fog_h = maxi(ceili(_map_size.y / FOG_CELL), 1)
	_fog_img = Image.create(_fog_w, _fog_h, false, Image.FORMAT_RGBA8)
	_fog_img.fill(FOG_COLOR)
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	var bg_key := str(data.get("background", "grass"))
	if MapData.TERRAIN.has(bg_key):
		_bg = MapData.TERRAIN[bg_key]["a"]
	for poly in data["polygons"]:
		var key := str(poly["type"])
		if not MapData.TERRAIN.has(key):
			continue
		var pts := PackedVector2Array()
		for p in poly["points"]:
			pts.append((p as Vector2) * _scale)
		if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
			continue  # degenerate outline: skip rather than error
		var col: Color = MapData.TERRAIN[key]["a"]
		col.a = 1.0
		_polys.append({"pts": pts, "color": col})
	for w in data["walls"]:
		var wp := PackedVector2Array()
		for p in w["points"]:
			wp.append((p as Vector2) * _scale)
		if wp.size() >= 2:
			_walls.append({"pts": wp, "closed": bool(w.get("closed", false)), "width": maxf(float(w.get("width", 12.0)) * _scale, 1.0)})
	for pr in data["props"]:
		var def: Dictionary = MapData.PROPS.get(pr["type"], {})
		if float(def.get("solid", 0.0)) > 0.0 or def.has("rect"):
			_blocks.append({"pos": (pr["pos"] as Vector2) * _scale, "r": maxf(float(def.get("radius", 10.0)) * float(pr["scale"]) * _scale * 0.5, 1.0)})


func _process(delta: float) -> void:
	_since += delta
	if _since >= REFRESH:
		_since = 0.0
		_reveal()
		queue_redraw()


## Clears the fog in a soft-edged disc around the player. Cleared cells stay cleared.
func _reveal() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return
	var c := player.global_position / FOG_CELL
	var rc := SEE_RADIUS / FOG_CELL
	var changed := false
	for y in range(maxi(int(c.y - rc) - 1, 0), mini(int(c.y + rc) + 2, _fog_h)):
		for x in range(maxi(int(c.x - rc) - 1, 0), mini(int(c.x + rc) + 2, _fog_w)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d > rc:
				continue
			# Fade the outer 25% of the radius so the edge isn't a hard circle.
			var a := clampf((d - rc * 0.75) / (rc * 0.25), 0.0, 1.0) * FOG_COLOR.a
			if a < _fog_img.get_pixel(x, y).a:
				_fog_img.set_pixel(x, y, Color(FOG_COLOR, a))
				changed = true
	if changed:
		_fog_tex.update(_fog_img)


func _explored(n: Node2D) -> bool:
	var p := n.global_position / FOG_CELL
	var x := clampi(int(p.x), 0, _fog_w - 1)
	var y := clampi(int(p.y), 0, _fog_h - 1)
	return _fog_img.get_pixel(x, y).a < 0.5


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, _bg)
	for p in _polys:
		draw_colored_polygon(p["pts"], p["color"])
	for w in _walls:
		var pts: PackedVector2Array = w["pts"]
		if w["closed"]:
			pts = PackedVector2Array(pts)
			pts.append(pts[0])
		draw_polyline(pts, Color(0.12, 0.1, 0.09), w["width"])
	for b in _blocks:
		draw_circle(b["pos"], b["r"], Color(0.18, 0.2, 0.16, 0.9))
	# Fog of war: unexplored areas are hidden, and so are markers inside them.
	draw_texture_rect(_fog_tex, rect, false)
	# Live markers.
	for n in get_tree().get_nodes_in_group("props"):
		if n is PropNode and (n as PropNode).kind == MapData.WEAPON_PROP and _explored(n):
			draw_circle(_at(n), 3.0, Color(1.0, 0.85, 0.3))
	for n in get_tree().get_nodes_in_group("npcs"):
		if n is NpcNode and (n as NpcNode).hp > 0:
			var hostile := (n as NpcNode).disposition == "hostile"
			if not _explored(n):
				continue  # hidden in the fog, hostile or not
			var col := Color(0.4, 0.8, 0.45)
			if hostile:
				col = Color(1.0, 0.55, 0.1) if n is AnimalNode else Color(0.95, 0.25, 0.2)
			draw_circle(_at(n), 2.5, col)
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null:
		var c := _at(player)
		var f := player.facing.normalized()
		var r := f.orthogonal()
		draw_colored_polygon(PackedVector2Array([c + f * 5.0, c - f * 3.5 + r * 3.5, c - f * 3.5 - r * 3.5]), Color.WHITE)
	# Frame.
	draw_rect(rect, Color(0.05, 0.04, 0.03, 0.9), false, 3.0)
	draw_rect(rect.grow(-1.5), Color(0.85, 0.65, 0.25, 0.9), false, 1.0)


func _at(n: Node2D) -> Vector2:
	return (n.global_position * _scale).clamp(Vector2.ZERO, size)
