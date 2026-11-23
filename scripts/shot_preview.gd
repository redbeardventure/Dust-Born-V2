extends Node2D
## Shot preview: hover an NPC (or keep one locked) with a ranged weapon and this draws the
## shot's aim cone, where cover stops it, and a small card with hit chance, cover and damage.
##
## The numbers come from sampling the same rules Projectile uses: the shot's angle is uniform
## inside +-spread, a character is hit when the path passes within Projectile.HIT_RADIUS of its
## centre, walls and props (Projectile.WORLD_MASK) stop the shot, and the first character on the
## path takes the hit. Each sample is one ray, so the percentage is exact up to the sample count.

const SAMPLES := 25
const HOVER_RADIUS := 22.0      # px from the cursor to an NPC's centre that counts as hovering it
const CONE_PAST_TARGET := 30.0  # the cone is drawn this far beyond the target
const PELLET_RANGE_MIN := 0.85  # pellets fly 85-100% of the weapon range (see Projectile.fire)

var player  # the Player (untyped: Player preloads this script)

var _data := {}


func _ready() -> void:
	top_level = true
	z_index = 20
	global_position = Vector2.ZERO  # everything is drawn in world coordinates


func _physics_process(_delta: float) -> void:
	var t := _pick_target()
	if t == null:
		if not _data.is_empty():
			_data = {}
			queue_redraw()
		return
	_data = _compute(t)
	queue_redraw()


## The NPC under the cursor, otherwise the locked target; null when no preview applies.
func _pick_target() -> Node2D:
	if player == null or player.hp <= 0 or not Weapons.is_ranged(player.weapon):
		return null
	if player.turn_mode and not player.my_turn:
		return null
	var best: Node2D = null
	if get_viewport().gui_get_hovered_control() == null:
		var mp := get_global_mouse_position()
		var best_d := HOVER_RADIUS
		for n in get_tree().get_nodes_in_group("npcs"):
			var npc := n as Node2D
			if npc == null or not is_instance_valid(npc) or npc.is_queued_for_deletion() or npc.hp <= 0:
				continue
			var d := mp.distance_to(npc.global_position)
			if d < best_d:
				best_d = d
				best = npc
	if best == null and is_instance_valid(player.target) and player.target.is_in_group("npcs"):
		best = player.target
	return best


func _compute(t: Node2D) -> Dictionary:
	var weapon: String = player.weapon
	var w: Dictionary = Weapons.RANGED[weapon]
	var aimed: bool = player.aimed
	var dist: float = player.global_position.distance_to(t.global_position)
	var spread: float = float(w["spread"]) * (0.0 if aimed else Weapons.spread_mul_at(weapon, dist))
	var reach: float = float(w["range"]) * (player.AIM_RANGE if aimed else 1.0)
	var pellets := int(w.get("pellets", 1))
	var dmg_each := roundi(float(w["damage"]) * (player.AIM_DAMAGE if aimed else 1.0))
	var is_pellet: bool = w["shot"] == "pellet"

	var origin: Vector2 = player.shot_origin(t.global_position)
	var tc := t.global_position
	var dir0 := (tc - origin).normalized()
	var draw_len := minf(reach, origin.distance_to(tc) + CONE_PAST_TARGET)

	var space := get_world_2d().direct_space_state
	var exclude: Array[RID] = []
	var others: Array[Node2D] = []
	for n in get_tree().get_nodes_in_group("combatants"):
		if n is CollisionObject2D:
			exclude.append(n.get_rid())
		if n != player and n != t and n is Node2D and is_instance_valid(n) and n.has_method("take_damage"):
			others.append(n)

	var count := 1 if spread < 0.0005 else SAMPLES
	var on_sum := 0.0    # samples that would hit the target if nothing were in the way
	var hit_sum := 0.0   # samples that actually hit it
	var body_block := false
	var ends := PackedVector2Array()
	var blocks := PackedVector2Array()  # where cover stops a shot that was heading for the target
	for i in count:
		var a := 0.0 if count == 1 else lerpf(-spread, spread, float(i) / float(count - 1))
		var dir := dir0.rotated(a)
		var full_end := origin + dir * reach
		var q := PhysicsRayQueryParameters2D.create(origin, full_end, Projectile.WORLD_MASK)
		q.exclude = exclude
		var wall := space.intersect_ray(q)
		var wall_pt: Vector2 = wall["position"] if not wall.is_empty() else full_end
		ends.append(origin + dir * minf(origin.distance_to(wall_pt), draw_len))

		var cp_full := Geometry2D.get_closest_point_to_segment(tc, origin, full_end)
		if tc.distance_to(cp_full) > Projectile.HIT_RADIUS:
			continue  # this sample misses the target by angle alone
		var reach_p := 1.0
		if is_pellet:
			reach_p = clampf((reach - origin.distance_to(cp_full)) / (reach * (1.0 - PELLET_RANGE_MIN)), 0.0, 1.0)
		on_sum += reach_p
		var cp_wall := Geometry2D.get_closest_point_to_segment(tc, origin, wall_pt)
		if tc.distance_to(cp_wall) > Projectile.HIT_RADIUS:
			blocks.append(wall_pt)  # a wall or prop is in front of the target
			continue
		var along := origin.distance_to(cp_wall)
		var body := false
		for o in others:
			var cp_o := Geometry2D.get_closest_point_to_segment(o.global_position, origin, wall_pt)
			if o.global_position.distance_to(cp_o) <= Projectile.HIT_RADIUS and origin.distance_to(cp_o) < along:
				body = true
				break
		if body:
			body_block = true
			blocks.append(cp_wall)
			continue
		hit_sum += reach_p

	var chance := hit_sum / float(count)
	var cover := 0.0 if on_sum <= 0.0 else 1.0 - hit_sum / on_sum
	var expected := chance * float(pellets * dmg_each)
	return {
		"origin": origin, "target": tc, "ends": ends, "blocks": blocks,
		"chance": chance, "cover": cover, "body": body_block,
		"dist": dist, "reach": reach, "aimed": aimed,
		"pellets": pellets, "dmg_each": dmg_each, "expected": expected,
		"hp": int(t.hp), "max_hp": int(t.max_hp), "empty": int(player.ammo()) <= 0,
		"can_kill": pellets * dmg_each >= int(t.hp),
	}


