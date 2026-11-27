class_name OpeningNode
extends Node2D
## A door or window set into a wall. The node sits on the wall's centre line and is rotated to
## follow the wall (local +x runs along the wall).
## Door: solid and blocks light while closed; can be opened or kicked open (swings away from the user).
## Window: blocks movement but not light, so you can see through it.

const SWING := 1.6  # radians a door leaf swings when opened (~92 degrees)

var kind := "door"
var width := 48.0
var thick := 12.0
var physics := false  # build collision (play-test only)

var is_open := false
var broken := false   # window whose glass has been shot out (no longer blocks movement or shots)
const SHARD_LIFE := 0.8
var _shards: Array = []  # flying glass: {p, v, r, s} in local space
var _shard_time := 0.0
var _angle := 0.0     # current leaf angle around the hinge
var _target := 0.0
var _vel := 0.0
var _kicked := false
var _flash := 0.0     # brief impact flash after a kick
var _shape: CollisionShape2D
var _occluder: LightOccluder2D
var _leaf_body: StaticBody2D  # the swung-open door leaf; solid only while the door is open
var _leaf_shape: CollisionShape2D
var _badge: Node2D            # clickable marker drawn above the roof, just outside the building
var _badge_side := 0.0        # -1 / +1: which side of the wall is outside the roof (0 = no roof, no badge)

const BADGE_OFFSET := 24.0  # px from the wall face to the badge centre
const BADGE_RADIUS := 11.0
const BADGE_SHOW_DIST := 160.0  # px: the badge only appears when the player is this close
const BADGE_Z := 19         # above the roofs (18)


func _ready() -> void:
	var t := _t()
	var half := Vector2(width, t) * 0.5
	if kind == "door":
		var occ := OccluderPolygon2D.new()
		occ.polygon = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
		_occluder = LightOccluder2D.new()
		_occluder.occluder = occ
		add_child(_occluder)
	if physics:
		add_to_group("openings")  # clickable in play-test (player walks up to it)
		var body := StaticBody2D.new()
		_shape = CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = Vector2(width, t)
		_shape.shape = rs
		body.add_child(_shape)
		add_child(body)
		if kind == "door":
			# The open leaf stands across the doorway's side, so it blocks walking (layer 1, like walls).
			_leaf_body = StaticBody2D.new()
			_leaf_body.position = Vector2(-width * 0.5 + 1.0, 0)  # hinge
			_leaf_shape = CollisionShape2D.new()
			var ls := RectangleShape2D.new()
			ls.size = Vector2(width - 2.0, t * 0.76)
			_leaf_shape.shape = ls
			_leaf_shape.position = Vector2((width - 2.0) * 0.5, 0)
			_leaf_shape.disabled = true
			_leaf_body.add_child(_leaf_shape)
			add_child(_leaf_body)
		_badge = Node2D.new()
		_badge.z_index = BADGE_Z
		_badge.visible = false
		_badge.draw.connect(_draw_badge)
		add_child(_badge)
	set_process(false)


func _t() -> float:
	return maxf(thick, 10.0)


## Called by the map renderer once it knows which side of the wall is outside the roof:
## shows a clickable badge on that side, sticking out past the roof edge.
func set_outside(side: float) -> void:
	if _badge == null or side == 0.0 or _badge_side == side:
		return
	_badge_side = side
	_badge.position = Vector2(0, side * (_t() * 0.5 + BADGE_OFFSET))
	_badge.rotation = -rotation  # keep the icon upright whatever way the wall runs
	_badge.visible = false  # shown by update_badge() once the player is close
	_badge.queue_redraw()


## Shows the badge only while the player is within BADGE_SHOW_DIST of this door/window.
func update_badge(player_pos: Vector2) -> void:
	if _badge == null or _badge_side == 0.0:
		return
	var near := global_position.distance_to(player_pos) <= BADGE_SHOW_DIST and not (kind == "door" and is_open)
	if near != _badge.visible:
		_badge.visible = near


func _badge_hit(p: Vector2) -> bool:
	return _badge_side != 0.0 and _badge.visible and to_local(p).distance_to(_badge.position) < BADGE_RADIUS + 5.0


## True when a click at `p` (world space) lands on this door/window or its badge (with a little slack).
func hit_test(p: Vector2) -> bool:
	if _badge_hit(p):
		return true
	var l := to_local(p)
	return absf(l.x) < width * 0.5 + 4.0 and absf(l.y) < _t() * 0.5 + 8.0


