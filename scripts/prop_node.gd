class_name PropNode
extends Node2D
## Draws a single prop procedurally (top-down). Position/scale/rotation come from the node transform.

var kind: String = "tree"
var seed_v: int = 0

# ---- play-test only (set up by MapRenderer.rebuild_props via make_interactive) ----
## Loot inside (key in MapData.NPC_LOOT). Barrels drop it when shot apart, crates when opened.
var loot := "none"
var hp := 0
var opened := false
## Crates and chests can be locked: a key from the map opens them (see unlock()).
var locked := false
## Opened container that held water: the inside is drawn full of water.
var water_inside := false
var _hit_flash := 0.0

const BARREL_HP := 30
const CRATE_HP := 50

## Sent when shot apart, so a player targeting it drops the target at once.
signal defeated(node: Node)

# ---- weapon pickup ("weapon" prop; the gun is in `loot`) ----
const PICKUP_RANGE := 22.0  # px from the gun to the player's centre
const WEAPON_BOX := 34.0  # px the gun picture is drawn in
const RING_RADIUS := 22.0  # selection ring around the gun
var _pickup_live := false  # play-test: pulses in size and can be picked up
var _t := 0.0
var _smoke_t := 0.0  # drives the drifting smoke animation


## Play-test only: the gun floats (eases smaller and back) and is picked up when the player walks over it.
func make_pickup() -> void:
	_pickup_live = true


func _tick_pickup(delta: float) -> void:
	_t += delta
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and p.has_method("pick_up_weapon") and p.global_position.distance_to(global_position) < PICKUP_RANGE * maxf(scale.x, 1.0):
		_pickup_live = false
		p.call("pick_up_weapon", loot)
		queue_free()
		return
	queue_redraw()


func _draw_weapon_pickup() -> void:
	if not Weapons.is_ranged(loot):
		return
	# Seen from above, "floating" reads as the gun drifting toward and away from the camera:
	# it eases between full size (raised) and a bit smaller (lowered) on a smooth cosine curve.
	var rise := 1.0  # 0 = lowest, 1 = highest
	if _pickup_live:
		rise = 0.5 + 0.5 * cos(_t * 2.2)
	var s := lerpf(0.86, 1.0, rise)
	# Selection ring: a steady ring around the gun (dark edge under a light line so it shows on any ground).
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 3.5)
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 40, Color(1.0, 0.92, 0.55, 0.95), 1.8)
	# The gun picture stays upright whatever the prop's rotation.
	Weapons.draw_icon_at(self, loot, Vector2.ZERO, WEAPON_BOX * s, -rotation)


## Makes a barrel/crate targetable in play-test (group "containers") and shootable
## (group "breakable": projectiles that hit their collision call take_damage).
func make_interactive(loot_kind: String, is_locked: bool = false) -> void:
	loot = loot_kind
	locked = is_locked and is_openable()
	add_to_group("containers")  # targetable by the player (click / Tab)
	if kind != "trunk":  # trunks are opened, never shot apart
		add_to_group("breakable")
	hp = max_hp()


## Crates, trunks and barrels are opened by hand (E / Open button).
func is_openable() -> bool:
	return kind == "crate" or kind == "trunk" or kind == "barrel"


## Barrels break quicker than the sturdier crates.
func max_hp() -> int:
	return BARREL_HP if kind == "barrel" else CRATE_HP


func label() -> String:
	return str(MapData.PROPS.get(kind, {}).get("label", kind))


## Footprint radius in world pixels (selection / click size).
func _radius() -> float:
	return float(MapData.PROPS.get(kind, MapData.PROPS["tree"])["radius"]) * scale.x


func hit_test(p: Vector2) -> bool:
	return global_position.distance_to(p) < _radius() + 4.0


func _ready() -> void:
	add_to_group("props")


## Defence score (0..1) of this prop as cover, see MapData.prop_defence().
func defence() -> float:
	return MapData.prop_defence(kind)


## Distance from the prop's centre to the edge of its body, going in world direction `dir`.
func edge_distance(dir: Vector2) -> float:
	var rect: Vector2 = MapData.PROPS.get(kind, {}).get("rect", Vector2.ZERO)
	if rect != Vector2.ZERO:
		var l := dir.rotated(-rotation)
		var h := rect * 0.5 * scale.x
		var tx := h.x / absf(l.x) if absf(l.x) > 0.001 else INF
		var ty := h.y / absf(l.y) if absf(l.y) > 0.001 else INF
		return minf(tx, ty)
	return MapData.prop_body_radius(kind) * scale.x


## Where someone coming from `from` should stand to use this prop: just outside it, on their side.
func approach_point(from: Vector2, gap: float = 18.0) -> Vector2:
	var d := from - global_position
	if d.length() < 0.5:
		d = Vector2.DOWN
	return global_position + d.normalized() * (_radius() + gap)


## Crates: lifts the lid and drops the loot (once). Returns the loot kind found ("none" = empty).
func open_container(from: Vector2) -> String:
	if not is_openable() or opened or locked:
		return "none"
	opened = true
	var found := loot
	if found == "water":
		water_inside = true  # shown filling the open container; nothing to pick up
		loot = "none"
	elif found != "none":
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("collect_loot"):
			p.call("collect_loot", found)  # picked up automatically
		else:
			LootDrop.spawn(get_tree().current_scene, found, approach_point(from, 4.0))
		loot = "none"
	queue_redraw()
	return found


## Water filling the inside of an opened crate / chest.
func _draw_water_fill(r: Rect2) -> void:
	if not water_inside:
		return
	var w := r.grow(-1.5)
	draw_rect(w, Color(0.2, 0.5, 0.68, 0.95))
	draw_rect(Rect2(w.position, Vector2(w.size.x, w.size.y * 0.4)), Color(0.4, 0.72, 0.86, 0.5))  # lit surface
	draw_arc(w.get_center() + Vector2(-2, -1), 3.5, 0.2, 2.6, 8, Color(1, 1, 1, 0.5), 1.0)  # ripple glint


func unlock() -> void:
	locked = false
	queue_redraw()


## Small brass padlock drawn on the front of a locked crate / chest.
func _draw_padlock() -> void:
	var c := Vector2.ZERO
	draw_arc(c + Vector2(0, -2.5), 3.6, PI, TAU, 10, Color("2b2b30"), 1.8)
	draw_rect(Rect2(c + Vector2(-4.5, -2.5), Vector2(9, 7.5)), Color("d9a82e"))
	draw_rect(Rect2(c + Vector2(-4.5, -2.5), Vector2(9, 7.5)), Color("5c4410"), false, 1.0)
	draw_circle(c + Vector2(0, 1), 1.1, Color("2a1c06"))


func take_damage(amount: int, _from: Node) -> void:
	if not is_in_group("breakable") or hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	_hit_flash = 0.15
	if hp == 0:
		_break_apart()
	queue_redraw()


## Barrel destroyed: burst effect, loot left behind, collision gone (path-finding updated).
func _break_apart() -> void:
	remove_from_group("containers")
	remove_from_group("breakable")
	var scene := get_tree().current_scene
	PropBurst.spawn(scene, global_position, scale.x)
	var p := get_tree().get_first_node_in_group("player")
	if loot == "water" or water_inside:
		WaterPuddle.spawn(get_parent(), position, scale.x)  # spills and pools where the barrel stood
	elif Weapons.is_ranged(loot) and p != null and p.has_method("collect_loot"):
		# A gun found inside goes straight onto the weapon wheel, like opening a crate.
		p.call("collect_loot", loot)
		if p.has_signal("notice"):
			p.emit_signal("notice", "Picked up: %s" % Weapons.label(loot))
	elif loot != "none":
		LootDrop.spawn(scene, loot, global_position)
	if p != null and p.has_method("refresh_nav"):
		var r := _radius() + 24.0
		p.call("refresh_nav", Rect2(global_position - Vector2(r, r), Vector2(r, r) * 2.0))
	defeated.emit(self)
	queue_free()


