class_name Player
extends CharacterBody2D
## Simple top-down test character with a lantern and a follow camera.

const SPEED := 160.0
const Loadout := preload("res://scripts/loadout.gd")
const HandCards := preload("res://scripts/hand_cards.gd")
const SHOW_HANDS_FEET := false  # set to true to draw the hands, arms, fists and boots again
const SHOW_SHOULDERS := false  # set to true to draw the shoulders / torso (shirt and vest) again
const STEP_LENGTH := 22.0  # pixels walked per step
const STEP_PULSE := 0.025  # how much bigger the character gets mid-step (0.025 = 2.5%)
const PRINT_LIFE := 6.0  # seconds a footprint takes to fade away
const MAX_PRINTS := 60
const TURN_RATE := 14.0  # how fast the character turns to face its direction (higher = snappier)
const HeadArt := preload("res://scripts/head_art.gd")
const ShotPreview := preload("res://scripts/shot_preview.gd")

## Selected head (hat or hair, see head_art.gd); static so the choice is kept between play-test sessions.
## Starts on the first hair style (no hat): head_art.gd lists the hats first, then the hair.
static var head_style: int = HeadArt.HatArt.STYLES.size()
## Selected weapon key ("none" or a key in Weapons.RANGED); static like head_style.
static var weapon := "none"
## Auto reload (on-screen toggle): reload a partly used magazine once you stop firing. Static like weapon.
static var auto_reload := false
const AUTO_RELOAD_DELAY := 1.0  # seconds after the last shot
var _since_shot := 0.0

const MAX_HP := 100

signal health_changed(hp: int, max_hp: int)

## Morale: drops when the player runs away from a fight (the "Run away" spot). Restored on respawn.
const MAX_MORALE := 100
const FLEE_MORALE_LOSS := 15
signal morale_changed(morale: int, max_morale: int)
var morale := MAX_MORALE
## Knocked out (0 hp) and sent back to the spawn point.
signal respawned

# ---- turn-based combat (driven by combat.gd) ----
const COMBAT_MOVE := 200.0  # pixels the player may walk in one combat turn
## A turn-based fight is on: outside your turn you can't move or act.
var turn_mode := false
var my_turn := false
var move_left := 0.0        # movement left this turn (pixels)
var action_left := false    # the turn's one action (a shot or a reload) is still available
var card_played := false    # a combat card has been played this turn (one per turn)
var aimed := false          # Aimed Shot card: the next shot this turn is aimed
const AIM_DAMAGE := 1.5     # Aimed Shot: damage multiplier
const AIM_RANGE := 1.5      # Aimed Shot: range multiplier
signal gold_changed(total: int, added: int)

## Coins in the player's purse (gold drops are picked up by walking over them). Kept on respawn.
var gold := 0
## Keys carried; each opens one locked crate or chest.
var keys := 0


## Takes loot straight into the player's hands (used when opening a crate or chest).
## Gold goes to the purse, keys to the key ring, guns to the weapon wheel. Potions, food, gems
## have no inventory yet, so they are simply taken.
func collect_loot(kind: String) -> void:
	match kind:
		"gold":
			add_gold(randi_range(5, 25))
		"key":
			keys += 1
		"none":
			pass
		_:
			if Weapons.is_ranged(kind) and not owned_weapons.has(kind):
				owned_weapons.append(kind)


## Sent when a gun is picked up off the ground (game_view shows the "new weapon" popup).
signal weapon_picked(key: String)


## Walking over a weapon prop: the gun joins the weapon wheel and is taken in hand.
func pick_up_weapon(key: String) -> void:
	if not Weapons.is_ranged(key):
		return
	if not owned_weapons.has(key):
		owned_weapons.append(key)
	fire_held = false
	set_weapon(key)
	weapon_picked.emit(key)


func add_key() -> void:
	keys += 1
	notice.emit("Picked up a key")


func add_gold(n: int) -> void:
	if n <= 0:
		return
	gold += n
	gold_changed.emit(gold, n)


## Experience points, earned by killing NPCs and animals.
signal xp_changed(total: int, added: int)
var xp := 0
## Weapon upgrades bought with XP (see weapon_upgrades.gd): weapon key -> {stat -> level}.
var upgrades := {}


func add_xp(n: int) -> void:
	if n <= 0:
		return
	xp += n
	xp_earned += n
	xp_changed.emit(xp, n)
	_deal_cards()


# ---------------------------------------------------------------- hand of cards (see hand_cards.gd)

signal hand_changed
signal card_drawn(kind: String)
## Cards held, one entry per card (kinds from HandCards.CARDS; duplicates allowed).
var hand: Array = []
## All XP ever earned. Spending XP on weapon upgrades does not lower it, so cards are never lost or re-dealt.
var xp_earned := 0
var cards_dealt := 0
## Upgrade cards played so far: weapon key -> count. They last for the whole game.
var damage_cards := {}
var mag_cards := {}
## First Strike played: every fight on this map starts with the player first, and +1 action on the first turn.
var first_strike := false
## Fan the Hammer played: this turn's shot empties the revolver.
var fan_hammer := false
const FAN_INTERVAL := 0.09  # seconds between the rounds of a fanned volley


## Magazine size of `key`, including Upgrade Shotgun cards.
func mag(key: String) -> int:
	if not Weapons.is_ranged(key):
		return 0
	return Weapons.mag_size(key) + int(mag_cards.get(key, 0)) * HandCards.SHOTGUN_MAG_STEP


## Damage multiplier from Upgrade Revolver cards (used by Projectile.fire).
func card_damage_mul(key: String) -> float:
	return 1.0 + int(damage_cards.get(key, 0)) * HandCards.REVOLVER_DAMAGE_STEP


## Deals one random card for every XP_PER_CARD xp earned that has not been paid out yet.
@warning_ignore("integer_division")
func _deal_cards() -> void:
	while cards_dealt < xp_earned / HandCards.XP_PER_CARD:
		cards_dealt += 1
		var kind := HandCards.random_kind()
		hand.append(kind)
		card_drawn.emit(kind)
	hand_changed.emit()


## Whether the card `kind` in the hand could be played right now (used to grey out cards).
func can_play_hand_card(kind: String) -> bool:
	if hp <= 0 or not hand.has(kind):
		return false
	match kind:
		"revolver_up", "shotgun_up":
			return true
		"first_strike":
			return not turn_mode and not first_strike
		"fan_hammer":
			return turn_mode and my_turn and action_left and not _combat_run and not fan_hammer \
					and weapon == "pistol" and ammo() >= 1
	return false


## Plays a card from the hand (the card is used up). Returns false when it can't be played now.
func play_hand_card(kind: String) -> bool:
	if not can_play_hand_card(kind):
		return false
	match kind:
		"revolver_up":
			damage_cards["pistol"] = int(damage_cards.get("pistol", 0)) + 1
		"shotgun_up":
			mag_cards["shotgun"] = int(mag_cards.get("shotgun", 0)) + 1
			if _ammo.has("shotgun"):
				_ammo["shotgun"] = int(_ammo["shotgun"]) + HandCards.SHOTGUN_MAG_STEP  # the extra slot comes loaded
		"first_strike":
			first_strike = true
		"fan_hammer":
			fan_hammer = true
	hand.erase(kind)  # removes one copy
	hand_changed.emit()
	queue_redraw()
	return true


var map_size := Vector2(2048, 1728)
var facing := Vector2.DOWN
var hp := MAX_HP
var _spawn := Vector2.ZERO
var _cooldown := 0.0
var _hurt_flash := 0.0
var _step_phase := 0.0
var _prints: Array = []  # footprints: {pos, ang, age}
var _print_layer: Node2D
var _print_dist := 0.0
var _print_left := true
var _step_amount := 0.0  # 0 = standing, 1 = walking (eases in/out so stopping isn't a snap)
var _ammo := {}  # weapon key -> shots left; missing = full magazine
var _reload_total := 1.0  # length of the reload in progress (for the progress bar)
var _reload_left := 0.0  # seconds until the reload finishes (0 = not reloading)
## Locked-on NPC (click it or press Tab). Space / F fire at it. Cleared when it dies or gets too far away.
var target: Node2D = null
var _reticle: Node2D
## Set while the on-screen Shoot button is held: fires at the target like holding Space / F.
var fire_held := false
## Push of the on-screen joystick (length 0..1), set by game_view. Walks like the arrow keys.
var joystick := Vector2.ZERO
## Selected door or window (click it). The player walks up to it; E / K then act on it.
var interact: Node2D = null
var _interact_marker: Node2D
var _interact_spot := Vector2.ZERO
var _interact_arrived := false

const INTERACT_REACH := 30.0  # close enough to the standing spot to count as arrived

const TARGET_RANGE := 900.0  # Tab only picks barrels / crates this close; one further away is dropped
## NPCs can only be targeted (click or Tab) within 6 tiles; an NPC target further away is dropped.
const NPC_TARGET_RANGE := 6 * Weapons.TILE
## NPC clicked from too far away: walking toward it, targeted once within NPC_TARGET_RANGE.
var _pending_target: Node2D = null
## Double-clicked target while fists are selected: walking until within punch reach.
var _punch_chase: Node2D = null
## Short on-screen hint for the player (shown by game_view).
signal notice(text: String)
const CLICK_RADIUS := 32.0  # how close (px, one tile) a click must land to an NPC to target it


func _ready() -> void:
	# Top-down: no floor/gravity. The default "grounded" mode treats walls and props as slopes and
	# snaps to a floor, which makes the character hop and bounce along obstacles.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	weapon = "pistol"  # every play-test starts with the revolver in hand
	Loadout.apply_to(self)  # gold left over and weapons bought on the purchase screen
	collision_mask = 1 | 2 | Projectile.LOW_MASK  # world + water + low props
	add_to_group("combatants")
	add_to_group("player")
	_spawn = position
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	cs.shape = circle
	add_child(cs)

	add_child(MapRenderer.character_occluder())  # casts shadows from lights that have "NPC Shadow" on

	var lantern := PointLight2D.new()
	lantern.texture = MapRenderer.light_texture()
	lantern.texture_scale = 2.6
	lantern.color = Color(1.0, 0.86, 0.62)
	lantern.energy = 0.9
	lantern.shadow_enabled = true
	lantern.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	add_child(lantern)

	var cam := Camera2D.new()
	_setup_revolver()
	# The revolver is a sprite child, which draws over this node's own _draw(). The hat gets its own
	# child added after it, so the hat always sits on top of the weapon.
	_hat_layer = Node2D.new()
	_hat_layer.draw.connect(func() -> void:
		var bs := step_scale()
		HeadArt.draw(_hat_layer, head_style, Vector2.ZERO, facing.angle(), bs)
		_hat_layer.draw_set_transform_matrix(Transform2D.IDENTITY))
	add_child(_hat_layer)
	_cam = cam
	cam.zoom = Vector2(NORMAL_ZOOM, NORMAL_ZOOM)
	cam.position_smoothing_enabled = true
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(map_size.x)
	cam.limit_bottom = int(map_size.y)
	add_child(cam)
	cam.make_current()

	_print_layer = Node2D.new()
	_print_layer.top_level = true
	# top_level nodes ignore show_behind_parent (they draw on top), so order them by z instead:
	# above the terrain (z -4), below props tucked behind walls (-1) and the player (0).
	_print_layer.z_index = -3
	_print_layer.draw.connect(_draw_prints)
	add_child(_print_layer)

	_marker = Node2D.new()
	_marker.top_level = true
	_marker.z_index = 20
	_marker.visible = false
	_marker.draw.connect(_draw_marker)
	add_child(_marker)

	_reticle = Node2D.new()
	_reticle.top_level = true
	_reticle.z_index = 21
	_reticle.visible = false
	_reticle.draw.connect(_draw_reticle)
	add_child(_reticle)

	var preview := ShotPreview.new()  # hover an NPC: aim cone, cover and damage preview
	preview.player = self
	add_child(preview)

	_interact_marker = Node2D.new()
	_interact_marker.top_level = true
	_interact_marker.z_index = 21
	_interact_marker.visible = false
	_interact_marker.draw.connect(_draw_interact_marker)
	add_child(_interact_marker)

	_cover_layer = Node2D.new()  # highlighted cover spots while it is your turn
	_cover_layer.top_level = true
	_cover_layer.z_index = 19
	_cover_layer.visible = false
	_cover_layer.draw.connect(_draw_cover_layer)
	add_child(_cover_layer)
	_build_grid()