func _draw_badge() -> void:
	var edge := Color(0.1, 0.07, 0.04, 0.95)
	var wall_pt := _badge.to_local(global_position)  # a stem back to the opening itself
	_badge.draw_line(Vector2.ZERO, wall_pt, Color(edge, 0.8), 3.0)
	_badge.draw_line(Vector2.ZERO, wall_pt, Color(1.0, 0.9, 0.55, 0.9), 1.5)
	var r := BADGE_RADIUS
	var fill := Color("2e2418")
	var ring := Color(0.35, 0.9, 1.0) if kind == "window" else Color("e8c860")
	_badge.draw_circle(Vector2(1.5, 2.0), r, Color(0, 0, 0, 0.35))
	_badge.draw_circle(Vector2.ZERO, r, fill)
	_badge.draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, ring, 2.0)
	if kind == "window":
		var pane := Rect2(-5.5, -5.5, 11.0, 11.0)
		_badge.draw_rect(pane, Color(0.62, 0.84, 0.95, 0.55))
		_badge.draw_rect(pane, ring, false, 1.5)
		_badge.draw_line(Vector2(0, -5.5), Vector2(0, 5.5), ring, 1.2)
		_badge.draw_line(Vector2(-5.5, 0), Vector2(5.5, 0), ring, 1.2)
	elif is_open:
		# Open door: frame with the leaf swung aside.
		_badge.draw_rect(Rect2(-5.0, -6.5, 10.0, 13.0), Color(0.05, 0.04, 0.03))
		_badge.draw_rect(Rect2(-5.0, -6.5, 10.0, 13.0), ring, false, 1.5)
		_badge.draw_colored_polygon(PackedVector2Array([Vector2(-5, -6.5), Vector2(0, -4.5), Vector2(0, 8.5), Vector2(-5, 6.5)]), Color("9a6c42"))
	else:
		_badge.draw_rect(Rect2(-5.0, -6.5, 10.0, 13.0), Color("7a5230"))
		_badge.draw_rect(Rect2(-5.0, -6.5, 10.0, 13.0), ring, false, 1.5)
		_badge.draw_circle(Vector2(2.2, 0.5), 1.3, Color("d8b04a"))


## Where someone coming from `from` should stand to use this opening: in front of its middle,
## on the same side of the wall as they are, `gap` px clear of the wall face.
func approach_point(from: Vector2, gap: float = 20.0) -> Vector2:
	var side := signf(to_local(from).y)
	if side == 0.0:
		side = 1.0
	return to_global(Vector2(0, side * (_t() * 0.5 + gap)))


## True when `p` (world space) is standing in the doorway, so the door must not close on it.
func blocks_point(p: Vector2) -> bool:
	var l := to_local(p)
	return absf(l.x) < width * 0.5 + 12.0 and absf(l.y) < _t() * 0.5 + 16.0


## Opens a closed door. It swings away from `from` (the opener's position).
func open(from: Vector2, kicked: bool = false) -> void:
	if kind != "door" or is_open:
		return
	is_open = true
	_kicked = kicked
	var side := signf(to_local(from).y)
	if side == 0.0:
		side = 1.0
	_target = -side * SWING * (1.2 if kicked else 1.0)
	if kicked:
		_vel = _target * 6.0  # the kick gives the leaf a hard shove
		_flash = 0.25
	_set_solid(false)
	set_process(true)


func close() -> void:
	if kind != "door" or not is_open:
		return
	is_open = false
	_kicked = false
	_target = 0.0
	_set_solid(true)
	set_process(true)


## A bullet hit this opening. Only windows react: the glass is shot out.
func shoot_out(hit_dir: Vector2 = Vector2.ZERO) -> void:
	if kind != "window" or broken:
		return
	broken = true
	_shards.clear()
	var local_dir := hit_dir.rotated(-global_rotation) if hit_dir != Vector2.ZERO else Vector2.ZERO
	for i in 22:
		var pos := Vector2(randf_range(-width * 0.45, width * 0.45), randf_range(-_t() * 0.4, _t() * 0.4))
		var vel := Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0)) + local_dir * randf_range(40.0, 120.0)
		_shards.append({"p": pos, "v": vel, "r": randf() * TAU, "s": randf_range(1.5, 3.5)})
	_shard_time = SHARD_LIFE
	# Nothing left to block walking through the frame.
	if _shape != null:
		_shape.set_deferred("disabled", true)
	if _badge != null:
		_badge.queue_redraw()
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("refresh_nav"):
		var r := width + 24.0
		p.call("refresh_nav", Rect2(global_position - Vector2(r, r), Vector2(r, r) * 2.0))
	set_process(true)
	queue_redraw()


func _set_solid(solid: bool) -> void:
	if _shape != null:
		_shape.set_deferred("disabled", not solid)
	if _leaf_body != null:
		# The open leaf blocks at its final resting angle, so path-finding sees it straight away.
		_leaf_body.rotation = clampf(_target, -SWING, SWING)
		_leaf_shape.set_deferred("disabled", solid)
	if _badge != null:
		_badge.queue_redraw()
	if _occluder != null:
		_occluder.visible = solid


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if kind == "window":
		_shard_time = maxf(_shard_time - delta, 0.0)
		for s in _shards:
			s["p"] += s["v"] * delta
			s["v"] *= maxf(1.0 - 3.0 * delta, 0.0)
		if _shard_time <= 0.0:
			_shards.clear()
			set_process(false)
		queue_redraw()
		return
	# Spring toward the target: gently damped normally, bouncy after a kick.
	var k := 150.0 if _kicked else 70.0
	var c := 7.0 if _kicked else 15.0
	_vel += ((_target - _angle) * k - _vel * c) * delta
	_angle += _vel * delta
	_flash = maxf(_flash - delta, 0.0)
	if absf(_target - _angle) < 0.002 and absf(_vel) < 0.03 and _flash <= 0.0:
		_angle = _target
		_vel = 0.0
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if kind == "window":
		_draw_window()
	else:
		_draw_door()