func _u(v: Vector2) -> Vector2:
	# Keeps light/shadow direction constant in world space even when the prop is rotated.
	return v.rotated(-rotation)


func _blob(r: float, n: int, jitter: float, rng: RandomNumberGenerator, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		var rr := r * (1.0 + rng.randf_range(-jitter, jitter))
		pts.append(off + Vector2(cos(a), sin(a)) * rr)
	return pts


func _outline(pts: PackedVector2Array, col: Color, width: float) -> void:
	var ol := PackedVector2Array(pts)
	ol.append(pts[0])
	draw_polyline(ol, col, width)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	match kind:
		"tree":
			_draw_canopy(rng, 56.0, 14, Color("35501a"), Color("4d6b1d"), Color("a3b84c"))
		"bush":
			_draw_canopy(rng, 26.0, 7, Color("3d5a1e"), Color("587a22"), Color("a9bf55"))
		"rock":
			_draw_rock(rng)
		"barrel":
			_draw_barrel()
		"crate":
			_draw_crate()
		"table":
			_draw_table()
		"well":
			_draw_well(rng)
		"torch":
			_draw_torch()
		"bench":
			_draw_bench()
		"window":
			_draw_window()
		"locomotive":
			_draw_locomotive()
		"coal_car":
			_draw_coal_car(rng)
		"smoke":
			_draw_smoke(rng)
		"wisp_smoke":
			_draw_wisp_smoke(rng)
		"cactus":
			_draw_cactus(rng)
		"palm":
			_draw_palm(rng)
		"pillar":
			_draw_pillar()
		"broken_pillar":
			_draw_broken_pillar(rng)
		"rubble":
			_draw_rubble(rng)
		"pine":
			_draw_pine(rng)
		"snowdrift":
			_draw_snowdrift(rng)
		"snowman":
			_draw_snowman()
		"campfire":
			_draw_campfire(rng)
		"stump":
			_draw_stump()
		"fireplace":
			_draw_fireplace(rng)
		"stall":
			_draw_stall()
		"fountain":
			_draw_fountain()
		"lamppost":
			_draw_lamppost()
		"cart":
			_draw_cart()
		"haybale":
			_draw_haybale(rng)
		"dead_tree":
			_draw_dead_tree(rng)
		"reeds":
			_draw_reeds(rng)
		"lilypad":
			_draw_lilypad(rng)
		"mushroom":
			_draw_mushroom(rng)
		"wagon_wheel":
			_draw_wagon_wheel()
		"wagon_hitch":
			_draw_wagon_hitch()
		"wagon_seat":
			_draw_wagon_seat()
		"trunk":
			_draw_trunk()
		"bedroll":
			_draw_bedroll(rng)
		"sacks":
			_draw_sacks(rng)
		"wagon_lantern":
			_draw_wagon_lantern()
		"weapon":
			_draw_weapon_pickup()
	if locked and not opened:
		_draw_padlock()


func _draw_canopy(rng: RandomNumberGenerator, r: float, clumps: int, base_col: Color, dark: Color, light: Color) -> void:
	draw_colored_polygon(_blob(r * 1.02, 20, 0.04, rng, _u(Vector2(r * 0.2, r * 0.25))), MapData.shadow_color(0.28))
	var base := _blob(r, 22, 0.08, rng)
	draw_colored_polygon(base, base_col)
	for i in clumps:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.2, 0.75) * r
		var cr := rng.randf_range(0.22, 0.38) * r
		var c := Vector2(cos(a), sin(a)) * d
		var col := dark.lerp(light, rng.randf())
		draw_colored_polygon(_blob(cr, 9, 0.15, rng, c), col.darkened(0.3))
		draw_colored_polygon(_blob(cr * 0.8, 9, 0.15, rng, c + _u(Vector2(-cr * 0.12, -cr * 0.18))), col)
	_outline(base, Color(0.08, 0.12, 0.04, 0.8), 2.0)


func _draw_rock(rng: RandomNumberGenerator) -> void:
	var r := 34.0
	draw_colored_polygon(_blob(r * 1.05, 9, 0.1, rng, _u(Vector2(8, 10))), MapData.shadow_color(0.3))
	var base := _blob(r, 9, 0.18, rng)
	draw_colored_polygon(base, Color("6f7370"))
	draw_colored_polygon(_blob(r * 0.72, 9, 0.18, rng, _u(Vector2(-5, -6))), Color("a2a8a2"))
	draw_colored_polygon(_blob(r * 0.4, 7, 0.2, rng, _u(Vector2(-9, -10))), Color("c5cbc4"))
	_outline(base, Color(0.1, 0.11, 0.1, 0.85), 2.0)
	for i in 3:
		var a := rng.randf() * TAU
		var p1 := Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 10.0)
		var p2 := p1 + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14))
		draw_line(p1, p2, Color(0.15, 0.17, 0.15, 0.7), 1.5)


func _draw_barrel() -> void:
	draw_circle(_u(Vector2(3, 4)), 14.0, MapData.shadow_color(0.3))
	draw_circle(Vector2.ZERO, 14.0, Color("5a3a1e"))
	draw_circle(Vector2.ZERO, 11.0, Color("7a5530"))
	draw_arc(Vector2.ZERO, 12.5, 0.0, TAU, 24, Color("2d2d2d"), 1.5)
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, Color(0.2, 0.12, 0.05, 0.8), 1.5)
	draw_line(Vector2(-10, 0), Vector2(10, 0), Color(0.25, 0.15, 0.07, 0.6), 1.0)
	if opened:
		# Lid off: dark empty inside (or full of water).
		draw_circle(Vector2.ZERO, 10.0, Color("2a1a0c"))
		if water_inside:
			draw_circle(Vector2.ZERO, 8.5, Color(0.2, 0.5, 0.68, 0.95))
			draw_arc(Vector2(-2, -1), 3.5, 0.2, 2.6, 8, Color(1, 1, 1, 0.5), 1.0)
		draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 20, Color("1a1008"), 1.5)
	if hp > 0 and hp < max_hp():  # splintered once hit
		var dmg := 1.0 - float(hp) / BARREL_HP
		for i in int(ceil(dmg * 4.0)):
			var a := 0.7 + i * 1.6
			draw_line(Vector2(cos(a), sin(a)) * 4.0, Vector2(cos(a + 0.3), sin(a + 0.3)) * 12.0, Color(0.15, 0.08, 0.03, 0.9), 1.2)
	if _hit_flash > 0.0:
		draw_circle(Vector2.ZERO, 14.0, Color(1, 0.9, 0.6, _hit_flash * 3.0))