## Quickly moves the player to `dest` (used to step through a door that was just kicked in),
## ignoring input and the combat movement allowance.
func slide_to(dest: Vector2, time := 0.45) -> void:
	_clear_path()
	_slide_dest = dest
	_slide_speed = maxf(position.distance_to(dest) / time, 1.0)
	_sliding = true
	velocity = Vector2.ZERO


var _sliding := false
var _slide_dest := Vector2.ZERO
var _slide_speed := 0.0


func _physics_process(delta: float) -> void:
	if _sliding:
		_cooldown = maxf(_cooldown - delta, 0.0)
		_tick_reload(delta)  # a reload keeps running while stepping through a door
		var to := _slide_dest - position
		if to.length() <= _slide_speed * delta:
			position = _slide_dest
			_sliding = false
		else:
			position += to.normalized() * _slide_speed * delta
			facing = to.normalized()
		_step_phase = fmod(_step_phase + _slide_speed * delta / STEP_LENGTH * PI, TAU)
		_step_amount = 1.0
		queue_redraw()
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_tick_reload(delta)
	_tick_rifle_eject(delta)
	_since_shot += delta
	if _punch_t > 0.0:
		_punch_t = maxf(_punch_t - delta, 0.0)
		queue_redraw()
	if _kick_t > 0.0:
		_kick_t = maxf(_kick_t - delta, 0.0)
		queue_redraw()
	if weapon_drawn and not turn_mode and not is_instance_valid(target) and _since_shot > HOLSTER_AFTER:
		holster()  # drawn by firing at nothing: put it away after a quiet spell
	# Out of ammo: reload by itself, except in a fight (there it costs the turn's action).
	if not turn_mode and Weapons.is_ranged(weapon) and ammo() <= 0 and not is_reloading():
		reload()
	if auto_reload and not turn_mode and _since_shot >= AUTO_RELOAD_DELAY and Weapons.is_ranged(weapon) and not is_reloading() and ammo() < mag(weapon):
		reload()
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		queue_redraw()
	_update_target()
	_update_pending_target()
	_update_punch_chase()
	_update_hold_move(delta)
	_update_interact()
	# Holding right mouse keeps firing at the cursor (at the weapon's fire rate).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and get_viewport().gui_get_hovered_control() == null:
		shoot_at(get_global_mouse_position())
	# Holding Space or F fires at the locked target, or straight ahead without one.
	elif Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_F) or fire_held:
		if is_instance_valid(target):
			shoot_at(target.global_position)
		else:
			shoot_at(global_position + facing * 100.0)
	var dir := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	var stick_push := 1.0
	if dir == Vector2.ZERO and joystick != Vector2.ZERO and not turn_mode:
		dir = joystick  # on-screen joystick (only when no key is held)
		stick_push = minf(joystick.length(), 1.0)  # a light push walks slower
	var speed := SPEED * (1.7 if Input.is_key_pressed(KEY_SHIFT) or _combat_run else 1.0) * stick_push
	if turn_mode:
		# Turn-based: no free walking. The only way to move is running to a highlighted spot.
		dir = Vector2.ZERO
		if not (my_turn and _combat_run) and not _path.is_empty():
			_clear_path()
	if dir != Vector2.ZERO:
		_clear_path()  # keyboard overrides click-to-move
	elif not _path.is_empty():
		var to_next := _path[0] - position
		if to_next.length() < 6.0:
			_path.remove_at(0)
			if _path.is_empty():
				_clear_path()
		else:
			dir = to_next
	velocity = dir.normalized() * speed
	if is_instance_valid(target) and target.global_position.distance_to(global_position) > 1.0:
		# Locked on: keep facing (and aiming) at the target while walking in any direction.
		var aim := (target.global_position - global_position).normalized()
		if facing.dot(aim) < -0.99:
			facing = facing.rotated(0.2)  # slerp has no defined path for an exact reversal
		var turned := facing.slerp(aim, minf(1.0, TURN_RATE * delta)).normalized()
		if not turned.is_equal_approx(facing):
			facing = turned
			queue_redraw()
	elif dir != Vector2.ZERO:
		# Turn toward the move direction over a few frames instead of snapping.
		var want := dir.normalized()
		if facing.dot(want) < -0.99:
			facing = facing.rotated(0.2)  # slerp has no defined path for an exact reversal
		facing = facing.slerp(want, minf(1.0, TURN_RATE * delta)).normalized()
		queue_redraw()
	var before := position
	move_and_slide()
	_keep_out_of_water(before)
	# Step pulse follows distance actually walked, so running steps faster and pushing
	# into a wall doesn't animate. Each half-turn of the phase is one step.
	var moved := position.distance_to(before)
	if turn_mode and my_turn and moved > 0.0:
		move_left = maxf(move_left - moved, 0.0)
		queue_redraw()  # the movement ring shrinks
	_step_phase = fmod(_step_phase + moved / STEP_LENGTH * PI, TAU)
	_step_amount = move_toward(_step_amount, 1.0 if moved > 0.2 else 0.0, delta * 6.0)
	if _step_amount > 0.0:
		queue_redraw()
	_update_prints(delta, moved)
	if not _path.is_empty():
		# Give up if blocked (no progress for half a second).
		if position.distance_to(before) < speed * delta * 0.25:
			_stuck += delta
			if _stuck > 0.5:
				_clear_path()
		else:
			_stuck = 0.0
	if _combat_run and _path.is_empty():
		_finish_run()
	if _cover_layer != null and (_cover_layer.visible or not _spots.is_empty()):
		_update_cover_layer()


# ---------------------------------------------------------------- footprints

## Leaves a print every step (alternating feet) and fades old ones out.
func _update_prints(delta: float, moved: float) -> void:
	if moved > 0.2:
		_print_dist += moved
		if _print_dist >= STEP_LENGTH:
			_print_dist = 0.0
			var side := 1.0 if _print_left else -1.0
			_print_left = not _print_left
			var dir := velocity.normalized() if velocity.length() > 1.0 else facing
			if _on_base_ground(global_position):  # floors, roads, rugs...: no footprints
				_prints.append({
					"pos": global_position + dir.orthogonal() * 4.0 * side + dir * 2.0,
					"ang": dir.angle(),
					"age": 0.0})
				if _prints.size() > MAX_PRINTS:
					_prints.pop_front()
	if _prints.is_empty():
		return
	for p in _prints:
		p["age"] += delta
	while not _prints.is_empty() and _prints[0]["age"] >= PRINT_LIFE:
		_prints.pop_front()
	_print_layer.queue_redraw()


## True when `p` is on the map's base ground: not inside any terrain polygon drawn over it.
## See-through overlays (moss, blood, shadow) don't count, so prints still show through them.
func _on_base_ground(p: Vector2) -> bool:
	for poly in MapData.working.get("polygons", []):
		var pts: PackedVector2Array = poly["points"]
		if pts.size() < 3:
			continue
		var def: Dictionary = MapData.TERRAIN.get(str(poly["type"]), {})
		if not def.is_empty() and (def["a"] as Color).a < 0.99:
			continue
		if Geometry2D.is_point_in_polygon(p, pts):
			return false
	return true


func _draw_prints() -> void:
	for p in _prints:
		var a := (1.0 - float(p["age"]) / PRINT_LIFE) * 0.35
		_print_layer.draw_set_transform(p["pos"], float(p["ang"]), Vector2.ONE)
		_print_layer.draw_circle(Vector2(0, 0), 2.6, Color(0.1, 0.07, 0.04, a))  # sole
		_print_layer.draw_circle(Vector2(3.2, 0), 1.8, Color(0.1, 0.07, 0.04, a))  # toe
	_print_layer.draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------- click to move

const CELL := 16.0

var _grid: AStarGrid2D
var _path: PackedVector2Array = PackedVector2Array()
var _stuck := 0.0
var _marker: Node2D
var _marker_pos := Vector2.ZERO


func _build_grid() -> void:
	# Wait for the map's static bodies to register with the physics server.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var cols := int(ceil(map_size.x / CELL))
	var rows := int(ceil(map_size.y / CELL))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, cols, rows)
	_grid.cell_size = Vector2(CELL, CELL)
	_grid.offset = Vector2(CELL, CELL) * 0.5
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	q.shape = shape
	q.exclude = [get_rid()]
	for y in rows:
		for x in cols:
			q.transform = Transform2D(0.0, Vector2(x + 0.5, y + 0.5) * CELL)
			if not space.intersect_shape(q, 1).is_empty() or _cell_in_water(Vector2i(x, y)):
				_grid.set_point_solid(Vector2i(x, y), true)


## Re-checks which path-finding cells inside `area` are blocked (call after a door opens or closes).
func refresh_nav(area: Rect2) -> void:
	if _grid == null:
		return
	# Let the physics server apply the door's collision change first.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 11.0
	q.shape = shape
	q.exclude = [get_rid()]
	var lo := _cell(area.position)
	var hi := _cell(area.end)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			q.transform = Transform2D(0.0, Vector2(x + 0.5, y + 0.5) * CELL)
			_grid.set_point_solid(Vector2i(x, y), not space.intersect_shape(q, 1).is_empty() or _cell_in_water(Vector2i(x, y)))


## Backstop for water collision: if this frame's move ended in blocked water, slide along one
## axis instead, or undo the move. Starting in water (e.g. a bad spawn) is left alone so the
## player can walk out.
func _keep_out_of_water(before: Vector2) -> void:
	if position == before or not _in_water(position) or _in_water(before):
		return
	var tries := [Vector2(position.x, before.y), Vector2(before.x, position.y)]
	for t in tries:
		if not _in_water(t):
			position = t
			return
	position = before


func _in_water(p: Vector2) -> bool:
	# 9px: a bit under the 10px body, so hugging the shore doesn't stick.
	for r in get_tree().get_nodes_in_group("map_renderer"):
		if r.has_method("circle_in_water") and r.circle_in_water(p, 9.0):
			return true
	return false


## True when the cell's centre (with the body radius) touches water nobody can walk on.
## Checks the renderer's water polygons directly, so it works even if a collision shape failed.
func _cell_in_water(c: Vector2i) -> bool:
	for r in get_tree().get_nodes_in_group("map_renderer"):
		if r.has_method("circle_in_water") and r.circle_in_water((Vector2(c) + Vector2(0.5, 0.5)) * CELL, 11.0):
			return true
	return false


func _cell(p: Vector2) -> Vector2i:
	var c := Vector2i((p / CELL).floor())
	return Vector2i(clampi(c.x, 0, _grid.region.size.x - 1), clampi(c.y, 0, _grid.region.size.y - 1))


## Nearest walkable cell to `c` (searching outward), or (-1,-1) if none is close.
func _nearest_free(c: Vector2i) -> Vector2i:
	for r in 8:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if _grid.is_in_boundsv(n) and not _grid.is_point_solid(n):
					return n
	return Vector2i(-1, -1)