func _draw_door() -> void:
	var t := _t()
	var w := width
	var wood := Color("7a5230")
	var wood_hi := Color("9a6c42")
	var edge := Color(0.1, 0.07, 0.04, 0.95)
	# Floor strip under the doorway, visible once the leaf has swung away.
	draw_rect(Rect2(-w * 0.5, -t * 0.5, w, t), Color(0.22, 0.16, 0.1))
	# Door leaf, hinged at the left end.
	draw_set_transform(Vector2(-w * 0.5 + 1.0, 0), _angle, Vector2.ONE)
	var leaf := Rect2(0, -t * 0.38, w - 2.0, t * 0.76)
	draw_rect(Rect2(leaf.position + Vector2(1.5, 2.5), leaf.size), MapData.shadow_color(0.3))
	draw_rect(leaf, wood)
	draw_rect(Rect2(leaf.position, Vector2(leaf.size.x, leaf.size.y * 0.4)), wood_hi)
	for i in range(1, 4):
		var x := leaf.size.x * float(i) / 4.0
		draw_line(Vector2(x, leaf.position.y), Vector2(x, leaf.end.y), Color(edge, 0.55), 1.0)
	draw_rect(leaf, edge, false, 1.5)
	draw_circle(Vector2(leaf.size.x - 7.0, 0), 1.8, Color("d8b04a"))  # handle
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Door frame posts at both ends.
	for sx in [-1.0, 1.0]:
		var post := Rect2(Vector2(sx * w * 0.5 - 2.5, -t * 0.5 - 1.0), Vector2(5.0, t + 2.0))
		draw_rect(post, Color("3a2818"))
		draw_rect(post, edge, false, 1.0)
	if _flash > 0.0:  # kick impact
		var a := _flash / 0.25
		for i in 6:
			var ang := TAU * float(i) / 6.0 + 0.3
			draw_line(Vector2(cos(ang), sin(ang)) * 6.0, Vector2(cos(ang), sin(ang)) * (12.0 + 8.0 * (1.0 - a)), Color(1.0, 0.9, 0.5, a), 2.0)


func _draw_window() -> void:
	var t := _t()
	var w := width
	var frame := Color("4a3a2c")
	var glass := Color(0.62, 0.84, 0.95, 0.38)
	var edge := Color(0.1, 0.07, 0.04, 0.95)
	var outer := Rect2(-w * 0.5, -t * 0.5, w, t)
	var pane := outer.grow(-2.5)
	# Frame as four borders so the glass area stays see-through.
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, 2.5)), frame)
	draw_rect(Rect2(Vector2(outer.position.x, pane.end.y), Vector2(outer.size.x, 2.5)), frame)
	draw_rect(Rect2(outer.position, Vector2(2.5, outer.size.y)), frame)
	draw_rect(Rect2(Vector2(pane.end.x, outer.position.y), Vector2(2.5, outer.size.y)), frame)
	if broken:
		# Glass gone: only jagged teeth stay in the frame, plus the flying shards.
		var tooth := Color(glass, 0.6)
		for i in 6:
			var x := pane.position.x + pane.size.x * (float(i) + 0.5) / 6.0
			var h := pane.size.y * (0.25 if i % 2 == 0 else 0.4)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 3.0, pane.position.y), Vector2(x + 3.0, pane.position.y), Vector2(x, pane.position.y + h)]), tooth)
		var fade := clampf(_shard_time / SHARD_LIFE, 0.0, 1.0)
		for s in _shards:
			var sz: float = s["s"]
			draw_set_transform(s["p"], s["r"], Vector2.ONE)
			draw_colored_polygon(PackedVector2Array([Vector2(-sz, -sz * 0.5), Vector2(sz, 0), Vector2(-sz * 0.3, sz)]), Color(0.8, 0.93, 1.0, 0.8 * fade))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(outer, edge, false, 1.5)
		return
	draw_rect(pane, glass)
	# Glints and a centre bar.
	draw_line(pane.position + Vector2(pane.size.x * 0.15, pane.size.y), pane.position + Vector2(pane.size.x * 0.35, 0), Color(1, 1, 1, 0.55), 1.2)
	draw_line(pane.position + Vector2(pane.size.x * 0.28, pane.size.y), pane.position + Vector2(pane.size.x * 0.42, 0), Color(1, 1, 1, 0.35), 1.0)
	draw_line(Vector2(0, pane.position.y), Vector2(0, pane.end.y), frame, 2.0)
	draw_rect(outer, edge, false, 1.5)