func _draw_crate() -> void:
	draw_rect(Rect2(Vector2(-16, -16) + _u(Vector2(3, 4)), Vector2(32, 32)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-16, -16, 32, 32), Color("7a5530"))
	draw_rect(Rect2(-16, -16, 32, 32), Color("2b1a0b"), false, 2.0)
	if _hit_flash > 0.0:
		draw_rect(Rect2(-16, -16, 32, 32), Color(1, 0.9, 0.6, _hit_flash * 3.0))
	if hp > 0 and hp < max_hp():  # split boards once hit
		var dmg := 1.0 - float(hp) / max_hp()
		for i in int(ceil(dmg * 4.0)):
			var y := -10.0 + i * 6.5
			draw_line(Vector2(-14, y), Vector2(-2 + i * 3, y + 4), Color(0.12, 0.07, 0.02, 0.9), 1.2)
	if opened:
		# Lid off: dark empty inside, lid propped against one side.
		draw_rect(Rect2(-13, -13, 26, 26), Color("2a1a0c"))
		_draw_water_fill(Rect2(-13, -13, 26, 26))
		draw_rect(Rect2(-13, -13, 26, 26), Color("1a1008"), false, 1.5)
		draw_set_transform(Vector2(13, -20), 0.35, Vector2.ONE)
		draw_rect(Rect2(-14, -4, 28, 8), Color("8a6034"))
		draw_rect(Rect2(-14, -4, 28, 8), Color("2b1a0b"), false, 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_rect(Rect2(-11, -11, 22, 22), Color("5e4023"), false, 2.0)
	draw_line(Vector2(-11, -11), Vector2(11, 11), Color("5e4023"), 2.0)
	draw_line(Vector2(11, -11), Vector2(-11, 11), Color("5e4023"), 2.0)


func _draw_table() -> void:
	draw_rect(Rect2(Vector2(-40, -22) + _u(Vector2(5, 7)), Vector2(80, 44)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-40, -22, 80, 44), Color("8a6034"))
	for i in 5:
		draw_line(Vector2(-40, -22 + i * 11.0), Vector2(40, -22 + i * 11.0), Color("5e4023"), 1.0)
	draw_rect(Rect2(-40, -22, 80, 44), Color("2b1a0b"), false, 2.5)
	for x in [-26.0, -8.0, 10.0, 26.0]:
		draw_circle(Vector2(x, -8.0), 5.0, Color("d9d2c0"))
		draw_circle(Vector2(x + 2.0, 9.0), 4.0, Color("b8453a"))


func _draw_well(rng: RandomNumberGenerator) -> void:
	draw_circle(_u(Vector2(5, 7)), 36.0, MapData.shadow_color(0.3))
	draw_circle(Vector2.ZERO, 36.0, Color("6c6a63"))
	for i in 14:
		var a := TAU * float(i) / 14.0
		var c := Vector2(cos(a), sin(a)) * 29.0
		draw_colored_polygon(_blob(7.5, 7, 0.2, rng, c), Color("8f8c83").darkened(rng.randf() * 0.25))
	draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 32, Color(0.1, 0.1, 0.09, 0.9), 2.0)
	draw_circle(Vector2.ZERO, 21.0, Color("1a2a30"))
	draw_circle(Vector2.ZERO, 17.0, Color("2f6672"))
	draw_arc(Vector2(-4, -4), 8.0, 3.5, 5.0, 8, Color(1, 1, 1, 0.35), 2.0)


func _draw_torch() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.55, 0.2, 0.10))
	draw_circle(Vector2.ZERO, 14.0, Color(1.0, 0.6, 0.2, 0.18))
	draw_circle(Vector2.ZERO, 8.0, Color(1.0, 0.7, 0.25, 0.4))
	draw_circle(Vector2.ZERO, 6.0, Color("3a2a1a"))
	draw_circle(Vector2.ZERO, 3.5, Color("ffd36b"))


# ---------------------------------------------------------------- train theme

func _draw_bench() -> void:
	draw_rect(Rect2(Vector2(-35, -14) + _u(Vector2(3, 4)), Vector2(70, 28)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-35, -14, 70, 28), Color("5e4023"))
	draw_rect(Rect2(-32, -9, 64, 20), Color("b3342f"))
	draw_rect(Rect2(-32, -9, 64, 20), Color("4d1210"), false, 1.5)
	draw_line(Vector2(-32, 1), Vector2(32, 1), Color(0.3, 0.07, 0.06, 0.7), 1.0)
	draw_rect(Rect2(-35, -14, 70, 28), Color("1d1209"), false, 2.0)


func _draw_window() -> void:
	draw_rect(Rect2(-22, -6, 44, 12), Color("1a2b30"))
	draw_rect(Rect2(-20, -4.5, 40, 9), Color("7fd0d6"))
	draw_rect(Rect2(-20, -4.5, 40, 3.5), Color("b6eef0"))
	draw_line(Vector2(0, -6), Vector2(0, 6), Color("1a2b30"), 1.5)


func _draw_locomotive() -> void:
	# Top-down, front (smokestack) points to -Y, cab at +Y. Footprint 150 x 430.
	var sh := _u(Vector2(8, 10))
	draw_rect(Rect2(Vector2(-64, -170) + sh, Vector2(128, 262)), MapData.shadow_color(0.3))
	draw_rect(Rect2(Vector2(-75, 88) + sh, Vector2(150, 127)), MapData.shadow_color(0.3))
	# side rods and running board
	draw_rect(Rect2(-64, -170, 128, 260), Color("23252b"))
	for sx in [-1.0, 1.0]:
		draw_line(Vector2(sx * 60.0, -150), Vector2(sx * 60.0, 70), Color("5f6670"), 5.0)
		for wy in [-110.0, -60.0, -10.0, 40.0]:
			draw_circle(Vector2(sx * 62.0, wy), 9.0, Color("15171b"))
			draw_circle(Vector2(sx * 62.0, wy), 5.0, Color("8a919a"))
	# cow catcher
	draw_colored_polygon(PackedVector2Array([Vector2(-48, -170), Vector2(48, -170), Vector2(0, -215)]), Color("2a2c33"))
	draw_polyline(PackedVector2Array([Vector2(-48, -170), Vector2(0, -215), Vector2(48, -170)]), Color("0e0f12"), 2.5)
	# boiler
	draw_rect(Rect2(-48, -170, 96, 262), Color("a9253a"))
	draw_rect(Rect2(-34, -170, 22, 262), Color("cf4457"))
	draw_rect(Rect2(26, -170, 22, 262), Color("7d1828"))
	draw_rect(Rect2(-48, -170, 96, 262), Color("2a0710"), false, 3.0)
	for by in [-130.0, -60.0, 10.0, 70.0]:
		draw_rect(Rect2(-49, by, 98, 8), Color("d9a82e"))
		draw_rect(Rect2(-49, by, 98, 8), Color("5c4410"), false, 1.0)
	# front cap, chimney, dome, whistle
	draw_circle(Vector2(0, -170), 48.0, Color("a9253a"))
	draw_arc(Vector2(0, -170), 48.0, PI, TAU, 24, Color("2a0710"), 3.0)
	draw_circle(Vector2(0, -168), 26.0, Color("2a2c33"))
	draw_circle(Vector2(0, -168), 16.0, Color("0b0b0d"))
	draw_circle(Vector2(0, -85), 20.0, Color("d9a82e"))
	draw_circle(Vector2(0, -85), 13.0, Color("a57d17"))
	draw_circle(Vector2(0, -40), 8.0, Color("d9a82e"))
	draw_circle(Vector2(-6, -92), 4.0, Color("f2d27a"))
	# cab
	draw_rect(Rect2(-75, 88, 150, 127), Color("8a1f2c"))
	draw_rect(Rect2(-75, 88, 150, 127), Color("1c050a"), false, 3.0)
	draw_rect(Rect2(-66, 98, 132, 107), Color("3b3f4a"))
	for ry in 7:
		var yy := 98.0 + ry * 15.3
		draw_line(Vector2(-66, yy), Vector2(66, yy), Color("23262d"), 1.5)
	draw_rect(Rect2(-66, 98, 132, 107), Color("15171b"), false, 2.0)
	draw_rect(Rect2(-12, 205, 24, 10), Color("2a2c33"))


func _draw_coal_car(rng: RandomNumberGenerator) -> void:
	draw_rect(Rect2(Vector2(-95, -95) + _u(Vector2(7, 9)), Vector2(190, 190)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-95, -95, 190, 190), Color("9e2433"))
	draw_rect(Rect2(-95, -95, 190, 190), Color("1c050a"), false, 3.0)
	draw_rect(Rect2(-76, -76, 152, 152), Color("1f1d22"))
	draw_rect(Rect2(-76, -76, 152, 152), Color("0b0a0c"), false, 2.5)
	for i in 34:
		var p := Vector2(rng.randf_range(-68, 68), rng.randf_range(-68, 68))
		var r := rng.randf_range(5.0, 11.0)
		draw_colored_polygon(_blob(r, 7, 0.25, rng, p), Color("34323a").lerp(Color("5b5963"), rng.randf()))
		draw_colored_polygon(_blob(r * 0.45, 5, 0.2, rng, p + _u(Vector2(-2, -3))), Color("8a8893"))
	# coupling bar
	draw_rect(Rect2(-8, -110, 16, 16), Color("23252b"))