func _unhandled_input(event: InputEvent) -> void:
	if _grid == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Clicking an NPC targets it (clicking the current target again clears it); elsewhere = walk there.
		var mp := get_global_mouse_position()
		_pending_target = null
		_punch_chase = null
		if turn_mode:
			# In a fight you only move by clicking one of the highlighted spots.
			var si := _spot_at(mp) if my_turn and not _combat_run else -1
			if si >= 0:
				_run_to_spot(si)
				get_viewport().set_input_as_handled()
				return
		var npc := _npc_at(mp)
		if event.double_click and Weapons.is_ranged(weapon):
			# Double-click with a gun: shoot at the NPC / barrel / crate clicked, else at the spot.
			var mark: Node2D = npc if npc != null else _container_at(mp)
			var aim_at := mp
			if mark != null:
				if mark != target:
					set_target(mark)
				aim_at = mark.global_position
			_hold_move = false
			if not turn_mode:
				_clear_path()  # stop walking so the shot is not cancelled by the first click's move
			shoot_at(aim_at)
			get_viewport().set_input_as_handled()
			return
		if event.double_click and weapon == "none":
			# Punch selected: double-clicking a target walks right up to it.
			var victim: Node2D = npc if npc != null else _container_at(mp)
			if victim != null:
				if victim != target:
					set_target(victim)
				set_interact(null)
				if not in_punch_reach(victim):
					_punch_chase = victim
					_move_to(victim.global_position)
				get_viewport().set_input_as_handled()
				return
		if npc != null and npc != target and global_position.distance_to(npc.global_position) > NPC_TARGET_RANGE:
			# Too far to target yet: walk toward the NPC and lock on once within 6 tiles.
			if turn_mode:
				notice.emit("Too far to target")
				get_viewport().set_input_as_handled()
				return
			_pending_target = npc
			set_interact(null)
			_move_to(npc.global_position)
			notice.emit("Too far to target - moving closer")
			get_viewport().set_input_as_handled()
			return
		if npc == null:
			npc = _container_at(mp)  # barrels and crates are targets too, not walk-to selections
		var opening: Node2D = _opening_at(mp) if npc == null else null
		if npc != null:
			set_target(null if npc == target else npc)
		elif opening != null:
			# Doors / windows use their own selection (separate from the NPC target): walk up to it.
			if opening == interact:
				set_interact(null)
			else:
				set_interact(opening)
		elif not turn_mode:
			set_interact(null)  # clicking empty ground only clears the door / window selection (no click-to-move)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				reload()
			KEY_TAB:
				cycle_target()
			KEY_X:
				set_target(null)
			_:
				return
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- combat

## Weapons the player carries. Fists ("none") only at the start of every play-test.
var owned_weapons: Array = ["pistol"]


func has_weapon(key: String) -> bool:
	return owned_weapons.has(key)


func set_weapon(key: String) -> void:
	if not has_weapon(key):
		return
	weapon = key if (key == "none" or Weapons.is_ranged(key)) else "none"
	_reload_left = 0.0  # switching weapons cancels a reload in progress
	queue_redraw()


## Shots left in the current weapon's magazine (each weapon keeps its own count).
func ammo() -> int:
	return int(_ammo.get(weapon, mag(weapon)))


func is_reloading() -> bool:
	return _reload_left > 0.0


## 0..1 progress of the reload in progress (1 when not reloading).
func reload_progress() -> float:
	if not is_reloading() or not Weapons.is_ranged(weapon):
		return 1.0
	return 1.0 - _reload_left / maxf(_reload_total, 0.001)


## Starts refilling the magazine (R, or automatically when it runs dry).
func reload() -> void:
	if not Weapons.is_ranged(weapon) or is_reloading() or ammo() >= mag(weapon):
		return
	if turn_mode and not (my_turn and action_left):
		return  # turn-based: reloading is your turn's action
	var spent := _casings_left_to_eject(mag(weapon) - ammo())
	if turn_mode:
		_spend_action()
		_clear_path()
		_ammo[weapon] = mag(weapon)  # takes the action instead of real time
	else:
		# Only the missing rounds are loaded, so a partly full magazine reloads proportionally faster.
		var missing := mag(weapon) - ammo()
		_reload_total = float(Weapons.RANGED[weapon]["reload"]) * WeaponUpgrades.reload_mul(upgrades, weapon) * float(missing) / float(mag(weapon))
		_reload_left = _reload_total
	# Throw out one spent casing per round being reloaded, from the gun (part way along it).
	if weapon != "flintlock":  # a flintlock has no brass: its wad leaves with the shot
		_eject_casings(spent)


func _eject_casings(count: int, gun_weapon: String = "") -> void:
	var key := weapon if gun_weapon == "" else gun_weapon
	var gun := Weapons.muzzle_offset(key, facing) * 0.55
	if gun != Vector2.ZERO:
		gun -= facing * _gun_pull  # the gun is drawn back for a close target
	if key == "rifle" and gun != Vector2.ZERO:
		gun -= facing * RIFLE_EJECT_BACK  # a little further back along the gun, towards the stock
		gun += Vector2(-facing.y, facing.x) * RIFLE_EJECT_SIDE  # ejection port is on the gun's right
	if gun == Vector2.ZERO:
		gun = facing * 12.0 + Vector2(-facing.y, facing.x) * 6.0
	ShellCasings.spawn(get_tree().current_scene, global_position + gun, facing, count,
			"shell" if key == "shotgun" else "brass")


## Rifle casings are thrown out between shots (halfway through the delay), so a reload only
## has to eject the ones not already out.
const RIFLE_EJECT_AT := 0.5
const RIFLE_EJECT_BACK := 4.0   # px the ejection point sits back along the gun (towards the stock)
const RIFLE_EJECT_SIDE := 8.0   # px to the right of the barrel line that casings come out
var _rifle_eject_timer := 0.0   # > 0 while a casing is waiting to be ejected
var _rifle_ejected := 0         # casings already thrown out since the last reload


func _casings_left_to_eject(spent: int) -> int:
	if weapon != "rifle":
		return spent
	var pending := 1 if _rifle_eject_timer > 0.0 else 0
	var left := maxi(spent - _rifle_ejected - pending, 0)
	_rifle_ejected = 0
	return left


func _tick_rifle_eject(delta: float) -> void:
	if _rifle_eject_timer <= 0.0:
		return
	_rifle_eject_timer -= delta
	if _rifle_eject_timer <= 0.0:
		_rifle_eject_timer = 0.0
		_rifle_ejected += 1
		_eject_casings(1, "rifle")


func _tick_reload(delta: float) -> void:
	if _reload_left <= 0.0:
		return
	_reload_left -= delta
	if _reload_left <= 0.0:
		_reload_left = 0.0
		_ammo[weapon] = mag(weapon)