func _chance_color(c: float) -> Color:
	if c >= 0.5:
		return Color(1.0, 0.9, 0.2).lerp(Color(0.3, 1.0, 0.35), (c - 0.5) * 2.0)
	return Color(1.0, 0.25, 0.2).lerp(Color(1.0, 0.9, 0.2), c * 2.0)


func _draw() -> void:
	if _data.is_empty():
		return
	var origin: Vector2 = _data["origin"]
	var tc: Vector2 = _data["target"]
	var ends: PackedVector2Array = _data["ends"]
	var chance: float = _data["chance"]
	var in_range: bool = float(_data["dist"]) <= float(_data["reach"])
	var col := _chance_color(chance) if in_range else Color(1.0, 0.25, 0.2)

	# The cone: one thin triangle per neighbouring pair of rays, so cover cuts notches into it.
	for i in range(ends.size() - 1):
		draw_colored_polygon(PackedVector2Array([origin, ends[i], ends[i + 1]]), Color(col, 0.14))
	if ends.size() >= 2:
		draw_line(origin, ends[0], Color(col, 0.7), 1.5)
		draw_line(origin, ends[ends.size() - 1], Color(col, 0.7), 1.5)
	else:
		draw_line(origin, ends[0], Color(col, 0.7), 1.5)
	# Shots that cover or a body stops before the target.
	for b in _data["blocks"]:
		draw_circle(b, 2.5, Color(1.0, 0.3, 0.2, 0.9))

	_draw_card(tc, col, in_range)


func _draw_card(tc: Vector2, col: Color, in_range: bool) -> void:
	var chance: float = _data["chance"]
	var cover: float = _data["cover"]
	var pellets: int = _data["pellets"]
	var lines: Array = []  # [text, color]
	if not in_range:
		lines.append(["OUT OF RANGE", Color(1.0, 0.3, 0.25)])
	else:
		lines.append(["HIT %d%%" % roundi(chance * 100.0), col])
	if _data["body"]:
		lines.append(["Someone in the way", Color(1.0, 0.55, 0.25)])
	if chance <= 0.0 and cover > 0.0:
		lines.append(["BLOCKED by cover", Color(1.0, 0.3, 0.25)])
	elif cover > 0.02:
		lines.append(["Cover -%d%%" % roundi(cover * 100.0), Color(1.0, 0.75, 0.3)])
	else:
		lines.append(["Clear shot", Color(0.7, 0.95, 0.7)])
	var dmg := ("%d x %d" % [pellets, _data["dmg_each"]]) if pellets > 1 else str(_data["dmg_each"])
	lines.append(["Damage %s%s" % [dmg, " (aimed)" if _data["aimed"] else ""], Color(0.95, 0.95, 0.95)])
	if in_range:
		lines.append(["Expected %.1f" % _data["expected"], Color(0.95, 0.95, 0.95)])
	if _data["can_kill"] and in_range:
		lines.append(["Can kill (%d/%d hp)" % [_data["hp"], _data["max_hp"]], Color(1.0, 0.85, 0.3)])
	else:
		lines.append(["Target %d/%d hp" % [_data["hp"], _data["max_hp"]], Color(0.75, 0.75, 0.8)])
	if _data["empty"]:
		lines.append(["Empty: reload first", Color(1.0, 0.3, 0.25)])

	var font := ThemeDB.fallback_font
	const FS := 13
	const LH := 16.0
	const PAD := 6.0
	var wmax := 0.0
	for l in lines:
		wmax = maxf(wmax, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FS).x)
	var size := Vector2(wmax + PAD * 2.0, LH * lines.size() + PAD * 2.0 - 3.0)
	var pos := tc + Vector2(26.0, -size.y * 0.5)  # to the right of the target
	draw_rect(Rect2(pos, size), Color(0.05, 0.05, 0.08, 0.82))
	draw_rect(Rect2(pos, size), Color(col, 0.8), false, 1.5)
	for i in lines.size():
		draw_string(font, pos + Vector2(PAD, PAD + LH * (i + 1) - 4.0), lines[i][0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, FS, lines[i][1])