func _draw_smoke(rng: RandomNumberGenerator) -> void:
	var r := 90.0
	for i in 16:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.62) * r
		var cr := rng.randf_range(0.28, 0.48) * r
		# Animation: each puff slowly circles the cloud centre, swells and shrinks, and bobs a little.
		# Speeds come from the puff index so the random layout from the seed is unchanged.
		var spin := (0.10 + 0.05 * float(i % 4)) * (1.0 if i % 2 == 0 else -1.0)
		var phase := float(i) * 1.7
		a += _smoke_t * spin
		d *= 1.0 + 0.18 * sin(_smoke_t * 0.7 + phase)
		cr *= 1.0 + 0.10 * sin(_smoke_t * 0.9 + phase * 1.3)
		var c := Vector2(cos(a), sin(a)) * d + Vector2(sin(_smoke_t * 0.5 + phase), cos(_smoke_t * 0.4 + phase)) * 4.0
		var g := rng.randf_range(0.34, 0.56)
		draw_colored_polygon(_blob(cr, 12, 0.14, rng, c), Color(g * 0.7, g * 0.7, g * 0.74, 0.9))
		draw_colored_polygon(_blob(cr * 0.75, 12, 0.14, rng, c + _u(Vector2(-cr * 0.12, -cr * 0.15))), Color(g, g, g * 1.04, 0.9))


## Thin, translucent smoke: a few tapering ribbons that sway in S-curves and slowly drift.
## Each ribbon is drawn as three stacked layers (wide and faint to narrow and brighter) with a
## fine rim line, which gives the soft, see-through edges of curling smoke.
func _draw_wisp_smoke(rng: RandomNumberGenerator) -> void:
	var half := 100.0
	var steps := 28
	for i in 5:
		# Random look per ribbon (always drawn, so the seeded layout is stable).
		var y_off := rng.randf_range(-34.0, 34.0)
		var amp := rng.randf_range(14.0, 30.0)
		var freq := rng.randf_range(0.7, 1.4)
		var phase := rng.randf() * TAU
		var tilt := rng.randf_range(-0.4, 0.4)
		var width := rng.randf_range(5.0, 11.0)
		var alpha := rng.randf_range(0.12, 0.2)
		var tone := rng.randf_range(0.86, 0.97)
		var speed := rng.randf_range(0.25, 0.5) * (1.0 if i % 2 == 0 else -1.0)
		var t := _smoke_t * speed

		var centres := PackedVector2Array()
		var widths := PackedFloat32Array()
		for k in steps + 1:
			var u := float(k) / float(steps)
			var y := y_off + amp * sin(u * TAU * freq + phase + t) + amp * 0.4 * sin(u * TAU * 2.3 - t * 1.4 + phase * 2.0)
			centres.append(Vector2(lerpf(-half, half, u), y).rotated(tilt))
			var taper := pow(sin(PI * u), 0.9)
			widths.append(maxf(width * taper * (1.0 + 0.25 * sin(_smoke_t * 0.6 + phase + u * 5.0)), 0.4))

		for layer in 3:
			var wk: float = [1.0, 0.6, 0.28][layer]
			var ak: float = [0.55, 0.8, 1.0][layer]
			var top := PackedVector2Array()
			var bottom := PackedVector2Array()
			var cols := PackedColorArray()
			for k in steps + 1:
				var prev := centres[maxi(k - 1, 0)]
				var next := centres[mini(k + 1, steps)]
				var normal := (next - prev).normalized().orthogonal()
				var w: float = widths[k] * wk
				top.append(centres[k] + normal * w)
				bottom.append(centres[k] - normal * w)
				var fade := sin(PI * float(k) / float(steps))  # both ends fade to nothing
				cols.append(Color(tone, tone, tone + 0.03, alpha * ak * fade))
			if layer == 0:  # fine bright rim along both edges
				var rim := PackedColorArray()
				for c in cols:
					rim.append(Color(1.0, 1.0, 1.0, c.a * 0.9))
				draw_polyline_colors(top, rim, 1.2, true)
				draw_polyline_colors(bottom, rim, 1.2, true)
			# Closed outline: down one edge, back along the other (colours mirror the fade).
			var outline := top.duplicate()
			var outline_cols := cols.duplicate()
			for k in range(steps, -1, -1):
				outline.append(bottom[k])
				outline_cols.append(cols[k])
			draw_polygon(outline, outline_cols)


# ---------------------------------------------------------------- desert theme

func _draw_cactus(rng: RandomNumberGenerator) -> void:
	var base_col := Color("2f5a22")
	var dark := Color("3e7a2e")
	var light := Color("8fc255")
	var outline := Color(0.06, 0.14, 0.05, 0.85)
	# Shadow
	draw_colored_polygon(_blob(15.0, 14, 0.06, rng, _u(Vector2(5, 6))), MapData.shadow_color(0.28))
	# Arms: layered blobs (dark base, mid tone, offset highlight), like the tree clumps
	var arms: Array = []
	for sx in [-1.0, 1.0]:
		arms.append(Vector2(sx * 17.0, rng.randf_range(-7.0, 7.0)))
	for arm_v in arms:
		var arm: Vector2 = arm_v
		var mid: Vector2 = arm * 0.5
		for c in [Vector2.ZERO, mid, arm]:
			draw_colored_polygon(_blob(7.0, 9, 0.1, rng, c), base_col)
		_outline(_blob(7.0, 9, 0.0, rng, arm), outline, 1.5)
		for c in [mid, arm]:
			var col := dark.lerp(light, rng.randf_range(0.0, 0.5))
			draw_colored_polygon(_blob(5.2, 9, 0.12, rng, c), col.darkened(0.25))
			draw_colored_polygon(_blob(4.0, 9, 0.12, rng, c + _u(Vector2(-1.2, -1.8))), col)
	# Body
	var body := _blob(13.0, 16, 0.07, rng)
	draw_colored_polygon(body, base_col)
	for i in 5:
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 7.0)
		var cr := rng.randf_range(3.5, 6.0)
		var col := dark.lerp(light, rng.randf())
		draw_colored_polygon(_blob(cr, 8, 0.15, rng, c), col.darkened(0.25))
		draw_colored_polygon(_blob(cr * 0.78, 8, 0.15, rng, c + _u(Vector2(-cr * 0.12, -cr * 0.18))), col)
	# Ribs and spines
	for i in 8:
		var a := TAU * float(i) / 8.0
		draw_line(Vector2(cos(a), sin(a)) * 4.0, Vector2(cos(a), sin(a)) * 11.5, Color(0.1, 0.22, 0.08, 0.55), 1.0)
	draw_circle(Vector2.ZERO, 2.5, Color("f08aa8"))
	_outline(body, outline, 2.0)


func _draw_palm(rng: RandomNumberGenerator) -> void:
	draw_colored_polygon(_blob(46.0, 16, 0.1, rng, _u(Vector2(12, 16))), MapData.shadow_color(0.25))
	var n := 9
	var off := rng.randf() * TAU
	for i in n:
		var a := off + TAU * float(i) / float(n)
		var dir := Vector2(cos(a), sin(a))
		var side := dir.orthogonal()
		var len := rng.randf_range(54.0, 64.0)
		var tip := dir * len
		var pts := PackedVector2Array([Vector2.ZERO, dir * len * 0.4 + side * 13.0, tip, dir * len * 0.4 - side * 13.0])
		draw_colored_polygon(pts, Color("3f7a2a").lerp(Color("6aa33c"), rng.randf()))
		draw_line(Vector2.ZERO, tip, Color("2a5a1c"), 1.5)
	draw_circle(Vector2.ZERO, 9.0, Color("6a4a2a"))
	for i in 3:
		draw_circle(Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)), 3.5, Color("8a5a2a"))