## False when a wall sits between the body and the muzzle (gun poking through a wall);
## the shot then starts from the body so it can't pass through.
func _muzzle_clear(muzzle: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(global_position, muzzle, Projectile.WORLD_MASK, [get_rid()])
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


## Close quarters: px the held gun is drawn back along the aim so its barrel stops short of an
## NPC / animal standing right in front of it (eased toward gun_pull_for() each frame).
var _gun_pull := 0.0
const GUN_PULL_SPEED := 160.0  # px/s the gun slides back / forward


## How far the gun must come back (along `dir`) so the muzzle stays just in front of the nearest
## body in the barrel's line, instead of poking over or past it. 0 when nothing is that close.
## The muzzle ends at most 8 px short of the body's centre, so a shot from it still hits.
func gun_pull_for(dir: Vector2) -> float:
	if not weapon_drawn or not Weapons.is_ranged(weapon) or dir.length() < 0.5:
		return 0.0
	dir = dir.normalized()
	var off := Weapons.muzzle_offset(weapon, dir)
	if off == Vector2.ZERO and weapon != "pistol":
		off = dir * (Weapons.length(weapon) + 2.0)  # line-art gun: tip is this far out
	var reach := off.dot(dir)
	if reach <= 4.0:
		return 0.0
	var barrel_side := off - dir * reach  # the barrel runs this far beside the body centre
	var pull := 0.0
	for n in get_tree().get_nodes_in_group("combatants"):
		if n == self or not (n is Node2D) or (n as Node).is_queued_for_deletion() or int(n.get("hp")) <= 0:
			continue
		var r: float = float(n.call("body_radius")) if n.has_method("body_radius") else 11.0
		var to := (n as Node2D).global_position - global_position - barrel_side
		var along := to.dot(dir)
		if along <= 0.0 or absf(to.cross(dir)) > r + 4.0:
			continue  # behind the shooter, or not in line with the barrel
		pull = maxf(pull, reach - (along - minf(r, Projectile.HIT_RADIUS - 2.0)))
	pull = maxf(pull, _gun_pull_for_blockers(off, barrel_side, reach))
	return clampf(pull, 0.0, reach - 4.0)


const GUN_WALL_MARGIN := 3.0  # px the gun's tip stays clear of a wall or blocking prop


## How far the gun must come back so it doesn't poke into a wall or a prop that blocks walking
## (solid props, low cover like crates and barrels). Looks along the line from the body to the
## muzzle, and along the barrel itself, since the gun is held to one side of the body.
func _gun_pull_for_blockers(off: Vector2, barrel_side: Vector2, reach: float) -> float:
	var space := get_world_2d().direct_space_state
	var mask := Projectile.WORLD_MASK | Projectile.LOW_MASK
	var tip := global_position + off
	var best := 0.0
	# [from, fraction of the segment that is gun] for the two lines.
	for from in [global_position, global_position + barrel_side]:
		var seg: Vector2 = tip - from
		if seg.length() < 1.0:
			continue
		var skip: Array[RID] = [get_rid()]
		var q := PhysicsRayQueryParameters2D.create(from, tip, mask, skip)
		var hit := space.intersect_ray(q)
		while not hit.is_empty() and (hit["collider"] as Object).has_meta("fence"):
			skip.append(hit["rid"])  # the gun reaches over fences
			q.exclude = skip
			hit = space.intersect_ray(q)
		if hit.is_empty():
			continue
		# Fraction of the way to the tip where it hits; the gun has to give back the rest.
		var f: float = from.distance_to(hit["position"]) / seg.length()
		best = maxf(best, reach * (1.0 - f) + GUN_WALL_MARGIN)
	return best


## The gun's muzzle (world position) when aiming along `dir`, drawn back for close targets.
func _muzzle_at(dir: Vector2) -> Vector2:
	var off := Weapons.muzzle_offset(weapon, dir)
	if off == Vector2.ZERO:
		return global_position
	return global_position + off - dir.normalized() * gun_pull_for(dir)


## Where a shot aimed at `at` leaves from: the gun's muzzle, or the body when a wall is in the way
## (same rule as shoot_at). Used by the shot preview.
func shot_origin(at: Vector2) -> Vector2:
	var dir := (at - global_position).normalized()
	var muzzle := _muzzle_at(dir)
	if muzzle != global_position and _muzzle_clear(muzzle):
		return muzzle
	return global_position


## Fires the selected weapon toward `target` if it is ranged, loaded and off cooldown.
func shoot_at(target: Vector2) -> void:
	if weapon == "none":
		punch_at(target)  # bare hands: the attack is a punch
		return
	if not Weapons.is_ranged(weapon) or _cooldown > 0.0 or hp <= 0 or is_reloading():
		return
	if turn_mode and not (my_turn and action_left):
		return  # turn-based: one shot per turn, on your own turn
	if wall_cover:
		notice.emit("Can't shoot from behind the wall - move out first")
		return
	if not weapon_drawn:
		draw_weapon()  # first pull it out; the shot comes after DRAW_TIME
		return
	if ammo() <= 0:
		ClickText.spawn(self)  # empty gun: the hammer just clicks
		if not turn_mode:
			reload()  # in a fight reloading costs the turn's action, so it is never automatic
		return
	if turn_mode:
		_spend_action()
		_clear_path()
	var dir := target - global_position
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	facing = dir
	_cooldown = float(Weapons.RANGED[weapon]["cooldown"]) * WeaponUpgrades.delay_mul(upgrades, weapon)
	_since_shot = 0.0
	_ammo[weapon] = ammo() - 1
	if fan_hammer and weapon == "pistol":
		# Fan the Hammer card: the rest of the cylinder follows the first round, all in this one action.
		fan_hammer = false
		var volley := ammo()
		_ammo[weapon] = 0
		_cooldown += volley * FAN_INTERVAL
		var fan_weapon := weapon
		for i in range(1, volley + 1):
			get_tree().create_timer(i * FAN_INTERVAL).timeout.connect(func() -> void:
				if is_inside_tree() and hp > 0 and weapon == fan_weapon:
					var d := target - global_position
					if d.length() >= 1.0:
						facing = d.normalized()
						_release_shot(target, facing))
	if weapon == "rifle":
		_rifle_eject_timer = float(Weapons.RANGED[weapon]["cooldown"]) * RIFLE_EJECT_AT
	if weapon == "flintlock":
		# Flintlock: the pan flashes and puffs smoke by the stock, then the main shot follows.
		var right := Vector2(-dir.y, dir.x)
		MuzzleFlash.spawn_lock(get_tree().current_scene, global_position + Weapons.lock_offset(weapon, dir), right)
		var fired_with := weapon
		get_tree().create_timer(Weapons.FLINTLOCK_DELAY).timeout.connect(func() -> void:
			if is_inside_tree() and hp > 0 and weapon == fired_with:
				_release_shot(target, (target - global_position).normalized()))
		queue_redraw()
		return
	_release_shot(target, dir)


## Sends the shot out of the muzzle (after any weapon-specific lead-in) and handles what follows it.
const KICK_TIME := 0.22   # seconds the shotgun / flintlock recoil animation lasts
const KICK_DIST := 6.0    # px the gun jerks back at the peak of the kick
var _kick_t := 0.0        # > 0 while the gun is kicking back


## How far (px) the held gun is pushed back right now: a sharp jerk back, then easing forward.
func _kick_amount() -> float:
	if _kick_t <= 0.0:
		return 0.0
	var k := 1.0 - _kick_t / KICK_TIME  # 0..1 through the animation
	return KICK_DIST * (k / 0.2 if k < 0.2 else 1.0 - (k - 0.2) / 0.8)


func _release_shot(target: Vector2, dir: Vector2) -> void:
	if dir.length() < 0.5:
		return
	if weapon == "shotgun" or weapon == "flintlock":
		_kick_t = KICK_TIME
	# Shots leave from the gun's muzzle when the weapon has an in-hand image (Projectile.fire adds 14px
	# along `dir`, so that is subtracted here). Re-aim from the muzzle so the shot still meets the target.
	var from := global_position
	var muzzle := _muzzle_at(dir)  # drawn back when an NPC / animal is right in front of the gun
	if muzzle != global_position and _muzzle_clear(muzzle):
		var aim := target - muzzle
		if aim.length() > 20.0:
			dir = aim.normalized()
		from = muzzle - dir * 14.0
	if aimed:
		# Aimed Shot card: dead straight, harder hitting and reaches further.
		Projectile.fire(get_tree().current_scene, weapon, from, dir, self, 0.0, AIM_DAMAGE, AIM_RANGE)
		aimed = false
	else:
		# The farther the target, the more the shot can stray.
		var spread := Weapons.spread_mul_at(weapon, global_position.distance_to(target))
		Projectile.fire(get_tree().current_scene, weapon, from, dir, self, spread)
	MuzzleFlash.spawn(get_tree().current_scene, from + dir * 14.0, dir)  # fire + smoke at the barrel tip
	if weapon == "flintlock":
		ShellCasings.spawn(get_tree().current_scene, from + dir * 14.0, dir, 1, "wad")  # burnt powder wad
	_alert_shot_at(target)
	var shot_at: NpcNode = self.target as NpcNode if is_instance_valid(self.target) else null  # a shot at an NPC alerts it, even when it misses
	if shot_at != null:
		shot_at.alerted = true
	if ammo() <= 0 and not turn_mode:
		reload()  # in a turn-based fight reloading takes a later turn's action instead
	queue_redraw()


## The NPC being shot at turns to face the player, hit or miss: the locked-on NPC, otherwise
## the NPC nearest the aim point (within a click's reach).
func _alert_shot_at(aim: Vector2) -> void:
	var npc: Node2D = null
	if is_instance_valid(self.target) and self.target.is_in_group("npcs"):
		npc = self.target
	else:
		npc = _npc_at(aim)
	if npc != null and is_instance_valid(npc) and npc.has_method("face_toward"):
		npc.call("face_toward", global_position)


# ---------------------------------------------------------------- punching (unarmed)

const PUNCH_REACH := 36.0     # px from your centre to the centre of what you hit
const PUNCH_DAMAGE := 8
const PUNCH_COOLDOWN := 0.6
const PUNCH_ANIM := 0.22      # seconds the jab takes on screen
var _punch_t := 0.0           # > 0 while the jab animation plays
var _punch_side := 1.0        # alternates left / right fist


## True when `n` is close enough to punch.
func in_punch_reach(n: Node2D) -> bool:
	return is_instance_valid(n) and global_position.distance_to(n.global_position) <= PUNCH_REACH


## Punches toward `toward`: hits the target if it is within reach, otherwise the nearest NPC or
## breakable prop in reach on that side. Outside combat a punch at nothing is a harmless swing;
## in combat it is refused (your action is kept) until something is in reach.
func punch_at(toward: Vector2) -> void:
	if _cooldown > 0.0 or hp <= 0:
		return
	if turn_mode and not (my_turn and action_left):
		return
	var victim: Node2D = null
	if is_instance_valid(target) and in_punch_reach(target) and target.has_method("take_damage"):
		victim = target
	else:
		var aim := (toward - global_position).normalized()
		var best := INF
		for g in ["npcs", "breakable"]:
			for n in get_tree().get_nodes_in_group(g):
				var node := n as Node2D
				if node == null or not in_punch_reach(node) or not node.has_method("take_damage"):
					continue
				var to := node.global_position - global_position
				if aim != Vector2.ZERO and to.normalized().dot(aim) < 0.2:
					continue  # behind you
				if to.length() < best:
					best = to.length()
					victim = node
	if victim == null and turn_mode:
		notice.emit("Too far to punch - move next to them")
		return
	var dir := (victim.global_position if victim != null else toward) - global_position
	if dir.length() > 0.5:
		facing = dir.normalized()
	_cooldown = PUNCH_COOLDOWN
	_since_shot = 0.0
	_punch_t = PUNCH_ANIM
	_punch_side = -_punch_side
	if victim != null:
		victim.call("take_damage", PUNCH_DAMAGE, self)
	if turn_mode:
		_spend_action()
		_clear_path()
	queue_redraw()


## The hat brim reaches about 12.5 px to the front and 15 px to the sides, so limbs have to reach
## past that to be seen.
const FOOT_STRIDE := 9.0  # how far a foot swings ahead of / behind the body mid-step


## Body proportions, styled on the top-down cowboy reference: the shoulders are a wide oval that
## shows on both sides of the hat, arms reach forward to the hands, boots step out front and back.
const SHOULDER_W := 13.0     # half-width of the shoulders (sideways); hair is ~8.5, a hat brim ~15
const TORSO_D := 6.5         # half-depth of the torso (front to back)
## Shirt colour, picked in the profile panel; static like head_style so it is kept between play-tests.
static var shirt_color := Color("3b6fb0")
const VEST := Color("6a4426")
const VEST_DARK := Color("4a2e18")
const SKIN := Color("e8c9a0")
const OUTLINE := Color("101820")


## Where a hand hangs: straight down from the shoulder (seen from above, right under it),
## swinging a little forward / back against the leg on that side with each step.
func _hang_pos(s: float) -> Vector2:
	var side := body_dir().orthogonal()  # follows the shoulder as the torso twists
	return side * (SHOULDER_W - 3.0) * s - facing * arm_swing() * s


## Unarmed fists hang at the sides and only come up to jab out in front when punching.
func _fist_pos(s: float) -> Vector2:
	var side := facing.orthogonal()
	var rest: Vector2 = _hang_pos(s)
	if _punch_t > 0.0 and s == _punch_side:
		var k := sin((1.0 - _punch_t / PUNCH_ANIM) * PI)  # jab out and back
		return rest.lerp(facing * 22.0 + side * 3.0 * s, k)
	return rest


## True while fist `s` is out on a punch (otherwise it hangs under the shoulder).
func _is_punching(s: float) -> bool:
	return _punch_t > 0.0 and s == _punch_side


## Only the punching fist is drawn above the body; resting fists are drawn under the shoulders.
func _draw_fists() -> void:
	var edge := Color(0.25, 0.15, 0.08)
	for s in [-1.0, 1.0]:
		if not _is_punching(s):
			continue
		var p: Vector2 = _fist_pos(s)
		draw_circle(p, 3.0, SKIN)
		draw_arc(p, 3.0, 0.0, TAU, 12, edge, 1.0)


## Torso outline turned to `facing`: a squarish oval (superellipse) so the shoulders read as
## shoulders rather than a floating egg. `w` = half-width sideways, `d` = half-depth front to back.
## The back is pulled in a little so the chest sits forward under the head.
func _torso_shape(w: float, d: float, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var fwd := body_dir()
	var side := fwd.orthogonal()
	var pts := PackedVector2Array()
	var e := 2.0 / 2.8  # exponent for a squarer curve (2/n with n = 2.8)
	for i in 32:
		var a := TAU * float(i) / 32.0
		var c := cos(a)
		var sn := sin(a)
		var x := signf(c) * pow(absf(c), e) * d * (1.0 if c > 0.0 else 0.85)
		var y := signf(sn) * pow(absf(sn), e) * w
		pts.append(off + fwd * x + side * y)
	return pts


## How far (radians) the shoulders turn with each step. Walking, the shoulders counter-rotate
## against the hips: the shoulder on the side of the back leg comes forward with its arm.
const TORSO_TWIST := 0.07


## The way the torso points this moment: `facing`, turned a little by the walking twist.
## Head, legs and gun aim stay on `facing`.
func body_dir() -> Vector2:
	return facing.rotated(-sin(_step_phase) * TORSO_TWIST * _step_amount)


## Shirt shoulders with a leather vest over the back and chest, shaded darker toward the back.
func _draw_torso() -> void:
	var fwd := body_dir()
	var side := fwd.orthogonal()
	var body := _torso_shape(SHOULDER_W, TORSO_D)
	draw_colored_polygon(body, shirt_color)
	# Shoulder caps: rounded sleeve tops where the arms join.
	for s in [-1.0, 1.0]:
		draw_circle(side * (SHOULDER_W - 3.0) * s, 3.4, shirt_color.darkened(0.25))
		draw_circle(side * (SHOULDER_W - 3.2) * s + fwd * 0.6, 2.4, shirt_color)
	# Vest over the middle, leaving the shirt shoulders showing at the sides.
	var vest := _torso_shape(SHOULDER_W - 4.5, TORSO_D - 0.4)
	draw_colored_polygon(vest, VEST)
	draw_colored_polygon(_torso_shape(SHOULDER_W - 5.5, TORSO_D - 2.5, -fwd * 1.8), VEST_DARK)  # back shade
	draw_polyline(vest + PackedVector2Array([vest[0]]), VEST_DARK, 1.0)
	draw_polyline(body + PackedVector2Array([body[0]]), OUTLINE, 1.5)


## Two boots that swap places with each step. Standing still they sit under the body.
func _draw_legs() -> void:
	var side := facing.orthogonal()
	var swing := sin(_step_phase) * FOOT_STRIDE * _step_amount
	for s in [-1.0, 1.0]:
		var hip: Vector2 = side * 4.5 * s
		var foot: Vector2 = side * 5.0 * s + facing * swing * s
		draw_line(hip, foot, OUTLINE, 6.0)
		draw_line(hip, foot, Color("2a3a55"), 4.5)  # trouser leg
		var boot := PackedVector2Array()  # boot sole, a little longer toward the toe
		for i in 12:
			var a := TAU * float(i) / 12.0
			boot.append(foot + facing * (cos(a) * 3.6 + 0.8) + side * sin(a) * 2.6)
		draw_colored_polygon(boot, Color("4a3220"))
		draw_polyline(boot + PackedVector2Array([boot[0]]), OUTLINE, 1.0)


## How far (px) the hands swing forward / back this moment of the step. Same rhythm as the boots,
## applied the opposite way so each arm swings forward with the other side's leg.
const ARM_SWING := 5.0  # the shoulder is about 5 px deep there, so only the tip of the hand peeks out mid-step


func arm_swing() -> float:
	return sin(_step_phase) * ARM_SWING * _step_amount


## One arm: upper arm to an elbow bent outward, forearm to the hand.
func _draw_arm(shoulder: Vector2, hand: Vector2, s: float, hand_dot: bool) -> void:
	var side := facing.orthogonal()
	# The elbow bends outward only when the arm reaches out; a hanging arm stays straight.
	var bend := clampf(shoulder.distance_to(hand) / 12.0, 0.0, 1.0)
	var elbow: Vector2 = shoulder.lerp(hand, 0.5) + side * 2.5 * s * bend
	draw_line(shoulder, elbow, OUTLINE, 6.0)
	draw_line(elbow, hand, OUTLINE, 6.0)
	draw_circle(elbow, 3.0, OUTLINE)
	draw_line(shoulder, elbow, shirt_color, 4.5)
	draw_line(elbow, hand, shirt_color, 4.0)
	draw_circle(elbow, 2.2, shirt_color)
	if hand_dot:
		draw_circle(hand, 2.6, SKIN)
		draw_arc(hand, 2.6, 0.0, TAU, 10, OUTLINE, 1.0)


## Arms: fists at the sides when unarmed (jabbing out to punch), reaching the grip (and the barrel for long guns)
## when a gun is drawn, otherwise hanging at the sides and swinging against the legs.
## Seen from above, a hanging arm is straight down under its shoulder: only the hand is drawn, and
## it is drawn before the torso (`under` = true) so the shoulder hides it until a step swings it
## out front or back. Arms that reach out (punch, gun grip, barrel) are drawn over the torso.
func _draw_arms(under: bool) -> void:
	var side := facing.orthogonal()
	for s in [-1.0, 1.0]:
		var shoulder: Vector2 = body_dir().orthogonal() * (SHOULDER_W - 3.0) * s
		var hand: Vector2 = _hang_pos(s)
		var hanging := true
		if weapon == "none":
			if _is_punching(s):
				hand = _fist_pos(s)
				hanging = false
		elif weapon_drawn and Weapons.is_ranged(weapon):
			var hold := side * 9.0 + facing * (2.0 - _gun_pull)  # hands follow the gun when it is drawn back
			if s > 0.0:
				hand = hold
				hanging = false
			elif weapon != "pistol":
				hand = hold + facing * 12.0 - side * 1.0  # off hand supports the long gun's barrel
				hanging = false
		if hanging != under:
			continue
		if hanging:
			draw_circle(hand, 3.0, SKIN)
			draw_arc(hand, 3.0, 0.0, TAU, 12, OUTLINE, 1.0)
		else:
			_draw_arm(shoulder, hand, s, weapon != "none")


# ---------------------------------------------------------------- turn-based combat hooks

## Gun in hand (shown and ready). Holstered while exploring; drawn when a fight starts, when a
## target is picked, or when you fire. Put away again once combat ends and nothing is targeted.
var weapon_drawn := true  # the revolver is always in hand for now (see holster())
const DRAW_TIME := 0.3  # seconds before the first shot after pulling the gun out
const HOLSTER_AFTER := 4.0  # with no target and no fight, the gun goes away this long after the last shot


func draw_weapon() -> void:
	if weapon_drawn:
		return
	weapon_drawn = true
	_since_shot = 0.0  # so the idle holster timer starts from now
	if Weapons.is_ranged(weapon) and not (turn_mode and my_turn):
		_cooldown = maxf(_cooldown, DRAW_TIME)  # a moment to pull it out
	queue_redraw()


func holster() -> void:
	return  # disabled for now: the revolver stays in hand
	if not weapon_drawn:
		return
	weapon_drawn = false
	queue_redraw()


const NORMAL_ZOOM := 2.0
const COMBAT_ZOOM := 2.2  # camera zoom while a turn-based fight is on (the MAX_ZOOM limit)
const MIN_ZOOM := 0.9  # furthest out a pinch can go
const MAX_ZOOM := 2.2  # closest in a pinch can go (the zoom limit)
var _cam: Camera2D
var _zoom_tween: Tween
var _zoom_base := NORMAL_ZOOM  # zoom the current mode asks for (normal or combat)
var _zoom_mul := 1.0  # the player's pinch adjustment on top of it


func _target_zoom() -> float:
	return clampf(_zoom_base * _zoom_mul, MIN_ZOOM, MAX_ZOOM)


## Smoothly zooms the camera (used when combat starts and ends). Keeps the pinch adjustment.
func _zoom_camera(z: float) -> void:
	if _cam == null:
		return
	_zoom_base = z
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var t := _target_zoom()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(_cam, "zoom", Vector2(t, t), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Pinch zoom: `factor` > 1 zooms in. The result is kept between MIN_ZOOM and MAX_ZOOM.
func pinch_zoom(factor: float) -> void:
	if _cam == null:
		return
	_zoom_mul = clampf(_zoom_mul * factor, MIN_ZOOM / _zoom_base, MAX_ZOOM / _zoom_base)
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var t := _target_zoom()
	_cam.zoom = Vector2(t, t)


func enter_combat() -> void:
	draw_weapon()
	turn_mode = true
	my_turn = false
	fire_held = false
	_clear_path()
	if _reload_left > 0.0:  # finish a reload that was under way
		_reload_left = 0.0
		_ammo[weapon] = mag(weapon)
	_zoom_camera(COMBAT_ZOOM)
	queue_redraw()


func leave_combat() -> void:
	_zoom_camera(NORMAL_ZOOM)
	if not is_instance_valid(target):
		holster()
	turn_mode = false
	my_turn = false
	move_left = 0.0
	action_left = false
	extra_actions = 0
	_combat_run = false
	_spots.clear()
	_clear_cover()
	queue_redraw()


## Plays a combat card (see game_view.gd COMBAT_CARDS). One card per turn, on your own turn.
## Returns false (and does nothing) when the card can't be used right now.
func play_card(kind: String) -> bool:
	if not can_play_card(kind):
		return false
	match kind:
		"dash":
			move_left += COMBAT_MOVE  # double move: a wider circle of spots
			_refresh_spots()
		"aim":
			aimed = true  # applies to this turn's shot
		"reload":
			# Quick reload: refill without using the turn's action.
			var spent := _casings_left_to_eject(mag(weapon) - ammo())
			_ammo[weapon] = mag(weapon)
			if weapon != "flintlock":
				ShellCasings.spawn(get_tree().current_scene, global_position + facing * 12.0, facing, spent,
						"shell" if weapon == "shotgun" else "brass")
	card_played = true
	queue_redraw()
	return true


## Whether `kind` could be played now (used to grey out cards).
func can_play_card(kind: String) -> bool:
	if not (turn_mode and my_turn) or card_played or _combat_run:
		return false
	match kind:
		"dash":
			return move_left > 0.0
		"aim":
			return action_left and Weapons.is_ranged(weapon)
		"reload":
			return Weapons.is_ranged(weapon) and ammo() < mag(weapon)
	return false


## Extra actions left this turn (the ambush bonus after kicking a door in: 3 actions in round 1).
var extra_actions := 0


## Uses up the turn's action. The turn ends after the last one; an extra action keeps it going.
func _spend_action() -> void:
	if extra_actions > 0:
		extra_actions -= 1
		return
	action_left = false
	move_left = 0.0  # the turn ends after the action


func begin_turn() -> void:
	my_turn = true
	move_left = COMBAT_MOVE
	action_left = true
	card_played = false
	aimed = false
	fan_hammer = false
	_cooldown = 0.0
	_flee_set = false  # a new random run-away spot each turn
	_refresh_spots()
	queue_redraw()


func end_turn() -> void:
	my_turn = false
	move_left = 0.0
	action_left = false
	extra_actions = 0
	aimed = false
	fan_hammer = false
	fire_held = false
	_combat_run = false
	_spots.clear()
	_clear_path()
	queue_redraw()


# ---------------------------------------------------------------- cover spots (turn-based movement)
# In a fight you don't walk freely. The spots behind props (on the side away from the nearest
# enemy) that lie inside your movement circle are highlighted; clicking one runs you there and
# uses up your whole turn. Standing in cover gives a chance to soak up incoming shots equal to
# the prop's defence score (MapData.PROPS "defence").

const COVER_GAP := 18.0     # px between a prop's edge and the spot behind it
const SPOT_PICK := 24.0     # how close (px) a click must land to a spot
const BEHIND_GAP := 24.0    # sneaking: spot this far behind an unaware enemy, within punch reach
const ENGAGE_GAP := 28.0    # unarmed: spot this far from an enemy, close enough to punch

## Highlighted spots this turn: [{pos, node, kind ("cover" | "engage" | "flee"), defence, label}].
var _spots: Array = []
var _flee_pos := Vector2.ZERO  # this turn's run-away spot (see _add_flee_spot)
var _flee_set := false
var _combat_run := false    # running to a spot (the only way to move in a fight)
var _run_spot := {}
var _cover_layer: Node2D
## Prop the player is crouching behind (null = in the open) and its defence score (0..1).
var cover_prop: PropNode = null
var cover_defence := 0.0


func is_running() -> bool:
	return _combat_run


func has_spots() -> bool:
	return not _spots.is_empty()


func _hostile_npcs() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as Node2D
		if npc != null and is_instance_valid(npc) and not npc.is_queued_for_deletion() \
				and int(npc.get("hp")) > 0 and npc.get("disposition") == "hostile":
			out.append(npc)
	return out


func _nearest_to(nodes: Array, p: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for n in nodes:
		var d: float = (n as Node2D).global_position.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = n
	return best


## Works out the spots inside the movement circle: behind props that give cover, and (fists only)
## next to an enemy.
func _refresh_spots() -> void:
	_spots.clear()
	if _grid == null or not (turn_mode and my_turn) or _combat_run or move_left < 1.0:
		return
	var threats := _hostile_npcs()
	if threats.is_empty():
		return
	var reach := move_left
	_add_flee_spot(threats, reach)
	# Sneaking: a spot right behind each hostile that hasn't noticed you yet (if it is in reach).
	for t in threats:
		var npc := t as NpcNode
		if npc == null or npc.alerted:
			continue
		var spot := npc.global_position - npc.facing_dir() * BEHIND_GAP
		if _route_unseen(spot, threats):
			_try_add_spot(spot, npc, "behind", 0.0, "Sneak behind " + npc.npc_name, reach)
	for n in get_tree().get_nodes_in_group("props"):
		var prop := n as PropNode
		if prop == null or prop.is_queued_for_deletion() or prop.defence() <= 0.0:
			continue
		var foe := _nearest_to(threats, prop.global_position)
		var away := prop.global_position - foe.global_position
		if away.length() < 1.0:
			continue
		away = away.normalized()
		var spot := prop.global_position + away * (prop.edge_distance(away) + COVER_GAP)
		_try_add_spot(spot, prop, "cover", prop.defence(), prop.label(), reach)
	_add_wall_spots(threats, reach)
	if weapon == "none":
		for t in threats:
			var npc := t as Node2D
			var to := global_position - npc.global_position
			if to.length() < 1.0:
				continue
			var spot := npc.global_position + to.normalized() * ENGAGE_GAP
			_try_add_spot(spot, npc, "engage", 0.0, "Close in", reach)


func _try_add_spot(spot: Vector2, node: Node2D, kind: String, defence: float, label: String, reach: float) -> bool:
	var d := spot.distance_to(global_position)
	if d > reach or d < 14.0 or not Rect2(Vector2.ZERO, map_size).has_point(spot):
		return false
	var c := Vector2i((spot / CELL).floor())
	if not _grid.is_in_boundsv(c) or _grid.is_point_solid(c):
		return false
	for s in _spots:
		if (s["pos"] as Vector2).distance_to(spot) < 24.0:
			return false  # too close to a spot that is already marked
	var plen := _path_length(spot)
	if plen < 0.0 or plen > reach * 1.15:  # the grid path is a little longer than the smoothed run
		return false
	_spots.append({"pos": spot, "node": node, "kind": kind, "defence": defence, "label": label})
	return true


## Marks the run-away spot: the point at the edge of the movement circle that is farthest from the
## nearest hostile. Picked once per turn and kept, so it doesn't jump around.
func _add_flee_spot(threats: Array, reach: float) -> void:
	if _flee_set:
		_try_add_spot(_flee_pos, self, "flee", 0.0, "Run away", reach)
		return
	# Walk around the rim of the movement circle (stepping inward only where walls or water block
	# the rim) and take the point that is farthest from the nearest hostile.
	var best := Vector2.ZERO
	var best_d := -1.0
	for a in 48:
		var dir := Vector2.RIGHT.rotated(TAU * float(a) / 48.0)
		for f in [0.97, 0.9, 0.8, 0.7, 0.6]:
			var spot: Vector2 = global_position + dir * reach * float(f)
			if not _flee_spot_ok(spot, reach):
				continue
			var d := INF
			for t in threats:
				d = minf(d, spot.distance_to((t as Node2D).global_position))
			if d > best_d:
				best_d = d
				best = spot
			break  # the outermost reachable point on this bearing is the one that counts
	if best_d >= 0.0 and _try_add_spot(best, self, "flee", 0.0, "Run away", reach):
		_flee_pos = best
		_flee_set = true


const WALL_SPOT_STEP := 56.0  # px between wall-cover candidates along a wall
const WALL_SPOT_GAP := 16.0   # how far from the wall's face the player crouches
const MAX_WALL_SPOTS := 4     # keep the screen readable: only the closest few are marked

## Spots hugging a wall on the side away from the hostiles, where the wall breaks every hostile's
## line of sight. Hiding there you can't shoot (see in_wall_cover), and NPCs must move to see you.
func _add_wall_spots(threats: Array, reach: float) -> void:
	var space := get_world_2d().direct_space_state
	var found: Array = []  # [dist, pos]
	var watchers := _watchers(threats)
	for w in MapData.working.get("walls", []):
		if str(w.get("style", "wall")) == "rail":
			continue
		var pts: PackedVector2Array = w["points"]
		if pts.size() < 2:
			continue
		var path := PackedVector2Array(pts)
		if bool(w.get("closed", false)):
			path.append(pts[0])
		var off := float(w.get("width", 8.0)) * 0.5 + WALL_SPOT_GAP
		var cands: Array = []
		# Along each segment, on BOTH faces (the hidden face isn't always the one "away" from the
		# nearest enemy, e.g. the outside of a building's side wall), including close to the ends.
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var seg_len := a.distance_to(b)
			if seg_len < 1.0:
				continue
			var normal := (b - a).normalized().orthogonal()
			var n := maxi(int(seg_len / WALL_SPOT_STEP), 1) + 1
			for k in n + 1:
				var on_wall := a.lerp(b, clampf(float(k) / float(n), 0.0, 1.0))
				cands.append(on_wall + normal * off)
				cands.append(on_wall - normal * off)
		# Around each corner / wall end: ducking round a corner is the classic wall cover.
		for v in path:
			for d in 8:
				cands.append((v as Vector2) + Vector2.RIGHT.rotated(TAU * float(d) / 8.0) * off * 1.4)
		for c in cands:
			var spot: Vector2 = c
			var dist := spot.distance_to(global_position)
			if dist > reach or dist < 20.0:
				continue
			var cell := Vector2i((spot / CELL).floor())
			if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell):
				continue  # too tight against the wall for the path grid
			if not _hidden_from_all(spot, watchers, space):
				continue
			found.append([dist, spot])
	found.sort_custom(func(x, y) -> bool: return x[0] < y[0])
	var added: Array = []
	for f in found:
		var p: Vector2 = f[1]
		if added.size() >= MAX_WALL_SPOTS:
			break
		var crowded := false
		for q in added:
			if (q as Vector2).distance_to(p) < 48.0:
				crowded = true  # spread the few marked spots out instead of bunching them
				break
		if not crowded and _try_add_spot(p, self, "wall", 0.0, "Wall cover", reach):
			added.append(p)


## The hostiles a hiding spot has to be hidden from: every NPC in the current fight (however far
## away it stands) plus any other hostile close enough to see the spot area.
func _watchers(threats: Array) -> Array:
	var out: Array = []
	var fight := get_tree().get_first_node_in_group("combat")
	if fight != null and bool(fight.get("active")):
		for e in fight.get("order"):
			var node = e["node"]  # untyped: may be freed
			if is_instance_valid(node) and node is NpcNode and (node as NpcNode).hp > 0:
				out.append(node)
	for t in threats:
		var npc := t as Node2D
		if not out.has(npc) and npc.global_position.distance_to(global_position) <= Combat.JOIN_RANGE + COMBAT_MOVE:
			out.append(npc)
	return out


## True when a wall (or closed door) sits between `p` and every hostile in `watchers`
## (and there is at least one).
func _hidden_from_all(p: Vector2, watchers: Array, space: PhysicsDirectSpaceState2D) -> bool:
	if watchers.is_empty():
		return false
	var exclude: Array[RID] = [get_rid()]
	for n in get_tree().get_nodes_in_group("combatants"):
		if n is CollisionObject2D:
			exclude.append((n as CollisionObject2D).get_rid())  # bodies don't hide you
	for t in watchers:
		var npc := t as Node2D
		var q := PhysicsRayQueryParameters2D.create(npc.global_position, p, 1, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["collider"] as Node).get_parent() is PropNode:
			return false  # open line, or only a prop in the way (props are normal cover)
	return true


## Crouched behind a wall: hidden, but you can't shoot from here. Cleared when you move.
var wall_cover := false

func in_wall_cover() -> bool:
	return wall_cover


## Same checks as _try_add_spot (inside the circle, on the map, walkable, reachable by path), without adding.
func _flee_spot_ok(spot: Vector2, reach: float) -> bool:
	if not Rect2(Vector2.ZERO, map_size).has_point(spot):
		return false
	var c := Vector2i((spot / CELL).floor())
	if not _grid.is_in_boundsv(c) or _grid.is_point_solid(c):
		return false
	var plen := _path_length(spot)
	return plen >= 0.0 and plen <= reach * 1.15
			

## True when walking to `to` never passes through the view arc of any of `threats`
## (the whole walking path is sampled, including where it ends).
func _route_unseen(to: Vector2, threats: Array) -> bool:
	if _grid == null:
		return false
	var start := _cell(position)
	var start_was_solid := _grid.is_point_solid(start)
	if start_was_solid:
		_grid.set_point_solid(start, false)
	var pts := _grid.get_point_path(start, _cell(to))
	if start_was_solid:
		_grid.set_point_solid(start, true)
	if pts.size() < 2:
		return false
	pts[0] = position  # the walk starts where the player really stands
	pts[pts.size() - 1] = to
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var steps := maxi(int(a.distance_to(b) / 8.0), 1)
		for k in range(1, steps + 1):
			var p := a.lerp(b, float(k) / float(steps))
			for t in threats:
				var npc := t as NpcNode
				if npc != null and npc.arc_covers(p, Combat.JOIN_RANGE):
					return false
	return true


## Length of the walking path to `to`, or -1 when there is none.
func _path_length(to: Vector2) -> float:
	var start := _cell(position)
	var start_was_solid := _grid.is_point_solid(start)
	if start_was_solid:
		_grid.set_point_solid(start, false)
	var pts := _grid.get_point_path(start, _cell(to))
	if start_was_solid:
		_grid.set_point_solid(start, true)
	if pts.size() < 2:
		return -1.0
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total


func _spot_at(p: Vector2) -> int:
	var best := -1
	var best_d := SPOT_PICK
	for i in _spots.size():
		var d: float = p.distance_to(_spots[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


func _clear_cover() -> void:
	cover_prop = null
	cover_defence = 0.0
	wall_cover = false


## Runs to spot `i`. The run uses up the whole turn (the action is given up).
func _run_to_spot(i: int) -> void:
	if i < 0 or i >= _spots.size() or not my_turn:
		return
	var spot: Dictionary = _spots[i]
	_clear_cover()
	set_interact(null)
	_clear_path()
	_combat_run = true
	_move_to(spot["pos"])
	if _path.is_empty():
		_combat_run = false
		notice.emit("Can't get there")
		return
	_run_spot = spot
	if spot["kind"] == "flee":
		morale = maxi(morale - FLEE_MORALE_LOSS, 0)
		morale_changed.emit(morale, MAX_MORALE)
		notice.emit("You ran away - morale -%d" % FLEE_MORALE_LOSS)
	action_left = false
	extra_actions = 0
	fire_held = false
	_spots.clear()
	queue_redraw()


## The run is over: settle into cover (if that is where it ended) and end the turn's movement.
func _finish_run() -> void:
	_combat_run = false
	var spot := _run_spot
	_run_spot = {}
	if not spot.is_empty() and spot["kind"] == "cover" and is_instance_valid(spot["node"]) \
			and position.distance_to(spot["pos"]) < 30.0:
		cover_prop = spot["node"]
		cover_defence = float(spot["defence"])
		notice.emit("In cover behind %s (defence %d%%)" % [spot["label"], roundi(cover_defence * 100.0)])
	elif not spot.is_empty() and spot["kind"] == "wall" and position.distance_to(spot["pos"]) < 30.0:
		wall_cover = true
		notice.emit("Behind a wall: hidden, but you can't shoot from here")
	move_left = 0.0
	action_left = false
	queue_redraw()


## True when `from` is shooting at the player across the prop they are crouching behind and the
## prop soaks the shot up (a roll against its defence score).
func _cover_absorbs(from: Node) -> bool:
	if not is_instance_valid(cover_prop) or cover_defence <= 0.0 or not is_instance_valid(from):
		return false
	var shooter := from as Node2D
	if shooter == null:
		return false
	var s := shooter.global_position
	if s.distance_to(global_position) < 60.0:
		return false  # point blank: cover doesn't help
	var c := cover_prop.global_position
	if (s - global_position).dot(c - global_position) <= 0.0:
		return false  # the prop is on the other side
	var cp := Geometry2D.get_closest_point_to_segment(c, s, global_position)
	var off := cp - c
	var body := cover_prop.edge_distance(off.normalized() if off.length() > 0.5 else Vector2.RIGHT)
	if off.length() > body + 14.0:
		return false  # the shot comes past the side of the prop
	return randf() < cover_defence


func _update_cover_layer() -> void:
	for i in range(_spots.size() - 1, -1, -1):
		if not is_instance_valid(_spots[i]["node"]):  # barrel shot apart, enemy defeated
			_spots.remove_at(i)
	var show := turn_mode and my_turn and not _combat_run and not _spots.is_empty()
	_cover_layer.visible = show
	if show:
		_cover_layer.queue_redraw()


func _draw_cover_layer() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var hover := _spot_at(get_global_mouse_position()) if get_viewport().gui_get_hovered_control() == null else -1
	var font := ThemeDB.fallback_font
	for i in _spots.size():
		var s: Dictionary = _spots[i]
		var p: Vector2 = s["pos"]
		var cover: bool = s["kind"] == "cover"
		var col: Color = Color(0.35, 0.9, 0.5) if cover else ({
			"flee": Color(0.5, 0.7, 1.0), "behind": Color(0.75, 0.5, 1.0), "wall": Color(0.8, 0.8, 0.75),
		} as Dictionary).get(s["kind"], Color(1.0, 0.7, 0.3))
		var hot := i == hover
		var r := 15.0 + sin(t * 4.0 + float(i)) * 1.2 + (3.0 if hot else 0.0)
		if cover and is_instance_valid(s["node"]):
			_cover_layer.draw_line((s["node"] as Node2D).global_position, p, Color(col, 0.22), 1.5)
		_cover_layer.draw_circle(p, r, Color(col, 0.38 if hot else 0.18))
		_cover_layer.draw_arc(p, r, 0.0, TAU, 28, Color(col, 1.0 if hot else 0.75), 2.5 if hot else 2.0)
		_cover_layer.draw_circle(p, 2.5, Color(col, 0.9))
		var txt: String = "%s  DEF %d%%" % [s["label"], roundi(float(s["defence"]) * 100.0)] if cover else str(s["label"])
		_cover_layer.draw_string(font, p + Vector2(-70, r + 14.0), txt, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, Color(col.lightened(0.3), 1.0))
		if hot:
			_cover_layer.draw_string(font, p + Vector2(-70, r + 28.0), "run here (uses your turn)", HORIZONTAL_ALIGNMENT_CENTER, 140, 11, Color(1, 1, 1, 0.85))


## Selects a door or window (or clears with null) and walks to the near side of it.
func set_interact(opening: Node2D) -> void:
	interact = opening if is_instance_valid(opening) else null
	_interact_arrived = false
	_interact_marker.visible = interact != null
	if interact == null:
		return
	_interact_spot = interact.call("approach_point", global_position)
	_move_to(_interact_spot)
	if _path.is_empty() and global_position.distance_to(_interact_spot) < INTERACT_REACH:
		_arrive_at_interact()  # already standing there
	_interact_marker.queue_redraw()


## True while following a click-to-move path.
func is_walking() -> bool:
	return not _path.is_empty()


func is_at_interact() -> bool:
	return is_instance_valid(interact) and _interact_arrived


## Door or window under `p` (the "go to it" selection).
func _opening_at(p: Vector2) -> Node2D:
	for n in get_tree().get_nodes_in_group("openings"):
		if n.call("hit_test", p):
			return n
	return null


## Barrel or crate under `p` (targetable like an NPC).
func _container_at(p: Vector2) -> Node2D:
	for n in get_tree().get_nodes_in_group("containers"):
		if n.call("hit_test", p):
			return n
	return null


## Turns to face the selected door/window once the walk there is over.
func _arrive_at_interact() -> void:
	_interact_arrived = true
	var to := interact.global_position - global_position
	if to.length() > 0.5:
		facing = to.normalized()
		queue_redraw()


func _update_interact() -> void:
	# A freed reference (barrel shot apart) is not == null, so test validity, not null.
	if not is_instance_valid(interact) or interact.is_queued_for_deletion():
		if _interact_marker.visible or interact != null:
			interact = null
			set_interact(null)
		return
	if not _interact_arrived and _path.is_empty() and global_position.distance_to(_interact_spot) < INTERACT_REACH:
		_arrive_at_interact()
	# The marker follows the opening's position and wall direction.
	_interact_marker.global_transform = interact.global_transform
	_interact_marker.queue_redraw()


## Selection for doors/windows: cyan corner brackets around the opening (the NPC target uses a red/yellow ring).
func _draw_interact_marker() -> void:
	if not is_instance_valid(interact):
		return
	var w: float = interact.get("width")
	var t: float = maxf(float(interact.get("thick")), 10.0)
	var t_s := Time.get_ticks_msec() / 1000.0
	var grow := 5.0 + sin(t_s * 5.0) * 1.5
	var r := Rect2(Vector2(-w * 0.5, -t * 0.5), Vector2(w, t)).grow(grow)
	var col := Color(0.35, 0.9, 1.0)
	var arm := minf(10.0, r.size.x * 0.3)
	_interact_marker.draw_rect(r, Color(col, 0.12))
	for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if c.x < 0.0 else -1.0
		var sy := 1.0 if c.y < 0.0 else -1.0
		_interact_marker.draw_line(c, c + Vector2(arm * sx, 0), col, 2.5)
		_interact_marker.draw_line(c, c + Vector2(0, arm * sy), col, 2.5)


func set_target(npc: Node2D) -> void:
	if is_instance_valid(target) and target.has_signal("defeated") and target.is_connected("defeated", _on_target_defeated):
		target.disconnect("defeated", _on_target_defeated)
	target = npc if is_instance_valid(npc) else null
	# Drop the lock the moment the NPC is defeated.
	if target != null and target.has_signal("defeated"):
		target.connect("defeated", _on_target_defeated)
	if target != null:
		facing = (target.global_position - global_position).normalized()
		draw_weapon()  # picking a target pulls the gun out
		queue_redraw()
	elif not turn_mode:
		holster()  # nothing targeted and no fight on: put it away
	_reticle.visible = target != null


## Picks the nearest NPC in range, or the next-nearest after the current target on repeat presses.
## Hostile NPCs come first so Tab finds threats before bystanders.
func cycle_target() -> void:
	var list: Array = []
	for g in ["npcs", "containers"]:
		for n in get_tree().get_nodes_in_group(g):
			if is_instance_valid(n) and global_position.distance_to(n.global_position) <= _target_range(n):
				list.append(n)
	if list.is_empty():
		set_target(null)
		return
	# Order: hostile NPCs, other NPCs, then barrels / crates; nearest first within each.
	var rank := func(n: Node) -> int:
		if not n.is_in_group("npcs"):
			return 2
		return 0 if n.get("disposition") == "hostile" else 1
	list.sort_custom(func(a, b) -> bool:
		var ra: int = rank.call(a)
		var rb: int = rank.call(b)
		if ra != rb:
			return ra < rb
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	var i := list.find(target)
	set_target(list[(i + 1) % list.size()])


## Living hostile NPCs and animals the player can pick: within targeting range, or already in the
## fight (combat_mode) wherever they stand. Nearest first.
func hostile_targets() -> Array:
	var in_fight: Array = []
	var cmb := get_tree().get_first_node_in_group("combat")
	if cmb != null and cmb.get("active"):
		for e in cmb.get("order"):
			in_fight.append(e["node"])
	var list: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		if not is_instance_valid(n) or n.is_queued_for_deletion() or int(n.get("hp")) <= 0:
			continue
		if n.get("disposition") != "hostile":
			continue
		if in_fight.has(n) or global_position.distance_to(n.global_position) <= _target_range(n):
			list.append(n)
	list.sort_custom(func(a, b) -> bool:
		return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	return list


## Targets the next hostile after the current one (nearest first); wraps round. Does nothing when
## none are in range or in the fight.
func next_hostile_target() -> void:
	var list := hostile_targets()
	if list.is_empty():
		return
	set_target(list[(list.find(target) + 1) % list.size()])


## Click and hold on the ground: the move point follows the cursor until the button is released.
var _hold_move := false
var _hold_timer := 0.0
const HOLD_REPATH := 0.08  # seconds between updates of the move point


func _update_hold_move(delta: float) -> void:
	if not _hold_move:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or hp <= 0 \
			or _pending_target != null or _punch_chase != null:
		_hold_move = false
		return
	_hold_timer -= delta
	if _hold_timer > 0.0:
		return
	_hold_timer = HOLD_REPATH
	var mp := get_global_mouse_position()
	if mp.distance_to(_marker_pos) > 4.0 and global_position.distance_to(mp) > 6.0:
		_move_to(mp)


## Stops the walk once the double-clicked target is within punch reach; gives up if it is gone,
## no longer the target, or the walk ended without reaching it (re-paths once if it moved).
func _update_punch_chase() -> void:
	if _punch_chase == null:
		return
	if not is_instance_valid(_punch_chase) or _punch_chase.is_queued_for_deletion() \
			or _punch_chase != target or weapon != "none":
		_punch_chase = null
		return
	if in_punch_reach(_punch_chase):
		_punch_chase = null
		_clear_path()
	elif _path.is_empty():
		_move_to(_punch_chase.global_position)
		if _path.is_empty():
			_punch_chase = null


## Walking toward a far NPC that was clicked: lock on (and stop) once it is within 6 tiles.
## Gives up if the NPC dies or the walk ends without getting close enough.
func _update_pending_target() -> void:
	if _pending_target == null:
		return
	if not is_instance_valid(_pending_target) or _pending_target.is_queued_for_deletion():
		_pending_target = null
		return
	if global_position.distance_to(_pending_target.global_position) <= NPC_TARGET_RANGE:
		var npc := _pending_target
		_pending_target = null
		_clear_path()
		set_target(npc)
	elif _path.is_empty():
		_pending_target = null
		notice.emit("Couldn't get close enough to target")


## How far away `n` may be and still be (or stay) the target: 6 tiles for NPCs.
func _target_range(n: Node) -> float:
	return NPC_TARGET_RANGE if n.is_in_group("npcs") else TARGET_RANGE


func _npc_at(p: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := CLICK_RADIUS
	for n in get_tree().get_nodes_in_group("npcs"):
		var d: float = p.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _on_target_defeated(npc: Node) -> void:
	if npc == target:
		set_target(null)


## Drops a dead or distant target and keeps the reticle on it.
func _update_target() -> void:
	if not is_instance_valid(target):
		target = null  # also covers a freed reference, which isn't == null
	elif target.is_queued_for_deletion() or global_position.distance_to(target.global_position) > _target_range(target):
		set_target(null)
	_reticle.visible = target != null
	if target != null:
		_reticle.global_position = target.global_position
		_reticle.queue_redraw()


func _draw_reticle() -> void:
	# With a gun: green = close, good odds; shading to yellow toward the edge of the range;
	# red = out of range. Unarmed: yellow (nothing to shoot with).
	var col := Color(1.0, 0.9, 0.4)
	if is_instance_valid(target) and weapon == "none":
		col = Color(0.3, 1.0, 0.35) if in_punch_reach(target) else Color(1.0, 0.25, 0.2)  # fists: in reach or not
	elif is_instance_valid(target) and Weapons.is_ranged(weapon):
		col = Weapons.range_color(weapon, global_position.distance_to(target.global_position), AIM_RANGE if aimed else 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	var base_r := 16.0
	if is_instance_valid(target) and target.has_method("_radius"):  # barrels / crates: fit around the prop
		base_r = maxf(16.0, float(target.call("_radius")) + 5.0)
	var r := base_r + sin(t * 6.0) * 1.5
	_reticle.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 1.5)
	for k in 4:
		var d := Vector2.RIGHT.rotated(k * PI * 0.5 + t * 0.8)
		_reticle.draw_line(d * (r - 4.0), d * (r + 5.0), col, 2.0)


func take_damage(amount: int, from: Node) -> void:
	if hp <= 0:
		return
	if _cover_absorbs(from):
		notice.emit("Cover soaked up the shot")
		return
	hp = maxi(hp - amount, 0)
	_hurt_flash = 0.25
	if hp == 0:
		# Simple play-test respawn: back to the spawn point with full health.
		_clear_path()
		_clear_cover()
		position = _spawn
		reset_physics_interpolation()
		hp = MAX_HP
		morale = MAX_MORALE
		morale_changed.emit(morale, MAX_MORALE)
		_ammo.clear()  # respawn with full magazines
		_reload_left = 0.0
		respawned.emit()
	health_changed.emit(hp, MAX_HP)
	queue_redraw()


func _move_to(target: Vector2) -> void:
	if turn_mode and not _combat_run:
		return  # turn-based: only the run to a highlighted spot moves you
	var goal := _nearest_free(_cell(target))
	if goal.x < 0:
		return
	var start := _cell(position)
	var start_was_solid := _grid.is_point_solid(start)
	if start_was_solid:
		_grid.set_point_solid(start, false)
	var pts := _grid.get_point_path(start, goal)
	if start_was_solid:
		_grid.set_point_solid(start, true)
	if pts.size() < 2:
		return
	pts.remove_at(0)  # current cell
	if _cell(target) == goal:
		pts[pts.size() - 1] = target
	_path = _smooth_path(position, pts)
	_stuck = 0.0
	_marker_pos = pts[pts.size() - 1]
	_marker.visible = true
	_marker.queue_redraw()


## The grid path visits every 16px cell centre, which makes the character zig-zag and turn in steps.
## This drops waypoints that can be skipped: from each point, jump to the furthest later waypoint
## the character's collision circle can reach in a straight line.
func _smooth_path(from: Vector2, pts: PackedVector2Array) -> PackedVector2Array:
	const LOOKAHEAD := 48
	var space := get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 10.5
	q.shape = shape
	q.exclude = [get_rid()]
	var out := PackedVector2Array()
	var anchor := from
	var i := 0
	while i < pts.size():
		var j := mini(i + LOOKAHEAD, pts.size() - 1)
		while j > i:
			q.transform = Transform2D(0.0, anchor)
			q.motion = pts[j] - anchor
			var r := space.cast_motion(q)
			if r.size() >= 1 and r[0] >= 1.0:
				break
			j -= 1
		out.append(pts[j])
		anchor = pts[j]
		i = j + 1
	return out


func _clear_path() -> void:
	_path = PackedVector2Array()
	_stuck = 0.0
	if _marker:
		_marker.visible = false


func _draw_marker() -> void:
	_marker.draw_arc(_marker_pos, 10.0, 0.0, TAU, 24, Color(1, 0.9, 0.4, 0.9), 2.0)
	_marker.draw_circle(_marker_pos, 3.0, Color(1, 0.9, 0.4, 0.9))


func _draw() -> void:
	if turn_mode and my_turn:
		# Filled highlight under the player while it is their turn.
		draw_circle(Vector2.ZERO, 17.0, Color(0.35, 0.8, 1.0, 0.35))
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 28, Color(0.35, 0.8, 1.0, 0.95), 2.5)
	if turn_mode and wall_cover:
		draw_string(ThemeDB.fallback_font, Vector2(-60, 32), "Behind wall (can't shoot)",
				HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(0.85, 0.85, 0.8))
	if turn_mode and is_instance_valid(cover_prop):
		draw_string(ThemeDB.fallback_font, Vector2(-60, 32), "In cover %d%%" % roundi(cover_defence * 100.0),
				HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(0.5, 1.0, 0.6))
	if turn_mode and my_turn and move_left > 1.0 and not _combat_run:
		# How far you can run this turn: the highlighted spots lie inside this circle.
		draw_circle(Vector2.ZERO, move_left, Color(0.35, 0.8, 1.0, 0.07))
		draw_arc(Vector2.ZERO, move_left, 0.0, TAU, 64, Color(0.35, 0.8, 1.0, 0.6), 1.5)
	# Ground shadow stays the same size; the character above it pulses with each step.
	draw_colored_polygon(_torso_shape(SHOULDER_W + 1.0, TORSO_D + 1.5, Vector2(3, 4)), MapData.shadow_color(0.3))
	var bs := step_scale()
	var xf := Vector2(bs, bs)
	draw_set_transform(Vector2.ZERO, 0.0, xf)
	if SHOW_HANDS_FEET:
		_draw_legs()
	# Shoulders show either side of the hat (drawing only; the collision circle is unchanged).
	if SHOW_HANDS_FEET:
		_draw_arms(true)  # hanging hands, hidden under the shoulders until they swing out
	if SHOW_SHOULDERS:
		_draw_torso()
	if SHOW_HANDS_FEET:
		_draw_arms(false)  # arms reaching out (punch, gun) go over the body
	if weapon == "none":
		if SHOW_HANDS_FEET:
			_draw_fists()
	elif _revolver != null and weapon == "pistol":
		pass  # the revolver is the animated sprite from weapons.tscn (see _sync_revolver)
	elif weapon_drawn:
		var hold := facing.orthogonal() * 9.0 + facing * 2.0
		# _gun_pull draws the gun back (like the recoil kick) when a body is right in front of it.
		if Weapons.draw_held_image(self, weapon, facing, hold, bs, _kick_amount() + _gun_pull):
			draw_set_transform(Vector2.ZERO, 0.0, xf)  # the image call resets the transform
		else:
			Weapons.draw_held(self, weapon, facing, hold - facing * _gun_pull)
	else:
		_draw_holstered()
	if _hat_layer == null:
		_draw_hat()  # no separate layer: draw it here (still above the weapons drawn above)
	if _hurt_flash > 0.0:
		draw_circle(Vector2.ZERO, 11.0, Color(1, 0.1, 0.1, _hurt_flash * 2.0))
	draw_set_transform_matrix(Transform2D.IDENTITY)


# ---------------------------------------------------------------- animated revolver (scenes/weapons.tscn)

const WEAPONS_SCENE := "res://scenes/weapons.tscn"
const REV_GRIP := Vector2(30, 39)  # pixel of the 64x64 frame that sits in the hand
const REV_SCALE := 0.65
const REV_REACH := 11.0
const REV_SIDE := 6.0
const REV_HOLSTER_SIDE := 13.0   # holstered: this far to the player's right
const REV_HOLSTER_REACH := 0.0   # holstered: this far forward (negative = back)
const REV_MOVE_TIME := 0.3       # seconds to slide between the holster and the hand
var _revolver: AnimatedSprite2D
var _rev_state := ""
var _rev_blend := 0.0  # 0 = at the holster, 1 = in the hand


func _setup_revolver() -> void:
	if not ResourceLoader.exists(WEAPONS_SCENE):
		return
	var holder := (load(WEAPONS_SCENE) as PackedScene).instantiate()
	_revolver = holder.get_node_or_null("Revolver") as AnimatedSprite2D
	if _revolver == null:
		holder.queue_free()
		return
	_revolver.sprite_frames.set_animation_loop("holster draw", false)  # play once, hold the last frame
	_revolver.centered = false
	_revolver.offset = -REV_GRIP
	_revolver.visible = false
	add_child(holder)


## Holstered (walking about): the "holster" animation, or the first frame of "holster draw" if
## there is no such animation. Gun drawn (targeting, shooting, combat): plays "holster draw".
## Putting it away plays "holster draw" backwards.
func _sync_revolver(delta: float) -> void:
	if _revolver == null:
		return
	var show_it := weapon == "pistol"
	_revolver.visible = show_it
	if not show_it:
		_rev_state = ""
		_rev_blend = 1.0 if weapon_drawn else 0.0
		return
	var bs := step_scale()
	var right := Vector2(-facing.y, facing.x)
	# Holstered it sits at the player's right side; drawing slides it forward into the hand.
	_rev_blend = move_toward(_rev_blend, 1.0 if weapon_drawn else 0.0, delta / REV_MOVE_TIME)
	var holstered_at := right * REV_HOLSTER_SIDE + facing * REV_HOLSTER_REACH
	var drawn_at := facing * (REV_REACH - _gun_pull) + right * REV_SIDE  # drawn back for a close target
	_revolver.position = holstered_at.lerp(drawn_at, smoothstep(0.0, 1.0, _rev_blend)) * bs
	_revolver.rotation = facing.angle() + PI * 0.5
	_revolver.scale = Vector2(REV_SCALE, REV_SCALE) * bs
	var want := "drawn" if weapon_drawn else "holster"
	if want == _rev_state:
		return
	var frames := _revolver.sprite_frames
	var last := frames.get_frame_count("holster draw") - 1
	var first_time := _rev_state == ""
	_rev_state = want
	if want == "drawn":
		_revolver.animation = &"holster draw"
		if first_time:
			_revolver.frame = last
		else:
			_revolver.play(&"holster draw")
	elif frames.has_animation("holster"):
		_revolver.play(&"holster")
	else:
		_revolver.animation = &"holster draw"
		if first_time:
			_revolver.frame = 0
		else:
			_revolver.play_backwards(&"holster draw")


func _process(delta: float) -> void:
	var pull_before := _gun_pull
	_gun_pull = move_toward(_gun_pull, gun_pull_for(facing), GUN_PULL_SPEED * delta)
	if _gun_pull != pull_before:
		queue_redraw()
	_sync_revolver(delta)
	if _hat_layer != null:
		_hat_layer.queue_redraw()  # follows facing, step pulse and the chosen hat


var _hat_layer: Node2D


## Put-away gun: a revolver in a holster on the right hip, long guns slung across the back.
func _draw_holstered() -> void:
	if not Weapons.is_ranged(weapon):
		return
	var right := facing.orthogonal()
	if weapon == "pistol":
		var hip := right * 6.5 - facing * 1.5
		var pts := PackedVector2Array([hip - facing * 4.0 - right * 1.8, hip - facing * 4.0 + right * 1.8,
				hip + facing * 3.0 + right * 1.5, hip + facing * 3.0 - right * 1.5])
		draw_colored_polygon(pts, Color("5a3a1e"))  # leather holster
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("2a1a0c"), 1.0)
		draw_circle(hip + facing * 3.5, 1.6, Color("3a3a40"))  # grip poking out
	else:
		# Sling strap and the gun's outline lying diagonally across the back.
		var a := -facing * 5.0 + right * 7.0 + facing * -1.0
		var b := -facing * 5.0 - right * 7.0 + facing * 6.0
		draw_line(a, b, Color("3a3a40") if weapon == "rifle" else Color("4a3220"), 2.6)
		draw_line(right * 5.0 + facing * 3.0, -right * 5.0 - facing * 5.0, Color("6b4a2a"), 1.0)  # strap


## Size multiplier for the walking pulse: grows a little at the middle of each step and
## settles back to 1 when standing still.
func step_scale() -> float:
	return 1.0 + STEP_PULSE * _step_amount * absf(sin(_step_phase))


## Draws the selected hat or hair turned to `facing`.
func _draw_hat() -> void:
	var bs := step_scale()
	HeadArt.draw(self, head_style, Vector2.ZERO, facing.angle(), bs)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(bs, bs))  # HeadArt.draw resets the transform


func set_shirt_color(c: Color) -> void:
	shirt_color = c
	queue_redraw()


## Profile picture: the character from above (shoulders, vest, head) centred on `c`, facing up,
## using the current head style and shirt colour. `s` scales it (1 = in-game size).
static func draw_portrait(ci: CanvasItem, c: Vector2, s: float) -> void:
	var shape := func(w: float, d: float, back: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var e := 2.0 / 2.8
		for i in 32:
			var a := TAU * float(i) / 32.0
			var co := cos(a)
			var sn := sin(a)
			var y := -signf(co) * pow(absf(co), e) * d * (1.0 if co > 0.0 else 0.85) + back
			pts.append(c + Vector2(signf(sn) * pow(absf(sn), e) * w, y) * s)
		return pts
	var body: PackedVector2Array = shape.call(SHOULDER_W, TORSO_D, 0.0)
	ci.draw_colored_polygon(body, shirt_color)
	for side in [-1.0, 1.0]:
		ci.draw_circle(c + Vector2((SHOULDER_W - 3.0) * side, 0) * s, 3.4 * s, shirt_color.darkened(0.25))
		ci.draw_circle(c + Vector2((SHOULDER_W - 3.2) * side, -0.6) * s, 2.4 * s, shirt_color)
	var vest: PackedVector2Array = shape.call(SHOULDER_W - 4.5, TORSO_D - 0.4, 0.0)
	ci.draw_colored_polygon(vest, VEST)
	ci.draw_colored_polygon(shape.call(SHOULDER_W - 5.5, TORSO_D - 2.5, 1.8), VEST_DARK)
	ci.draw_polyline(vest + PackedVector2Array([vest[0]]), VEST_DARK, 1.0 * s)
	ci.draw_polyline(body + PackedVector2Array([body[0]]), OUTLINE, 1.5 * s)
	HeadArt.draw(ci, head_style, c, -PI * 0.5, s)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func set_head(idx: int) -> void:
	head_style = clampi(idx, 0, HeadArt.count() - 1)
	queue_redraw()