func _draw_pillar() -> void:
	draw_rect(Rect2(Vector2(-24, -24) + _u(Vector2(5, 7)), Vector2(48, 48)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-24, -24, 48, 48), Color("b2a07c"))
	draw_rect(Rect2(-24, -24, 48, 48), Color("3d3320"), false, 2.0)
	draw_circle(Vector2.ZERO, 19.0, Color("cdbc98"))
	draw_circle(_u(Vector2(-4, -5)), 11.0, Color("e0d2b0"))
	draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 24, Color("3d3320"), 1.5)
	for i in 8:
		var a := TAU * float(i) / 8.0
		draw_line(Vector2(cos(a), sin(a)) * 12.0, Vector2(cos(a), sin(a)) * 19.0, Color(0.3, 0.25, 0.15, 0.6), 1.0)


func _draw_broken_pillar(rng: RandomNumberGenerator) -> void:
	draw_rect(Rect2(Vector2(-22, -22) + _u(Vector2(4, 6)), Vector2(44, 44)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-22, -22, 44, 44), Color("a08e6a"))
	draw_rect(Rect2(-22, -22, 44, 44), Color("3d3320"), false, 2.0)
	var stump := PackedVector2Array()
	for i in 12:
		var a := TAU * float(i) / 12.0
		stump.append(Vector2(cos(a), sin(a)) * (16.0 + rng.randf_range(-3.0, 3.0)))
	draw_colored_polygon(stump, Color("cdbc98"))
	draw_colored_polygon(_blob(8.0, 8, 0.2, rng, _u(Vector2(-3, -4))), Color("e0d2b0"))
	_outline(stump, Color("3d3320"), 1.5)
	for i in 3:
		var c := Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
		draw_colored_polygon(_blob(rng.randf_range(4.0, 8.0), 6, 0.3, rng, c), Color("bba98a"))


func _draw_rubble(rng: RandomNumberGenerator) -> void:
	for i in 9:
		var a := rng.randf() * TAU
		var c := Vector2(cos(a), sin(a)) * rng.randf_range(0.0, 20.0)
		var r := rng.randf_range(5.0, 11.0)
		draw_colored_polygon(_blob(r, 6, 0.3, rng, c + _u(Vector2(2, 3))), MapData.shadow_color(0.25))
		var blob := _blob(r, 6, 0.3, rng, c)
		draw_colored_polygon(blob, Color("a8967a").lerp(Color("d0c0a0"), rng.randf()))
		_outline(blob, Color(0.25, 0.2, 0.12, 0.7), 1.0)


# ---------------------------------------------------------------- snow theme

func _draw_pine(rng: RandomNumberGenerator) -> void:
	draw_colored_polygon(_blob(50.0, 16, 0.05, rng, _u(Vector2(10, 14))), Color(0.1, 0.15, 0.25, 0.28))
	var layers := [[52.0, Color("1f4a32")], [40.0, Color("2a6040")], [27.0, Color("367a4e")], [14.0, Color("46935e")]]
	var off := rng.randf() * TAU
	for l in layers:
		var r: float = l[0]
		var pts := PackedVector2Array()
		for i in 20:
			var a := off + TAU * float(i) / 20.0
			pts.append(Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.6))
		draw_colored_polygon(pts, l[1])
		# snow on the upper-left of each tier
		var sn := PackedVector2Array()
		for i in 20:
			var a2 := off + TAU * float(i) / 20.0
			var rr := (r if i % 2 == 0 else r * 0.6) * 0.8
			sn.append(Vector2(cos(a2), sin(a2)) * rr + _u(Vector2(-r * 0.1, -r * 0.12)))
		draw_colored_polygon(sn, Color(0.93, 0.96, 1.0, 0.55))
		_outline(pts, Color(0.05, 0.12, 0.08, 0.7), 1.0)
	draw_circle(Vector2.ZERO, 4.0, Color("f4f8ff"))


func _draw_snowdrift(rng: RandomNumberGenerator) -> void:
	draw_colored_polygon(_blob(34.0, 14, 0.15, rng, _u(Vector2(5, 7))), Color(0.45, 0.55, 0.75, 0.35))
	var base := _blob(32.0, 14, 0.15, rng)
	draw_colored_polygon(base, Color("e6eef8"))
	draw_colored_polygon(_blob(22.0, 12, 0.15, rng, _u(Vector2(-4, -5))), Color("f8fbff"))
	_outline(base, Color(0.55, 0.65, 0.8, 0.7), 1.5)


func _draw_snowman() -> void:
	draw_circle(_u(Vector2(5, 6)), 17.0, Color(0.3, 0.4, 0.6, 0.35))
	draw_circle(Vector2.ZERO, 17.0, Color("e8eff8"))
	draw_circle(_u(Vector2(-4, -5)), 10.0, Color("ffffff"))
	draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 24, Color(0.4, 0.5, 0.65, 0.8), 1.5)
	for y in [-4.0, 3.0, 10.0]:
		draw_circle(Vector2(0, y), 1.6, Color("22252b"))
	# head with hat and carrot
	draw_circle(Vector2(0, -2), 10.0, Color("f4f8ff"))
	draw_circle(Vector2(0, -2), 10.0, Color(0.4, 0.5, 0.65, 0.0))
	draw_circle(Vector2(0, -2), 7.0, Color("22252b"))
	draw_circle(Vector2(0, -2), 4.5, Color("3a3d46"))
	draw_circle(Vector2(0, -2), 1.5, Color("e8731f"))


func _draw_campfire(rng: RandomNumberGenerator) -> void:
	draw_circle(Vector2.ZERO, 40.0, Color(1.0, 0.5, 0.15, 0.07))
	draw_circle(Vector2.ZERO, 28.0, Color(1.0, 0.55, 0.2, 0.12))
	for i in 9:
		var a := TAU * float(i) / 9.0
		var c := Vector2(cos(a), sin(a)) * 19.0
		draw_colored_polygon(_blob(5.5, 6, 0.25, rng, c), Color("6a6862").lerp(Color("9a9890"), rng.randf()))
	for i in 4:
		var a2 := PI * 0.25 + float(i) * PI * 0.5
		var d := Vector2(cos(a2), sin(a2)) * 13.0
		draw_line(-d, d, Color("4a2e18"), 5.0)
		draw_line(-d, d, Color("6a4524"), 2.5)
	# Animated flames: flickering tongues, pulsing core, rising embers
	var t := Time.get_ticks_msec() / 1000.0 + float(seed_v) * 1.7
	var pulse := 1.0 + 0.1 * sin(t * 9.0) + 0.06 * sin(t * 17.0)
	draw_circle(Vector2.ZERO, 11.0 * pulse, Color("b8300f"))
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.4 * sin(t * 2.0 + float(i))
		var dir := Vector2(cos(a), sin(a))
		var side := dir.orthogonal()
		var len := (13.0 + 4.0 * sin(t * 7.0 + float(i) * 2.3) + 2.0 * sin(t * 13.0 + float(i))) * pulse
		var pts := PackedVector2Array([dir * 2.0 + side * 4.0, dir * len, dir * 2.0 - side * 4.0])
		draw_colored_polygon(pts, Color("e8501a"))
		var pts2 := PackedVector2Array([dir * 1.5 + side * 2.5, dir * len * 0.65, dir * 1.5 - side * 2.5])
		draw_colored_polygon(pts2, Color("ff9a28"))
	draw_circle(Vector2.ZERO, 6.0 * pulse, Color("ff9a28"))
	draw_circle(Vector2.ZERO, 3.2 * (1.0 + 0.15 * sin(t * 12.0)), Color("ffe27a"))
	for i in 5:
		var ph := fposmod(t * 0.7 + float(i) * 0.2, 1.0)
		var ang := float(i) * 1.9 + t * 0.5
		var p := Vector2(cos(ang), sin(ang)) * (6.0 + ph * 22.0)
		draw_circle(p, 1.4 * (1.0 - ph), Color(1.0, 0.7, 0.2, 1.0 - ph))


func _process(delta: float) -> void:
	if _pickup_live:
		_tick_pickup(delta)
	if kind == "campfire" or kind == "fireplace":
		queue_redraw()
	if kind == "smoke" or kind == "wisp_smoke":
		_smoke_t += delta
		queue_redraw()
	if _hit_flash > 0.0:  # barrel hit flash fading out
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		queue_redraw()


## Square stone hearth: a border of fitted stones round a dark pit with glowing coals and flames.
func _draw_fireplace(rng: RandomNumberGenerator) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + float(seed_v) * 1.7
	var pulse := 1.0 + 0.08 * sin(t * 9.0) + 0.05 * sin(t * 17.0)
	# Warm glow spilling onto the floor
	draw_circle(Vector2.ZERO, 46.0, Color(1.0, 0.5, 0.15, 0.06 * pulse))
	draw_circle(Vector2.ZERO, 36.0, Color(1.0, 0.55, 0.2, 0.10 * pulse))
	# Square stone border: 60x60 slab, 4 stones per side along a 12 px wide frame
	var half := 30.0
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), Color("2b2824"))
	var n := 5
	var step := half * 2.0 / float(n)
	for side in 4:
		for i in n:
			var along := -half + step * (float(i) + 0.5)
			var pos := Vector2(along, -half + 6.0)
			pos = pos.rotated(PI * 0.5 * float(side))
			var stone := Color("7c786f").lerp(Color("a39f94"), rng.randf()).darkened(rng.randf() * 0.2)
			var sr := Rect2(pos - Vector2(step, 12.0) * 0.5 + Vector2(0.5, 0.5), Vector2(step, 12.0) - Vector2(1, 1))
			if side % 2 == 1:
				sr = Rect2(pos - Vector2(12.0, step) * 0.5 + Vector2(0.5, 0.5), Vector2(12.0, step) - Vector2(1, 1))
			draw_rect(sr, stone)
			draw_rect(Rect2(sr.position, Vector2(sr.size.x, 1.5)), stone.lightened(0.18))
			draw_rect(sr, Color(0.08, 0.07, 0.06, 0.6), false, 1.0)
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), Color(0.08, 0.07, 0.06, 0.9), false, 1.5)
	# Ash pit and coals
	draw_rect(Rect2(-18, -18, 36, 36), Color("15110e"))
	draw_rect(Rect2(-16, -16, 32, 32), Color("3a1a0e"))
	draw_rect(Rect2(Vector2(-12, -12) * pulse, Vector2(24, 24) * pulse), Color("b8300f"))
	# Logs
	for i in 3:
		var a2 := float(i) * PI / 3.0 + 0.5
		var d := Vector2(cos(a2), sin(a2)) * 10.0
		draw_line(-d, d, Color("3a2412"), 4.5)
		draw_line(-d, d, Color("5c3c1e"), 2.2)
	# Flames
	for i in 6:
		var a3 := TAU * float(i) / 6.0 + 0.4 * sin(t * 2.0 + float(i))
		var dir := Vector2(cos(a3), sin(a3))
		var side := dir.orthogonal()
		var len := (11.0 + 3.5 * sin(t * 7.0 + float(i) * 2.3) + 2.0 * sin(t * 13.0 + float(i))) * pulse
		draw_colored_polygon(PackedVector2Array([dir * 2.0 + side * 3.6, dir * len, dir * 2.0 - side * 3.6]), Color("e8501a"))
		draw_colored_polygon(PackedVector2Array([dir * 1.5 + side * 2.2, dir * len * 0.65, dir * 1.5 - side * 2.2]), Color("ff9a28"))
	draw_circle(Vector2.ZERO, 5.5 * pulse, Color("ff9a28"))
	draw_circle(Vector2.ZERO, 3.0 * (1.0 + 0.15 * sin(t * 12.0)), Color("ffe27a"))
	# Rising sparks
	for i in 4:
		var ph := fposmod(t * 0.7 + float(i) * 0.25, 1.0)
		var ang := float(i) * 2.1 + t * 0.5
		draw_circle(Vector2(cos(ang), sin(ang)) * (5.0 + ph * 18.0), 1.3 * (1.0 - ph), Color(1.0, 0.7, 0.2, 1.0 - ph))


func _draw_stump() -> void:
	# No drop shadow: a stump sits flush with the ground.
	draw_circle(Vector2.ZERO, 15.0, Color("4e3420"))
	draw_circle(Vector2.ZERO, 12.0, Color("a07a4a"))
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 16, Color("6e4e2a"), 1.0)
	draw_arc(Vector2.ZERO, 4.0, 0.0, TAU, 12, Color("6e4e2a"), 1.0)
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 20, Color(0.12, 0.08, 0.04, 0.8), 1.5)


# ---------------------------------------------------------------- town theme

func _draw_stall() -> void:
	var w := 96.0
	var h := 64.0
	draw_rect(Rect2(Vector2(-w * 0.5, -h * 0.5) + _u(Vector2(6, 8)), Vector2(w, h)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color("6a4a2a"))
	# striped awning
	var stripes := 8
	var sw := w / float(stripes)
	for i in stripes:
		var col := Color("c23b3b") if i % 2 == 0 else Color("f1e9d8")
		draw_rect(Rect2(-w * 0.5 + i * sw, -h * 0.5, sw, h - 8.0), col)
		draw_circle(Vector2(-w * 0.5 + i * sw + sw * 0.5, h * 0.5 - 8.0), sw * 0.5, col)
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h - 8.0), Color(0.15, 0.08, 0.05, 0.8), false, 2.0)
	draw_line(Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0), Color(0, 0, 0, 0.18), 1.0)


func _draw_fountain() -> void:
	draw_circle(_u(Vector2(6, 8)), 50.0, MapData.shadow_color(0.3))
	draw_circle(Vector2.ZERO, 50.0, Color("8a867c"))
	draw_circle(Vector2.ZERO, 43.0, Color("b0aa9c"))
	draw_circle(Vector2.ZERO, 37.0, Color("3f8ea0"))
	draw_circle(Vector2.ZERO, 30.0, Color("58a8b8"))
	draw_arc(Vector2.ZERO, 22.0, 0.3, 2.0, 12, Color(1, 1, 1, 0.35), 2.0)
	draw_arc(Vector2.ZERO, 30.0, 3.5, 5.2, 12, Color(1, 1, 1, 0.3), 2.0)
	draw_arc(Vector2.ZERO, 50.0, 0.0, TAU, 32, Color(0.12, 0.11, 0.1, 0.9), 2.0)
	draw_arc(Vector2.ZERO, 37.0, 0.0, TAU, 28, Color(0.12, 0.11, 0.1, 0.7), 1.5)
	draw_circle(Vector2.ZERO, 11.0, Color("9e9a90"))
	draw_circle(_u(Vector2(-2, -3)), 6.0, Color("c8c3b6"))
	draw_circle(Vector2.ZERO, 3.0, Color("d8f4f8"))


func _draw_lamppost() -> void:
	draw_circle(Vector2.ZERO, 30.0, Color(1.0, 0.8, 0.4, 0.08))
	draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.8, 0.4, 0.16))
	draw_circle(_u(Vector2(2, 3)), 7.0, MapData.shadow_color(0.3))
	draw_circle(Vector2.ZERO, 7.0, Color("23252b"))
	draw_circle(Vector2.ZERO, 5.0, Color("ffd98a"))
	draw_circle(Vector2.ZERO, 2.5, Color("fff4c8"))
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 14, Color("0e0f12"), 1.5)


func _draw_cart() -> void:
	var w := 84.0
	var h := 52.0
	draw_rect(Rect2(Vector2(-w * 0.5, -h * 0.5) + _u(Vector2(5, 7)), Vector2(w, h)), MapData.shadow_color(0.3))
	# wheels
	for sy in [-1.0, 1.0]:
		draw_rect(Rect2(-14, sy * (h * 0.5) - 5.0, 28, 10), Color("2a1c10"))
	# handles
	draw_line(Vector2(-w * 0.5, -10), Vector2(-w * 0.5 - 22, -14), Color("5e4023"), 4.0)
	draw_line(Vector2(-w * 0.5, 10), Vector2(-w * 0.5 - 22, 14), Color("5e4023"), 4.0)
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color("7a5530"))
	for i in 5:
		draw_line(Vector2(-w * 0.5, -h * 0.5 + i * h / 5.0), Vector2(w * 0.5, -h * 0.5 + i * h / 5.0), Color("4a3018"), 1.0)
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color("1d1209"), false, 2.5)
	draw_rect(Rect2(-w * 0.5 + 6, -h * 0.5 + 6, w - 12, h - 12), Color("d6b45a"))
	for i in 6:
		draw_circle(Vector2(-26 + i * 10.0, -8 + (i % 2) * 14.0), 5.5, Color("c9a23e"))
	draw_rect(Rect2(-w * 0.5 + 6, -h * 0.5 + 6, w - 12, h - 12), Color("6a4e14"), false, 1.0)


func _draw_haybale(rng: RandomNumberGenerator) -> void:
	draw_rect(Rect2(Vector2(-22, -15) + _u(Vector2(4, 5)), Vector2(44, 30)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-22, -15, 44, 30), Color("d6b44a"))
	for i in 14:
		var x := rng.randf_range(-20, 20)
		var y := rng.randf_range(-13, 13)
		draw_line(Vector2(x, y), Vector2(x + rng.randf_range(-6, 6), y + rng.randf_range(-3, 3)), Color("a8862a"), 1.0)
	for x in [-11.0, 11.0]:
		draw_line(Vector2(x, -15), Vector2(x, 15), Color("6a4a1c"), 2.0)
	draw_rect(Rect2(-22, -15, 44, 30), Color("5a4010"), false, 2.0)


# ---------------------------------------------------------------- covered wagon theme
# Parts are drawn with the wagon's length along local y; the hitch end of a wagon is -y.

## Seen from above a wheel is its rim edge-on: a narrow wooden band with an iron tyre,
## spoke ends showing along it and the hub poking out on the outer (+x) side.
func _draw_wagon_wheel() -> void:
	var w := 10.0
	var h := 46.0
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)
	draw_rect(Rect2(r.position + _u(Vector2(3, 4)), r.size), MapData.shadow_color(0.32))
	draw_rect(r, Color("4a3018"))
	for i in 6:  # spoke ends / felloe joints
		var y := -h * 0.5 + 4.0 + i * (h - 8.0) / 5.0
		draw_line(Vector2(-w * 0.5, y), Vector2(w * 0.5, y), Color("2a1a0c"), 1.2)
	draw_rect(Rect2(-w * 0.5 + 2.5, -h * 0.5, w - 5.0, h), Color(0.62, 0.42, 0.24, 0.35))  # worn top of the rim
	draw_rect(r, Color("1b1b1e"), false, 2.0)  # iron tyre
	draw_line(Vector2(-w * 0.5 + 1.0, -h * 0.5 + 3.0), Vector2(-w * 0.5 + 1.0, h * 0.5 - 3.0), Color(0.6, 0.6, 0.64, 0.55), 1.0)
	# Hub and axle cap on the outside.
	draw_rect(Rect2(w * 0.5 - 1.0, -6.0, 6.0, 12.0), Color("5a3c20"))
	draw_rect(Rect2(w * 0.5 - 1.0, -6.0, 6.0, 12.0), Color("1d1209"), false, 1.0)
	draw_circle(Vector2(w * 0.5 + 5.5, 0), 3.2, Color("2b2b30"))
	draw_circle(Vector2(w * 0.5 + 5.0, -0.8), 1.2, Color(0.75, 0.75, 0.8, 0.7))


## Tongue (pole) running forward from the wagon, ending in the doubletree crossbar with two
## singletrees where the team is hitched. The attachment end is +y, the team end is -y.
func _draw_wagon_hitch() -> void:
	var wood := Color("6b4526")
	var wood_hi := Color("8f6338")
	var dark := Color("1d1209")
	var iron := Color("2b2b30")
	var sh := _u(Vector2(3, 4))
	# shadow
	draw_line(Vector2(0, 58) + sh, Vector2(0, -46) + sh, MapData.shadow_color(0.3), 6.0)
	draw_rect(Rect2(Vector2(-36, -50) + sh, Vector2(72, 7)), MapData.shadow_color(0.3))
	# hounds: diagonal braces from the front axle to the tongue
	for sx in [-1.0, 1.0]:
		draw_line(Vector2(sx * 16.0, 58), Vector2(0, 30), dark, 4.0)
		draw_line(Vector2(sx * 16.0, 58), Vector2(0, 30), wood, 2.5)
	# tongue
	draw_line(Vector2(0, 60), Vector2(0, -46), dark, 6.0)
	draw_line(Vector2(0, 60), Vector2(0, -46), wood, 4.0)
	draw_line(Vector2(-0.8, 58), Vector2(-0.8, -44), wood_hi, 1.2)
	# doubletree crossbar
	draw_rect(Rect2(-36, -50, 72, 7), wood)
	draw_rect(Rect2(-36, -50, 72, 7), dark, false, 1.5)
	draw_circle(Vector2(0, -46.5), 3.0, iron)  # pin through the tongue
	# singletrees, chained to the crossbar ends
	for sx in [-1.0, 1.0]:
		var cx: float = sx * 26.0  # sx comes from an untyped array, so the type is given explicitly
		draw_line(Vector2(cx, -50), Vector2(cx, -58), iron, 1.5)
		draw_rect(Rect2(cx - 14.0, -62, 28, 5), wood)
		draw_rect(Rect2(cx - 14.0, -62, 28, 5), dark, false, 1.2)
		for ex in [-14.0, 14.0]:  # trace hooks
			draw_circle(Vector2(cx + ex, -59.5), 2.0, iron)
	# neck yoke ring at the tip of the tongue
	draw_arc(Vector2(0, -46), 5.0, 0.0, TAU, 12, iron, 1.5)


## Driver's bench across the front of the bed, with a footboard.
func _draw_wagon_seat() -> void:
	draw_rect(Rect2(Vector2(-34, -10) + _u(Vector2(2, 3)), Vector2(68, 20)), MapData.shadow_color(0.28))
	draw_rect(Rect2(-34, -10, 68, 6), Color("4a3018"))  # footboard
	draw_rect(Rect2(-30, -4, 60, 12), Color("8f6338"))  # seat plank
	draw_line(Vector2(-30, 2), Vector2(30, 2), Color("5e4023"), 1.0)
	draw_rect(Rect2(-30, 7, 60, 3), Color("3a2614"))  # backrest rail
	draw_rect(Rect2(-30, -4, 60, 14), Color("1d1209"), false, 1.5)
	for sx in [-1.0, 1.0]:
		draw_circle(Vector2(sx * 27.0, 2), 1.4, Color("2b2b30"))  # iron brackets


## Travel trunk: domed wooden chest with iron bands and a brass lock.
func _draw_trunk() -> void:
	draw_rect(Rect2(Vector2(-16, -11) + _u(Vector2(3, 4)), Vector2(32, 22)), MapData.shadow_color(0.3))
	draw_rect(Rect2(-16, -11, 32, 22), Color("6a3f22"))
	draw_rect(Rect2(-16, -11, 32, 9), Color("84522c"))  # lit side of the domed lid
	for x in [-9.0, 9.0]:
		draw_rect(Rect2(x - 1.5, -11, 3, 22), Color("2f2f34"))  # iron straps
	draw_rect(Rect2(-16, -11, 32, 22), Color("1d1209"), false, 1.5)
	if opened:
		# Lid thrown back: dark empty inside, lid flipped up along the top edge.
		draw_rect(Rect2(-13, -8, 26, 17), Color("2a1a0c"))
		_draw_water_fill(Rect2(-13, -8, 26, 17))
		draw_rect(Rect2(-13, -8, 26, 17), Color("1a1008"), false, 1.5)
		draw_rect(Rect2(-16, -19, 32, 8), Color("84522c"))
		draw_rect(Rect2(-16, -19, 32, 8), Color("1d1209"), false, 1.5)
		return
	draw_rect(Rect2(-2.5, 7, 5, 4), Color("d4b050"))  # lock plate
	draw_circle(Vector2(0, 9), 0.9, Color("3a2a10"))


## Rolled-out blanket with a pillow; colour picked from the seed.
func _draw_bedroll(rng: RandomNumberGenerator) -> void:
	var cols := [Color("7a3a30"), Color("3d5f7a"), Color("5c6b3a"), Color("8a6a3a")]
	var c: Color = cols[rng.randi() % cols.size()]
	draw_rect(Rect2(Vector2(-14, -26) + _u(Vector2(2, 3)), Vector2(28, 52)), MapData.shadow_color(0.22))
	draw_rect(Rect2(-14, -26, 28, 52), c)
	draw_rect(Rect2(-14, -6, 28, 32), c.darkened(0.15))  # folded-back top blanket
	for y in [-2.0, 10.0, 22.0]:
		draw_line(Vector2(-14, y), Vector2(14, y), c.lightened(0.2), 1.0)  # woven stripes
	draw_rect(Rect2(-14, -26, 28, 52), c.darkened(0.5), false, 1.2)
	draw_rect(Rect2(-10, -23, 20, 12), Color("e4dcc8"))  # pillow
	draw_rect(Rect2(-10, -23, 20, 12), Color("8a8270"), false, 1.0)


## Two or three tied burlap grain sacks.
func _draw_sacks(rng: RandomNumberGenerator) -> void:
	var n := 2 + rng.randi() % 2
	for i in n:
		var p := Vector2(-7.0 + i * 8.0, rng.randf_range(-5.0, 5.0))
		var r := rng.randf_range(8.0, 10.0)
		draw_circle(p + _u(Vector2(2, 3)), r, MapData.shadow_color(0.25))
		draw_circle(p, r, Color("b39a6a"))
		draw_circle(p + _u(Vector2(-2, -2)), r * 0.55, Color("c9b282"))
		draw_arc(p, r, 0.0, TAU, 16, Color("6e5a36"), 1.2)
		draw_circle(p, 2.2, Color("7a6440"))  # tied neck
		draw_line(p + Vector2(-2.5, -2), p + Vector2(2.5, 2), Color("4a3a20"), 1.0)


## Small hanging lantern; the light itself comes from the prop's light settings.
func _draw_wagon_lantern() -> void:
	draw_circle(Vector2.ZERO, 22.0, Color(1.0, 0.8, 0.45, 0.07))
	draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.8, 0.45, 0.15))
	draw_circle(_u(Vector2(2, 3)), 6.0, MapData.shadow_color(0.3))
	draw_rect(Rect2(-5, -5, 10, 10), Color("2b2b30"))
	draw_rect(Rect2(-3.5, -3.5, 7, 7), Color("ffd27a"))
	draw_circle(Vector2.ZERO, 1.8, Color("fff4c8"))
	draw_line(Vector2(-5, 0), Vector2(5, 0), Color("2b2b30"), 1.0)
	draw_line(Vector2(0, -5), Vector2(0, 5), Color("2b2b30"), 1.0)
	draw_arc(Vector2(0, -6), 3.0, PI, TAU, 8, Color("2b2b30"), 1.2)  # bail handle


# ---------------------------------------------------------------- swamp theme

func _draw_dead_tree(rng: RandomNumberGenerator) -> void:
	draw_colored_polygon(_blob(40.0, 14, 0.15, rng, _u(Vector2(8, 10))), MapData.shadow_color(0.22))
	var n := 7
	var off := rng.randf() * TAU
	for i in n:
		var a := off + TAU * float(i) / float(n) + rng.randf_range(-0.2, 0.2)
		var dir := Vector2(cos(a), sin(a))
		var len := rng.randf_range(34.0, 48.0)
		var mid := dir * len * 0.55
		var tip := mid + dir.rotated(rng.randf_range(-0.6, 0.6)) * len * 0.45
		draw_line(Vector2.ZERO, mid, Color("3a3028"), 5.0)
		draw_line(mid, tip, Color("3a3028"), 3.0)
		draw_line(mid, mid + dir.rotated(0.8) * len * 0.3, Color("3a3028"), 2.0)
		draw_line(mid, mid + dir.rotated(-0.8) * len * 0.3, Color("3a3028"), 2.0)
		draw_line(Vector2.ZERO, mid, Color("5a4a3c"), 2.0)
		# hanging moss
		draw_circle(tip, 3.0, Color(0.35, 0.5, 0.25, 0.7))
	draw_circle(Vector2.ZERO, 8.0, Color("2e251d"))
	draw_circle(_u(Vector2(-2, -2)), 5.0, Color("4a3c30"))


func _draw_reeds(rng: RandomNumberGenerator) -> void:
	for i in 22:
		var a := rng.randf() * TAU
		var base := Vector2(cos(a), sin(a)) * rng.randf_range(0.0, 14.0)
		var tip := base + Vector2(cos(a), sin(a)) * rng.randf_range(8.0, 16.0) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		draw_line(base, tip, Color("4f6a2a").lerp(Color("8a9a4a"), rng.randf()), 1.8)
		if i % 4 == 0:
			draw_circle(tip, 2.4, Color("6a4a2a"))


func _draw_lilypad(rng: RandomNumberGenerator) -> void:
	for i in 3:
		var c := Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
		var r := rng.randf_range(8.0, 11.0)
		var gap := rng.randf() * TAU
		var pts := PackedVector2Array([c])
		for k in 15:
			var a := gap + 0.5 + (TAU - 1.0) * float(k) / 14.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color("3f7a32").lerp(Color("5a9a3e"), rng.randf()))
		draw_line(c, c + Vector2(cos(gap + 3.0), sin(gap + 3.0)) * r * 0.7, Color("2a5a22"), 1.0)
		if i == 0:
			draw_circle(c, 3.0, Color("f4a8c0"))
			draw_circle(c, 1.4, Color("fff0a8"))


func _draw_mushroom(rng: RandomNumberGenerator) -> void:
	for i in 3:
		var c := Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
		var r := rng.randf_range(4.5, 7.0)
		draw_circle(c + _u(Vector2(1.5, 2)), r, MapData.shadow_color(0.3))
		draw_circle(c, r, Color("a8342e") if i != 1 else Color("c8a46a"))
		draw_circle(c, r * 0.55, Color("d4524a") if i != 1 else Color("e6c88a"))
		draw_circle(c + Vector2(-r * 0.2, -r * 0.2), r * 0.18, Color("f4f0e0"))
