extends Node2D
## Play-test screen: loads the working map with collisions and lighting and spawns a player.

const HeadArt := preload("res://scripts/head_art.gd")
const CountryMap := preload("res://scripts/country_map.gd")

var renderer: MapRenderer
var player: Player
var door_prompt: Label
var ammo_label: Label
var reload_bar: ProgressBar
var target_label: Label
var interact_label: Label
var message_label: Label
var shoot_btn: Button
const STICK_MARGIN_X := 80.0   # joystick / Shoot button distance from the left / right screen edge
const STICK_MARGIN_Y := 130.0  # ... and from the bottom edge
const KICK_ENTER_DIST := 45.0  # px past the door the player lands after a kick
const KICK_ROOM := 80.0  # Kick is only offered when this much space behind the door is clear
const DOOR_BTN := 68.0  # diameter of the round Open / Kick / Close buttons
var stick: TouchStick
var _action_panel: PanelContainer  # Skip turn / End combat; only shown in combat
var _minimap: Control
var _top_col: VBoxContainer  # Start combat / Untarget, beside the weapon button
var weapon_btn: Button
var weapon_icon: Control
var _wheel_layer: CanvasLayer
var untarget_btn: Button
var fight_btn: Button
var skip_btn: Button
var end_combat_btn: Button
var combat: Combat
var combat_panel: PanelContainer
var combat_border: Panel
var combat_title: Label
var combat_list: VBoxContainer
var combat_status: Label
var end_turn_btn: Button
var _hp_refresh := 0.0
var _bounty_total := 0     # bounty NPCs on the map when play-test started
var _saw_hostile := false  # (maps without bounties) a hostile NPC has been alive at some point
var _game_over := false
var _destinations: Array = []  # map polygons of type "destination": {points, coins?, bounties?}
var _dest_hint_until := 0      # Time.get_ticks_msec() before which the "can't leave yet" hint stays quiet
var _win_title := ""           # overrides the victory heading (set for destination wins)
const COMBAT_FONT := 10  # font size in the compact combat box

## Special-action cards dealt along the bottom of the screen during combat (one per turn).
## Effects are in Player.play_card().
const COMBAT_CARDS := [
	{"kind": "dash", "title": "Dash", "desc": "Double your movement this turn.", "accent": Color(0.25, 0.55, 0.9)},
	{"kind": "aim", "title": "Aimed Shot", "desc": "This turn's shot flies dead straight, hits 50% harder and reaches 50% further.", "accent": Color(0.8, 0.25, 0.2)},
	{"kind": "reload", "title": "Quick Reload", "desc": "Refill your gun without using your action.", "accent": Color(0.8, 0.6, 0.15)},
]
## Set to true to bring back the old always-available combat cards (Dash, Aimed Shot, Quick Reload).
## They are hidden for now; the earned hand of cards (hand_cards.gd) replaces them.
const SHOW_COMBAT_CARDS := false
const CARD_GAP := 12.0
var card_row: Control
var cards: Array = []  # ActionCard nodes
var _last_card := ""  # kind of the card played this turn (for its USED stamp)
const DeckPile := preload("res://scripts/deck_pile.gd")
const HandPopup := preload("res://scripts/hand_popup.gd")
var deck: Control  # face-down deck of earned cards (deck_pile.gd)
var _hand_popup: CanvasLayer  # the opened hand, while it is up
var ammo_icons: Control
const AMMO_SCALE := 3.0  # how much bigger the ammo graphic is drawn than its 22 px design
const PROFILE_SIZE := 80.0  # profile picture button in the top-left corner
const HUD_X := 12.0 + PROFILE_SIZE + 8.0  # health, ammo and info lines start right of the profile picture
var door_buttons := {}  # "Open" / "Kick" / "Close" -> Button
var _msg_time := 0.0


func _process(delta: float) -> void:
	_check_game_over()
	renderer.update_canopy_fade(player.position, delta)
	renderer.update_roof_fade(player.position, delta)
	for op in get_tree().get_nodes_in_group("openings"):
		(op as OpeningNode).update_badge(player.global_position)
	_update_ammo()
	_update_combat_status()
	_update_combat_cards()
	# An opened door drops its selection marker (its Close button still works when you stand next to it).
	var sel := player.interact as OpeningNode
	if sel != null and sel.kind == "door" and sel.is_open:
		player.set_interact(null)
	if stick != null:
		player.joystick = stick.output
	if fight_btn != null:
		fight_btn.disabled = combat == null or combat.active
	if end_combat_btn != null:
		end_combat_btn.visible = combat != null and combat.active
		var can_end := combat != null and combat.can_player_end()
		end_combat_btn.disabled = not can_end
		end_combat_btn.tooltip_text = "Leave combat (nobody is attacking you)" if can_end \
				else "Can't leave while an enemy is attacking you"
	if skip_btn != null:
		skip_btn.visible = combat != null and combat.active
		if _action_panel != null:
			_action_panel.visible = false  # the old box is empty now that the combat buttons are round
		skip_btn.disabled = not (combat != null and combat.is_player_turn() and not player.is_running())
	if untarget_btn != null:
		untarget_btn.disabled = not (is_instance_valid(player.target) or is_instance_valid(player.interact))
	if weapon_icon != null:
		weapon_icon.queue_redraw()  # follows the equipped weapon
		weapon_btn.tooltip_text = "%s\nClick to change weapon" % Weapons.tooltip(Player.weapon)
	if shoot_btn != null:
		var my_go := not player.turn_mode or (player.my_turn and player.action_left)
		var fists := Player.weapon == "none"
		var armed := fists or Weapons.is_ranged(Player.weapon)
		# A gun fires any time (at the target, else straight ahead); a punch needs a target.
		var can_shoot := armed and my_go and (not fists or is_instance_valid(player.target))
		if fists and can_shoot and player.turn_mode and not player.in_punch_reach(player.target):
			can_shoot = false  # in combat a punch needs the target right next to you
		var walled: bool = not fists and player.in_wall_cover()
		if walled:
			can_shoot = false  # hiding behind a wall: no line to shoot along
		shoot_btn.disabled = not can_shoot
		var verb := "Punch" if fists else "Shoot at"
		shoot_btn.tooltip_text = (("%s the target (hold to keep going)" % verb) if is_instance_valid(player.target) \
				else "Fire straight ahead (hold to keep going)") if can_shoot else (
				"Wait for your turn" if not my_go else
				"Behind a wall: run to another spot to shoot" if walled else
				"Target an NPC, barrel or crate first" if not is_instance_valid(player.target) else
				"Move next to the target to punch" if fists else "Pick a gun first")
		if not can_shoot:
			player.fire_held = false  # a disabled button never sends button_up
	if ammo_icons != null:
		var gun := Weapons.is_ranged(Player.weapon)
		var go := not player.turn_mode or (player.my_turn and player.action_left)
		var can_reload := gun and go and not player.is_reloading() and player.ammo() < player.mag(Player.weapon)
		ammo_icons.tooltip_text = "Click to reload%s" % (" (uses your action)" if player.turn_mode else "") if can_reload else (
				"" if not gun else
				"Wait for your turn" if not go else
				"Already reloading" if player.is_reloading() else "Magazine is full")
	if _msg_time > 0.0:
		_msg_time -= delta
		message_label.modulate.a = clampf(_msg_time / 0.5, 0.0, 1.0)  # fade over the last half second
	var door := _active_door()
	if door == null:
		door_prompt.text = ""
	elif door.is_open:
		door_prompt.text = ""
	else:
		door_prompt.text = "Closed door nearby"
	_update_door_buttons(door)


## The door the Open / Kick / Close buttons act on: a selected door the player has walked up to,
## otherwise the nearest door within reach (null when none).
func _active_door() -> OpeningNode:
	var sel: OpeningNode = player.interact as OpeningNode if is_instance_valid(player.interact) else null
	if player.is_at_interact() and sel != null and sel.kind == "door":
		return sel
	return renderer.nearest_door(player.position)


## Close shows only beside an open door; Open and Kick only beside a closed one.
## Open also shows beside a targeted, unopened crate, since it opens crates too.
func _update_door_buttons(door: OpeningNode) -> void:
	if door_buttons.is_empty():
		return
	var near_closed := door != null and not door.is_open
	var crate := _reachable_container()
	var crate_ready := crate != null and not crate.opened
	door_buttons["Open"].visible = near_closed or crate_ready
	door_buttons["Kick"].visible = near_closed and door.kind == "door" and _can_enter(door)


## The chest, crate or barrel the Open button acts on: the targeted one if the player is next to
## it, otherwise the nearest unopened one within reach (null when none).
func _reachable_container() -> PropNode:
	var t: PropNode = player.target as PropNode if is_instance_valid(player.target) else null
	if t != null and t.is_openable() and _crate_in_reach(t):
		return t
	var best: PropNode = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("containers"):
		var pn := n as PropNode
		if pn == null or not pn.is_openable() or pn.opened or not _crate_in_reach(pn):
			continue
		var d := player.global_position.distance_to(pn.global_position)
		if d < best_d:
			best_d = d
			best = pn
	return best


## Close enough to a crate to open it by hand.
func _crate_in_reach(crate: PropNode) -> bool:
	return player.global_position.distance_to(crate.global_position) <= crate._radius() + 30.0


## Short message in the middle of the screen (e.g. what was found in a crate); fades after a moment.
func _flash_message(text: String) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	_msg_time = 2.0


func _update_ammo() -> void:
	if ammo_label == null:
		return
	var t := player.target
	if is_instance_valid(t) and t is PropNode:
		var pn := t as PropNode
		var state := ""
		if pn.is_openable():
			state = "   (opened)" if pn.opened else ("   (use Open)" if _crate_in_reach(pn) else "")
		if pn.kind == "trunk":
			target_label.text = "Target: %s%s" % [pn.label(), state]
		else:
			target_label.text = "Target: %s   HP %d / %d%s" % [pn.label(), pn.hp, pn.max_hp(), state]
	elif is_instance_valid(t):
		target_label.text = "Target: %s   HP %d / %d" % [t.get("npc_name"), t.get("hp"), t.get("max_hp")]
	else:
		target_label.text = ""
	var o := player.interact
	if is_instance_valid(o):
		var name_txt := "Door" if o.get("kind") == "door" else "Window"
		if not player.is_at_interact():
			interact_label.text = "Selected: %s   (%s)" % [name_txt, "walking there..." if player.is_walking() else "can't reach it"]
		elif o.get("kind") == "door":
			interact_label.text = "Selected: Door   (%s)" % ("open" if o.get("is_open") else "closed")
		else:
			interact_label.text = "Selected: Window"
	else:
		interact_label.text = ""
	var w := Player.weapon
	if not Weapons.is_ranged(w):
		ammo_label.text = ""
		reload_bar.visible = false
		if ammo_icons != null:
			ammo_icons.visible = false
		return
	var txt := "%s   Ammo %d / %d" % [Weapons.label(w), player.ammo(), player.mag(w)]
	if player.is_reloading():
		txt += "   Reloading..."
	elif player.ammo() < player.mag(w):
		txt += ""
	ammo_label.text = txt
	reload_bar.visible = player.is_reloading()
	reload_bar.value = player.reload_progress()
	if ammo_icons != null:
		ammo_icons.visible = true
		ammo_icons.queue_redraw()


## Loaded rounds are bright, spent ones dark. While reloading, the missing rounds fill in one by one with the progress.
func _draw_ammo_icons() -> void:
	var w := Player.weapon
	var mag := player.mag(w)
	if mag <= 0:
		return
	var loaded := player.ammo()
	if player.is_reloading():
		# Rounds still in the gun stay lit; only the missing slots fill in as the reload progresses.
		var have := player.ammo()
		loaded = have + int(floor(player.reload_progress() * float(mag - have)))
	var c := ammo_icons
	# Drawn on a small design grid, then scaled up and centred in the box above the Shoot button.
	var content_w := 22.0 if w == "pistol" else float(mag) * 15.0 - 3.0 if w == "flintlock" else float(mag) * ((7.0 if w == "shotgun" else 5.0) + 3.0) - 3.0
	var origin := Vector2((c.size.x - content_w * AMMO_SCALE) * 0.5, (c.size.y - 22.0 * AMMO_SCALE) * 0.5)
	c.draw_set_transform(origin, 0.0, Vector2(AMMO_SCALE, AMMO_SCALE))
	if w == "pistol":
		# Revolver cylinder seen end-on: one chamber per round.
		var cen := Vector2(11, 11)
		c.draw_circle(cen, 10.5, Color(0.22, 0.22, 0.26))
		c.draw_arc(cen, 10.5, 0.0, TAU, 24, Color(0.05, 0.05, 0.06), 1.5)
		c.draw_circle(cen, 2.0, Color(0.12, 0.12, 0.14))
		for i in mag:
			var a := -PI * 0.5 + TAU * float(i) / float(mag)
			var p := cen + Vector2(cos(a), sin(a)) * 6.3
			if i < loaded:
				c.draw_circle(p, 2.6, Color("d4a640"))  # brass case head
				c.draw_circle(p, 1.0, Color("8a6a24"))  # primer
			else:
				c.draw_circle(p, 2.6, Color(0.05, 0.05, 0.06))  # empty chamber
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	if w == "flintlock":
		# Round lead balls: dull grey sphere with a soft highlight; an empty slot is a dark ring.
		for i in mag:
			var p := Vector2(float(i) * 15.0 + 6.0, 11.0)
			if i < loaded:
				c.draw_circle(p, 6.0, Color(0.16, 0.17, 0.2))  # dark edge
				c.draw_circle(p, 5.0, Color(0.46, 0.48, 0.53))  # lead
				c.draw_circle(p + Vector2(-1.5, -1.5), 1.8, Color(0.75, 0.77, 0.82))  # highlight
			else:
				c.draw_circle(p, 6.0, Color(0.0, 0.0, 0.0, 0.35))
				c.draw_arc(p, 6.0, 0.0, TAU, 20, Color(0.6, 0.6, 0.6, 0.5), 1.0)
		c.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	# Rifle rounds / shotgun shells standing in a row.
	var shell := w == "shotgun"
	var body := Color("b8322a") if shell else Color("d4a640")
	var tip := Color("d4b050") if shell else Color("b07840")
	var bw := 7.0 if shell else 5.0
	for i in mag:
		var x := float(i) * (bw + 3.0)
		var r := Rect2(x, 3, bw, 16)
		if i < loaded:
			c.draw_rect(Rect2(x, 3 + (0 if shell else 5), bw, 16 - (0 if shell else 5)), body)
			if shell:
				c.draw_rect(Rect2(x, 15, bw, 4), tip)  # brass base
			else:
				c.draw_colored_polygon(PackedVector2Array([Vector2(x, 8), Vector2(x + bw, 8), Vector2(x + bw * 0.5, 2)]), tip)  # bullet
		else:
			c.draw_rect(r, Color(0.0, 0.0, 0.0, 0.35))
			c.draw_rect(r, Color(0.6, 0.6, 0.6, 0.5), false, 1.0)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)


## Where the player lands after kicking `door` in: through the doorway to the far side.
func _kick_dest(door: OpeningNode) -> Vector2:
	var far_side := door.to_global(-door.to_local(player.global_position))
	return door.approach_point(far_side, KICK_ENTER_DIST)


## Spot `gap` px past the door's wall face, on the far side from the player.
func _inside_point(door: OpeningNode, gap: float) -> Vector2:
	return door.approach_point(door.to_global(-door.to_local(player.global_position)), gap)


## True when there is room behind the door for the player to step in: the landing spot and the
## space just inside the doorway are clear of walls, solid props and water.
func _can_enter(door: OpeningNode) -> bool:
	var space := player.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = 11.0  # a little over the player's 10 px body
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = player.collision_mask
	q.exclude = [player.get_rid()]
	# Sample the space behind the door: inside the doorway, the landing spot, and out to KICK_ROOM.
	for gap in [20.0, KICK_ENTER_DIST, (KICK_ENTER_DIST + KICK_ROOM) * 0.5, KICK_ROOM]:
		var p := _inside_point(door, gap)
		q.transform = Transform2D(0.0, p)
		if not space.intersect_shape(q, 1).is_empty() or player._in_water(p):
			return false
	return true


## E opens/closes the nearest door, K kicks a closed one open (only when there is room to step in).
## `only` limits the action: "open" never closes, "close" never opens.
func _use_door(kick: bool, only: String = "") -> void:
	# Open (or E) on a targeted crate the player is standing next to opens it.
	var crate := _reachable_container()
	if not kick and only != "close" and crate != null:
		if crate.opened:
			_flash_message("Already opened")
			return
		if crate.locked:
			if player.keys <= 0:
				_flash_message("Locked - find a key")
				return
			player.keys -= 1
			crate.unlock()  # the key is used up; the "Found" message below follows
		var found := crate.open_container(player.global_position)
		if found == "water":
			_flash_message("The %s is full of water" % crate.label().to_lower())
		else:
			_flash_message("Found: %s" % MapData.NPC_LOOT.get(found, found) if found != "none" else "The %s is empty" % crate.label().to_lower())
		return
	var door := _active_door()  # a selected door the player walked up to beats the nearest one
	if door == null:
		return
	if door.is_open:
		if kick or only == "open" or door.blocks_point(player.position):
			return  # can't close a door on yourself
		door.close()
	else:
		if only == "close":
			return
		if kick and door.kind == "door" and not _can_enter(door):
			_flash_message("No room to burst in here")
			return
		door.open(player.position, kick)
		if kick and door.is_open:  # (windows don't open, so there is nothing to burst through)
			# Burst in: step through the doorway to the far side at the same time.
			player.slide_to(_kick_dest(door))
			_ambush_from_kick(door)
	var reach := door.width + 24.0
	player.refresh_nav(Rect2(door.position - Vector2(reach, reach), Vector2(reach, reach) * 2.0))


func _ready() -> void:
	MapData.ensure_loaded()
	var data := MapData.working

	renderer = MapRenderer.new()
	renderer.physics_enabled = true
	add_child(renderer)
	renderer.build(data)
	_bounty_total = get_tree().get_nodes_in_group("bounty").size()
	for p in data["polygons"]:
		if str(p["type"]) == "destination" and (p["points"] as PackedVector2Array).size() >= 3:
			_destinations.append(p)

	player = Player.new()
	player.map_size = data["size"]
	player.position = data["spawn"]
	add_child(player)

	var vulture := VultureShadow.new()
	vulture.map_size = data["size"]
	add_child(vulture)

	var layer := CanvasLayer.new()
	add_child(layer)
	door_prompt = Label.new()
	door_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	door_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	door_prompt.offset_top = -60
	door_prompt.add_theme_font_size_override("font_size", 18)
	door_prompt.add_theme_color_override("font_shadow_color", Color.BLACK)
	door_prompt.add_theme_constant_override("shadow_offset_x", 1)
	door_prompt.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(door_prompt)
	message_label = Label.new()
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message_label.offset_top = -100
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	message_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	message_label.add_theme_constant_override("shadow_offset_x", 1)
	message_label.add_theme_constant_override("shadow_offset_y", 1)
	message_label.modulate.a = 0.0
	layer.add_child(message_label)
	combat = Combat.new()
	combat.player = player
	add_child(combat)
	combat.message.connect(_flash_message)
	player.notice.connect(_flash_message)
	player.weapon_picked.connect(_show_new_weapon)
	combat.changed.connect(_refresh_combat_panel)
	_build_combat_panel(layer)
	_build_combat_cards(layer)
	_build_hand(layer)
	_build_hat_picker(layer)
	_minimap = Minimap.create(data)  # overview map, top-right
	layer.add_child(_minimap)
	_build_weapon_bar(layer)
	_build_action_bar(layer)
	_build_health_bar(layer)
	_build_joystick(layer)
	if not _destinations.is_empty():
		var goal_coins := 0
		for d in _destinations:
			goal_coins = maxi(goal_coins, int(d.get("coins", 0)))
		_flash_message("Objective: reach the destination" + (" with %d coins" % goal_coins if goal_coins > 0 else ""))


## On-screen joystick at the bottom left; its push drives player.joystick (same as the arrow keys).
func _build_joystick(layer: CanvasLayer) -> void:
	stick = TouchStick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.offset_left = STICK_MARGIN_X
	stick.offset_bottom = -STICK_MARGIN_Y
	stick.offset_top = -STICK_MARGIN_Y - stick.custom_minimum_size.y
	stick.offset_right = STICK_MARGIN_X + stick.custom_minimum_size.x
	layer.add_child(stick)


## Weapon HUD: one button at the bottom right showing the equipped weapon (fists at the start).
## Clicking it opens the weapon wheel, which pauses the game.
func _build_weapon_bar(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	layer.add_child(panel)
	# Weapon button, with Start combat / Untarget stacked beside it (they are added in _build_action_bar).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	_top_col = VBoxContainer.new()
	_top_col.add_theme_constant_override("separation", 4)
	weapon_btn = Button.new()
	weapon_btn.focus_mode = Control.FOCUS_NONE  # keep keys for walking / shooting
	weapon_btn.custom_minimum_size = Vector2(96, 96)
	weapon_btn.pressed.connect(_open_weapon_wheel)
	row.add_child(weapon_btn)
	row.add_child(_top_col)
	weapon_icon = Control.new()
	weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	weapon_icon.draw.connect(func() -> void:
		Weapons.draw_icon_at(weapon_icon, Player.weapon, weapon_icon.size * 0.5 - Vector2(0, 6), 62.0)
		var f := ThemeDB.fallback_font
		weapon_icon.draw_string(f, Vector2(0, weapon_icon.size.y - 6), Weapons.label(Player.weapon), HORIZONTAL_ALIGNMENT_CENTER, weapon_icon.size.x, 13, Color(1, 1, 1, 0.9)))
	weapon_btn.add_child(weapon_icon)
	# Top-right, just left of the minimap.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	var map_left := _minimap.offset_left if _minimap != null and _minimap.offset_left < 0.0 else -222.0
	panel.offset_right = map_left - 8.0
	panel.offset_top = 12


## A kicked-in door surprises the hostile NPCs inside the building it belongs to (the roof the
## door sits on or beside). If there are any, combat starts at once with them caught off guard.
func _ambush_from_kick(door: OpeningNode) -> void:
	if combat == null or combat.active:
		return
	var surprised: Array = []
	for roof in MapData.working.get("roofs", []):
		var pts: PackedVector2Array = roof["points"]
		if pts.size() < 3 or not _door_on_roof(door.global_position, pts):
			continue
		for n in get_tree().get_nodes_in_group("npcs"):
			var npc := n as NpcNode
			if npc != null and npc.hp > 0 and npc.disposition == "hostile" and not surprised.has(npc) \
					and Geometry2D.is_point_in_polygon(npc.global_position, pts):
				surprised.append(npc)
	if not surprised.is_empty():
		combat.start_ambush(surprised)


## True when `p` is inside the roof outline or within a door's thickness of its edge.
func _door_on_roof(p: Vector2, pts: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(p, pts):
		return true
	for i in pts.size():
		var closest := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[(i + 1) % pts.size()])
		if closest.distance_to(p) <= 32.0:
			return true
	return false


## Opens the radial weapon picker over the game and pauses everything until it is closed.
func _open_weapon_wheel() -> void:
	if _game_over or _wheel_layer != null:
		return
	player.fire_held = false
	_wheel_layer = CanvasLayer.new()
	_wheel_layer.layer = 20
	_wheel_layer.process_mode = Node.PROCESS_MODE_ALWAYS  # stays clickable while paused
	add_child(_wheel_layer)
	var wheel := WeaponWheel.new()
	_wheel_layer.add_child(wheel)
	wheel.setup(player, Weapons.PLAYER_CHOICES)
	wheel.chosen.connect(func(key: String) -> void:
		player.set_weapon(key)
		_close_weapon_wheel())
	wheel.closed.connect(_close_weapon_wheel)
	wheel.info_requested.connect(func(key: String) -> void:
		wheel.info_open = true  # the specs card sits over the wheel; the game stays paused
		NewWeaponPopup.show_for(self, key, true).closed.connect(func() -> void:
			if is_instance_valid(wheel):
				wheel.info_open = false))
	get_tree().paused = true


func _close_weapon_wheel() -> void:
	if _wheel_layer == null:
		return
	_wheel_layer.queue_free()
	_wheel_layer = null
	if not _game_over:
		get_tree().paused = false


## A gun was picked up off the ground: pause and show its stats until the player continues.
func _show_new_weapon(key: String) -> void:
	if _game_over or not Weapons.is_ranged(key):
		return
	get_tree().paused = true
	NewWeaponPopup.show_for(self, key).closed.connect(func() -> void:
		if not _game_over:
			get_tree().paused = false)


## Win: every bounty NPC on the map is dead. A map without bounties is won once no hostile NPC
## is left alive (after at least one hostile has been seen, so a peaceful map never "ends").
func _check_game_over() -> void:
	if _game_over:
		return
	var won := false
	var why := ""
	if not _destinations.is_empty():
		# The map has a destination: walking into one (with its requirements met) is the only way to win.
		_check_destinations()
		return
	if _bounty_total > 0:
		won = get_tree().get_nodes_in_group("bounty").is_empty()
		why = "Every bounty has been collected." if _bounty_total > 1 else "The bounty has been collected."
	else:
		var hostiles := 0
		for n in get_tree().get_nodes_in_group("npcs"):
			# Animals (AnimalNode extends NpcNode) don't count: wildlife doesn't block the win.
			if n is NpcNode and not (n is AnimalNode) and (n as NpcNode).disposition == "hostile" and (n as NpcNode).hp > 0:
				hostiles += 1
		if hostiles > 0:
			_saw_hostile = true
		won = _saw_hostile and hostiles == 0
		why = "All hostiles have been defeated."
	if won:
		_show_game_over(why)


## Destination areas (polygons of type "destination"): finishing needs the player inside one while
## the purse holds its coins and, if it asks for that, every bounty is dead. Otherwise a short
## message says what is missing (at most every 2.5 seconds, so standing inside doesn't spam it).
func _check_destinations() -> void:
	var inside: Dictionary = {}
	for d in _destinations:
		if Geometry2D.is_point_in_polygon(player.global_position, d["points"]):
			inside = d
			var need_coins := int(d.get("coins", 0))
			var bounties_left := get_tree().get_nodes_in_group("bounty").size() if bool(d.get("bounties", false)) else 0
			if player.gold >= need_coins and bounties_left == 0:
				_win_title = "MAP COMPLETE"
				_show_game_over("You reached the destination." if need_coins <= 0 else "You reached the destination with %d coins." % player.gold)
				return
	if inside.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now < _dest_hint_until:
		return
	_dest_hint_until = now + 2500
	var missing: Array = []
	if player.gold < int(inside.get("coins", 0)):
		missing.append("%d more coins" % (int(inside["coins"]) - player.gold))
	var left := get_tree().get_nodes_in_group("bounty").size()
	if bool(inside.get("bounties", false)) and left > 0:
		missing.append("%d bount%s to collect" % [left, "y" if left == 1 else "ies"])
	_flash_message("Can't leave yet: need " + " and ".join(missing))


func _show_game_over(why: String) -> void:
	_game_over = true
	# Started from a location on the country map: finishing it unlocks the next one.
	var from_country := CountryMap.pending_id >= 0
	if from_country:
		CountryMap.mark_complete(CountryMap.pending_id)
	if combat != null:
		combat.end_combat("")
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS  # stays clickable while the game is paused
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.11, 0.07, 0.97)
	style.border_color = Color(0.85, 0.65, 0.25)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = _win_title if _win_title != "" else ("BOUNTY COLLECTED" if _bounty_total > 0 else "VICTORY")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	box.add_child(title)
	var info := Label.new()
	info.text = why
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var again := Button.new()
	again.text = "Play again"
	again.custom_minimum_size = Vector2(130, 40)
	again.pressed.connect(func() -> void:
		get_tree().paused = false
		get_tree().reload_current_scene())
	row.add_child(again)
	var back := Button.new()
	back.text = "Back to map" if from_country else "Back to editor"
	back.custom_minimum_size = Vector2(130, 40)
	back.pressed.connect(func() -> void:
		get_tree().paused = false
		if from_country:
			CountryMap.open_map_screen = true
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/map_editor.tscn"))
	row.add_child(back)
	get_tree().paused = true  # the world stops; only the buttons above still work


## Turn order panel (left side), shown only during turn-based combat: round number, everyone's
## d20 initiative roll in turn order with the current turn marked, what you have left this turn,
## and an End turn button.
func _build_combat_panel(layer: CanvasLayer) -> void:
	# Red frame around the whole screen while turn-based combat is on.
	combat_border = Panel.new()
	combat_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	combat_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combat_border.visible = false
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.set_border_width_all(6)
	border_style.border_color = Color(0.85, 0.15, 0.12, 0.85)
	combat_border.add_theme_stylebox_override("panel", border_style)
	layer.add_child(combat_border)

	combat_panel = PanelContainer.new()
	combat_panel.visible = false
	# Left edge, below the HP / ammo / target lines.
	combat_panel.position = Vector2(12, 146)
	# Compact: half the size of the first version (small fonts, tight margins).
	combat_panel.custom_minimum_size.x = 120
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.08, 0.88)
	style.border_color = Color(0.85, 0.3, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(4)
	combat_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(combat_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	combat_panel.add_child(box)
	combat_title = Label.new()
	combat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_title.add_theme_font_size_override("font_size", COMBAT_FONT)
	combat_title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	box.add_child(combat_title)
	var sub := Label.new()
	sub.text = "Initiative (d20)"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", COMBAT_FONT - 2)
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	box.add_child(sub)
	combat_list = VBoxContainer.new()
	combat_list.add_theme_constant_override("separation", 0)
	box.add_child(combat_list)
	combat_status = Label.new()
	combat_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combat_status.add_theme_font_size_override("font_size", COMBAT_FONT)
	box.add_child(combat_status)
	end_turn_btn = Button.new()
	end_turn_btn.text = "End turn"
	end_turn_btn.focus_mode = Control.FOCUS_NONE
	end_turn_btn.add_theme_font_size_override("font_size", COMBAT_FONT)
	end_turn_btn.custom_minimum_size = Vector2(0, 20)
	end_turn_btn.pressed.connect(func() -> void: combat.end_player_turn())
	box.add_child(end_turn_btn)


## Three special-action cards at the bottom centre, half tucked below the screen edge; hover to
## lift one fully and read it, click to play it. Shown only during combat.
func _build_combat_cards(layer: CanvasLayer) -> void:
	card_row = Control.new()
	card_row.visible = false
	card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := COMBAT_CARDS.size() * ActionCard.SIZE.x + (COMBAT_CARDS.size() - 1) * CARD_GAP
	card_row.anchor_left = 0.5
	card_row.anchor_right = 0.5
	card_row.anchor_top = 1.0
	card_row.anchor_bottom = 1.0
	card_row.offset_left = -w * 0.5
	card_row.offset_right = w * 0.5
	layer.add_child(card_row)
	for i in COMBAT_CARDS.size():
		var d: Dictionary = COMBAT_CARDS[i]
		var card := ActionCard.new()
		card.kind = d["kind"]
		card.title = d["title"]
		card.desc = d["desc"]
		card.accent = d["accent"]
		card.rest_y = -ActionCard.SIZE.y * 0.5  # top half on screen, bottom half hidden
		card.position = Vector2(i * (ActionCard.SIZE.x + CARD_GAP), card.rest_y)
		card.played.connect(_on_card_played)
		card_row.add_child(card)
		cards.append(card)


## The player's hand: cards earned with XP (one per 5 XP, see hand_cards.gd), shown along the bottom
## of the screen just left of the combat cards, as a face-down deck. Click it to open the hand.
func _build_hand(layer: CanvasLayer) -> void:
	deck = DeckPile.new()
	deck.rest_y = -DeckPile.SIZE.y * 0.6  # 60% of the deck shows, the rest is below the screen edge
	# With the combat cards hidden the deck sits in the middle; otherwise just left of them.
	var combat_w := (COMBAT_CARDS.size() * ActionCard.SIZE.x + (COMBAT_CARDS.size() - 1) * CARD_GAP) if SHOW_COMBAT_CARDS else -(CARD_GAP * 4.0 + ActionCard.SIZE.x)
	# The deck moves by `position` (hover lift), so it sits in a zero-size holder anchored to the
	# bottom centre, like the combat card row, instead of being anchored itself.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	layer.add_child(holder)
	deck.position = Vector2(-combat_w * 0.5 - CARD_GAP * 2.0 - DeckPile.SIZE.x, deck.rest_y)
	deck.tooltip_text = "Your cards (1 per 5 XP). Click to open."
	deck.pressed.connect(_open_hand)
	holder.add_child(deck)
	deck.set_count(player.hand.size())
	player.hand_changed.connect(func() -> void: deck.set_count(player.hand.size()))
	player.card_drawn.connect(func(kind: String) -> void:
		_flash_message("New card drawn! (%d in your deck)" % player.hand.size()))


## A round, initially hidden combat button (Skip turn / End combat), styled like the door buttons.
func _round_combat_button(text: String, font_col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", font_col)
	b.add_theme_color_override("font_disabled_color", Color(font_col, 0.4))
	for st in ["normal", "hover", "pressed", "disabled"]:
		var fill := Color(0.18, 0.14, 0.08, 0.7) if st != "pressed" else Color(0.5, 0.38, 0.15, 0.85)
		if st == "disabled":
			fill = Color(0.1, 0.1, 0.1, 0.45)
		b.add_theme_stylebox_override(st, _round_style(fill, DOOR_BTN / 2.0, Color(0.9, 0.78, 0.4, 0.85 if st != "disabled" else 0.35)))
	b.visible = false  # shown in combat by _process
	return b


## Puts a round button on the circle around the Shoot button, at `angle` degrees (0 = right, 90 = down).
func _place_round_button(b: Button, angle: float, shoot_c: Vector2) -> void:
	var centre: Vector2 = shoot_c + Vector2.from_angle(deg_to_rad(angle)) * (70.0 + DOOR_BTN * 0.5 + 8.0)
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = centre.x - DOOR_BTN * 0.5
	b.offset_right = centre.x + DOOR_BTN * 0.5
	b.offset_top = centre.y - DOOR_BTN * 0.5
	b.offset_bottom = centre.y + DOOR_BTN * 0.5


## Opens the deck: the cards turn face up over the paused game until it is closed.
func _open_hand() -> void:
	if _game_over or _wheel_layer != null or _hand_popup != null or player.hand.is_empty():
		return
	player.fire_held = false
	_hand_popup = HandPopup.new()
	add_child(_hand_popup)
	_hand_popup.setup(player)
	_hand_popup.closed.connect(func() -> void:
		_hand_popup = null
		if not _game_over:
			get_tree().paused = false)
	get_tree().paused = true


func _on_card_played(kind: String) -> void:
	if not player.play_card(kind):
		return
	_last_card = kind
	for d in COMBAT_CARDS:
		if d["kind"] == kind:
			_flash_message("%s!" % d["title"])


## Per frame: show the cards in combat, grey out those that can't be played right now, and lift
## the door prompt / messages above them.
func _update_combat_cards() -> void:
	if card_row == null:
		return
	var on := combat != null and combat.active
	var cards_shown := on and SHOW_COMBAT_CARDS
	card_row.visible = cards_shown
	if combat_border != null:
		combat_border.visible = on
	door_prompt.offset_top = -60.0 - (90.0 if cards_shown else 0.0)
	message_label.offset_top = -100.0 - (90.0 if cards_shown else 0.0)
	if not on:
		return
	if not player.card_played:
		_last_card = ""
	for c in cards:
		var card: ActionCard = c
		card.set_state(player.can_play_card(card.kind), player.card_played and card.kind == _last_card)


func _refresh_combat_panel() -> void:
	if combat_panel == null:
		return
	combat_panel.visible = combat.active
	if not combat.active:
		return
	combat_title.text = "COMBAT - Round %d" % combat.round_num
	for c in combat_list.get_children():
		combat_list.remove_child(c)
		c.queue_free()
	for i in combat.order.size():
		var e: Dictionary = combat.order[i]
		var current: bool = i == combat.turn
		var row := Label.new()
		var who := str(e["name"])
		var node = e["node"]  # untyped: may be an NPC freed this frame
		if not is_instance_valid(node):
			continue
		if node is NpcNode:
			who += "  (HP %d)" % (node as NpcNode).hp
		elif node == player:
			who += "  (HP %d)" % player.hp
		row.text = "%s %2d   %s" % [">" if current else "  ", int(e["roll"]), who]
		var col := Color(0.6, 0.85, 1.0) if node == player else Color(1.0, 0.6, 0.55)
		if current:
			col = Color(1.0, 0.88, 0.35)
		row.add_theme_color_override("font_color", col)
		row.add_theme_font_size_override("font_size", COMBAT_FONT)
		combat_list.add_child(row)
	_update_combat_status()


## Per-frame part of the panel: what the player still has this turn.
func _update_combat_status() -> void:
	if combat_status == null or combat == null or not combat.active:
		return
	_hp_refresh -= get_process_delta_time()
	if _hp_refresh <= 0.0:
		_hp_refresh = 0.3
		_refresh_combat_panel()  # keeps the HP figures in the list current
		return
	if combat.is_player_turn():
		var act := "action used"
		if player.action_left:
			act = "action ready" if player.extra_actions == 0 else "%d actions ready" % (player.extra_actions + 1)
		if player.is_running():
			combat_status.text = "Your turn\nrunning..."
		else:
			var mv := "click a marked spot to run (uses your turn)" if player.has_spots() else "no cover in reach"
			combat_status.text = "Your turn\n%s, %s" % [mv, act]
		end_turn_btn.disabled = false
	else:
		combat_status.text = "%s's turn..." % combat.current_name()
		end_turn_btn.disabled = true


## Open / Kick / Close buttons at the bottom right, left of the weapon column.
func _build_action_bar(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	_action_panel = panel
	# Open / Kick / Close: round buttons fanned out to the left of the Shoot circle.
	# [label, kick?, only, angle in degrees (0 = right, 90 = down)]
	var defs := [["Open", false, "open", 210.0], ["Kick", true, "", 165.0]]
	var shoot_c := Vector2(-(STICK_MARGIN_X + 80.0), -(STICK_MARGIN_Y + 80.0))  # Shoot circle centre, from the bottom-right corner
	for d in defs:
		var b := Button.new()
		b.text = d[0]
		b.focus_mode = Control.FOCUS_NONE  # keep keys for walking / shooting
		b.add_theme_font_size_override("font_size", 15)
		for st in ["normal", "hover", "pressed", "disabled"]:
			var fill := Color(0.18, 0.14, 0.08, 0.7) if st != "pressed" else Color(0.5, 0.38, 0.15, 0.85)
			b.add_theme_stylebox_override(st, _round_style(fill, DOOR_BTN / 2.0, Color(0.9, 0.78, 0.4, 0.85)))
		b.pressed.connect(_use_door.bind(d[1], d[2]))
		b.visible = false  # shown by _update_door_buttons() when a matching door is near
		layer.add_child(b)
		var centre: Vector2 = shoot_c + Vector2.from_angle(deg_to_rad(float(d[3]))) * (70.0 + DOOR_BTN * 0.5 + 8.0)
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.anchor_top = 1.0
		b.anchor_bottom = 1.0
		b.offset_left = centre.x - DOOR_BTN * 0.5
		b.offset_right = centre.x + DOOR_BTN * 0.5
		b.offset_top = centre.y - DOOR_BTN * 0.5
		b.offset_bottom = centre.y + DOOR_BTN * 0.5
		door_buttons[d[0]] = b
	# Shoot: fires at the current target; holding it keeps firing at the weapon's rate.
	# Disabled (in _process) while there is no target or no gun selected.
	# Drawn ammo just above the Shoot button: a revolver cylinder for the pistol, a row of rounds otherwise.
	ammo_icons = Control.new()
	# Clicking the bullets reloads now. In a fight that uses the turn's action (the Quick Reload card doesn't).
	ammo_icons.mouse_filter = Control.MOUSE_FILTER_STOP
	ammo_icons.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ammo_icons.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			player.reload())
	# Ammo sits just above the round Shoot button (bottom right, mirroring the joystick).
	var ammo_h := 22.0 * AMMO_SCALE + 6.0
	ammo_icons.visible = false
	ammo_icons.draw.connect(_draw_ammo_icons)
	layer.add_child(ammo_icons)
	ammo_icons.anchor_left = 1.0
	ammo_icons.anchor_right = 1.0
	ammo_icons.anchor_top = 1.0
	ammo_icons.anchor_bottom = 1.0
	ammo_icons.offset_left = -(STICK_MARGIN_X + 120.0)  # 30 px right of the Shoot circle's centre line
	ammo_icons.offset_right = -(STICK_MARGIN_X - 20.0)
	ammo_icons.offset_bottom = -(STICK_MARGIN_Y + 150.0 + 4.0)
	ammo_icons.offset_top = ammo_icons.offset_bottom - ammo_h
	shoot_btn = Button.new()
	shoot_btn.focus_mode = Control.FOCUS_NONE
	shoot_btn.custom_minimum_size = Vector2(140, 140)  # same size as the joystick ring
	# Target / crosshair icon instead of text.
	var target_icon := Control.new()
	target_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target_icon.draw.connect(func() -> void:
		var c := target_icon.size * 0.5
		var tint := Color(0.7, 0.45, 0.4, 0.6) if shoot_btn.disabled else Color(1.0, 0.55, 0.45)
		target_icon.draw_arc(c, 24.0, 0.0, TAU, 48, tint, 3.0, true)
		target_icon.draw_arc(c, 11.0, 0.0, TAU, 32, tint, 2.5, true)
		target_icon.draw_circle(c, 3.0, tint)
		for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:  # ticks crossing the outer ring
			target_icon.draw_line(c + dir * 19.0, c + dir * 32.0, tint, 3.0))
	shoot_btn.add_child(target_icon)
	shoot_btn.draw.connect(target_icon.queue_redraw)  # follows the enabled / disabled look
	shoot_btn.add_theme_font_size_override("font_size", 24)
	shoot_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	shoot_btn.add_theme_color_override("font_disabled_color", Color(0.7, 0.45, 0.4, 0.6))
	shoot_btn.add_theme_stylebox_override("normal", _round_style(Color(0.35, 0.1, 0.08, 0.6)))
	shoot_btn.add_theme_stylebox_override("hover", _round_style(Color(0.45, 0.13, 0.1, 0.7)))
	shoot_btn.add_theme_stylebox_override("pressed", _round_style(Color(0.7, 0.2, 0.15, 0.8)))
	shoot_btn.add_theme_stylebox_override("disabled", _round_style(Color(0.1, 0.1, 0.1, 0.35)))
	shoot_btn.button_down.connect(func() -> void:
		player.fire_held = true
		# A quick tap still fires once: at the target, else straight ahead.
		if is_instance_valid(player.target):
			player.shoot_at(player.target.global_position)
		else:
			player.shoot_at(player.global_position + player.facing * 100.0))
	shoot_btn.button_up.connect(func() -> void: player.fire_held = false)
	layer.add_child(shoot_btn)
	shoot_btn.anchor_left = 1.0
	shoot_btn.anchor_right = 1.0
	shoot_btn.anchor_top = 1.0
	shoot_btn.anchor_bottom = 1.0
	shoot_btn.offset_right = -(STICK_MARGIN_X + 10.0)
	shoot_btn.offset_left = shoot_btn.offset_right - 140.0
	shoot_btn.offset_bottom = -(STICK_MARGIN_Y + 10.0)
	shoot_btn.offset_top = shoot_btn.offset_bottom - 140.0

	# Skip turn: shown only in combat; gives up whatever is left of your turn.
	# Round buttons below the Shoot circle, like the door buttons beside it.
	skip_btn = _round_combat_button("Skip\nturn", Color(0.7, 0.85, 1.0))
	skip_btn.tooltip_text = "Do nothing this turn and pass to the next in the initiative order"
	skip_btn.pressed.connect(func() -> void:
		player.fire_held = false
		combat.end_player_turn())
	layer.add_child(skip_btn)
	_place_round_button(skip_btn, 120.0, shoot_c)
	# End combat: shown only in combat; usable only while no enemy is attacking you.
	end_combat_btn = _round_combat_button("End\ncombat", Color(0.75, 1.0, 0.75))
	end_combat_btn.pressed.connect(func() -> void:
		player.fire_held = false
		combat.player_end_combat())
	layer.add_child(end_combat_btn)
	_place_round_button(end_combat_btn, 60.0, shoot_c)
	# Start combat yourself: you go first, and keep taking turns while nobody has noticed you.
	fight_btn = Button.new()
	fight_btn.text = "Start combat"
	fight_btn.tooltip_text = "Start a fight on your terms: you act first, and keep acting while no hostile has noticed you (sneak up from behind)"
	fight_btn.focus_mode = Control.FOCUS_NONE
	fight_btn.custom_minimum_size = Vector2(90, 40)
	fight_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	fight_btn.visible = false  # hidden for now; set to true to bring the button back
	fight_btn.pressed.connect(func() -> void: combat.start_player_initiated())
	_top_col.add_child(fight_btn)
	# Untarget: clears the target (NPC / barrel / crate) and the selected door or window.
	untarget_btn = Button.new()
	untarget_btn.text = "Untarget"
	untarget_btn.tooltip_text = "Clear the current target and selection"
	untarget_btn.focus_mode = Control.FOCUS_NONE
	untarget_btn.custom_minimum_size = Vector2(90, 40)
	untarget_btn.pressed.connect(func() -> void:
		player.fire_held = false
		player.set_target(null)
		player.set_interact(null))
	_top_col.add_child(untarget_btn)
	# Auto reload (toggle): tops the magazine up by itself shortly after you stop firing.
	var auto_btn := Button.new()
	auto_btn.toggle_mode = true
	auto_btn.button_pressed = Player.auto_reload
	auto_btn.text = "Auto reload: %s" % ("on" if Player.auto_reload else "off")
	auto_btn.tooltip_text = "When on, a partly used magazine is reloaded %.0f s after your last shot" % Player.AUTO_RELOAD_DELAY
	auto_btn.focus_mode = Control.FOCUS_NONE
	auto_btn.custom_minimum_size = Vector2(90, 56)
	auto_btn.toggled.connect(func(on: bool) -> void:
		Player.auto_reload = on
		auto_btn.text = "Auto reload: %s" % ("on" if on else "off"))
	auto_btn.visible = false  # hidden for now; set to true to bring the toggle back
	col.add_child(auto_btn)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -(STICK_MARGIN_X + 80.0 + 70.0 + 8.0 + DOOR_BTN + 12.0)  # left of the Shoot circle and its door buttons
	panel.offset_bottom = -40


## Flat round-cornered box that draws as a circle on a square button (used by the Shoot button).
func _round_style(fill: Color, radius := 70.0, border := Color(1.0, 0.55, 0.45, 0.8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(int(radius))
	s.set_border_width_all(3)
	s.border_color = border
	return s


## Player health bar under the controls hint.
func _build_health_bar(layer: CanvasLayer) -> void:
	var bar := ProgressBar.new()
	bar.position = Vector2(HUD_X, 34)
	bar.custom_minimum_size = Vector2(200, 18)
	bar.max_value = Player.MAX_HP
	bar.value = player.hp
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.2, 0.2)
	bar.add_theme_stylebox_override("fill", fill)
	layer.add_child(bar)
	var txt := Label.new()
	txt.position = Vector2(HUD_X + 208, 32)
	txt.text = "HP %d / %d" % [player.hp, Player.MAX_HP]
	layer.add_child(txt)
	# Morale bar under the HP bar. Running away from a fight lowers it.
	var morale_bar := ProgressBar.new()
	morale_bar.position = Vector2(HUD_X, 56)
	morale_bar.custom_minimum_size = Vector2(200, 10)
	morale_bar.max_value = Player.MAX_MORALE
	morale_bar.value = player.morale
	morale_bar.show_percentage = false
	var mfill := StyleBoxFlat.new()
	mfill.bg_color = Color(0.3, 0.55, 0.95)
	morale_bar.add_theme_stylebox_override("fill", mfill)
	layer.add_child(morale_bar)
	var morale_txt := Label.new()
	morale_txt.position = Vector2(HUD_X + 208, 50)
	morale_txt.text = "Morale %d / %d" % [player.morale, Player.MAX_MORALE]
	layer.add_child(morale_txt)
	player.morale_changed.connect(func(m: int, max_m: int) -> void:
		morale_bar.value = m
		morale_txt.text = "Morale %d / %d" % [m, max_m])
	# Ammo for the selected weapon, with a reload bar; updated every frame in _process.
	ammo_label = Label.new()
	ammo_label.position = Vector2(HUD_X, 70)
	ammo_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	ammo_label.add_theme_constant_override("shadow_offset_x", 1)
	ammo_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(ammo_label)
	target_label = Label.new()
	target_label.position = Vector2(HUD_X, 106)
	target_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	target_label.add_theme_constant_override("shadow_offset_x", 1)
	target_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(target_label)
	interact_label = Label.new()
	interact_label.position = Vector2(HUD_X, 126)
	interact_label.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))  # cyan, like the selection brackets
	interact_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	interact_label.add_theme_constant_override("shadow_offset_x", 1)
	interact_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(interact_label)
	reload_bar = ProgressBar.new()
	reload_bar.position = Vector2(HUD_X, 94)
	reload_bar.custom_minimum_size = Vector2(200, 8)
	reload_bar.max_value = 1.0
	reload_bar.step = 0.0
	reload_bar.show_percentage = false
	var rfill := StyleBoxFlat.new()
	rfill.bg_color = Color(0.95, 0.8, 0.35)
	reload_bar.add_theme_stylebox_override("fill", rfill)
	layer.add_child(reload_bar)
	# Purse: coin icon and total, right of the HP text.
	var purse_icon := Control.new()
	purse_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purse_icon.position = Vector2(HUD_X + 318, 33)
	purse_icon.custom_minimum_size = Vector2(20, 20)
	purse_icon.draw.connect(func() -> void: LootDrop.draw_icon(purse_icon, "gold", Vector2(10, 10), 1.0))
	layer.add_child(purse_icon)
	var purse := Label.new()
	purse.position = Vector2(HUD_X + 342, 32)
	purse.text = "Purse: %d gold" % player.gold
	purse.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	purse.add_theme_color_override("font_shadow_color", Color.BLACK)
	purse.add_theme_constant_override("shadow_offset_x", 1)
	purse.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(purse)
	player.gold_changed.connect(func(total: int, added: int) -> void:
		purse.text = "Purse: %d gold" % total
		_flash_message("Picked up %d gold coins" % added))
	# XP total, top-left above the HP bar (where the controls hint used to be).
	var xp_label := Label.new()
	xp_label.position = Vector2(HUD_X, 8)
	xp_label.text = "XP: %d" % player.xp
	xp_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	xp_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	xp_label.add_theme_constant_override("shadow_offset_x", 1)
	xp_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(xp_label)
	# Restart map: reloads this scene, so the map, the player and the enemies start over.
	var restart_btn := Button.new()
	restart_btn.text = "Restart map"
	restart_btn.tooltip_text = "Start this map again from the beginning"
	restart_btn.focus_mode = Control.FOCUS_NONE  # keep keys for walking / shooting
	restart_btn.custom_minimum_size = Vector2(90, 40)
	restart_btn.pressed.connect(func() -> void:
		player.fire_held = false
		get_tree().paused = false
		get_tree().reload_current_scene())
	_top_col.add_child(restart_btn)  # under Untarget, beside the weapon button
	# Exit: back to the home (main menu) screen.
	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.tooltip_text = "Leave this map and return to the home screen"
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.custom_minimum_size = Vector2(90, 40)
	exit_btn.pressed.connect(func() -> void:
		player.fire_held = false
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_top_col.add_child(exit_btn)
	player.xp_changed.connect(func(total: int, added: int) -> void:
		xp_label.text = "XP: %d" % total
		if added > 0:
			_flash_message("+%d XP" % added))
	player.health_changed.connect(func(hp: int, max_hp: int) -> void:
		bar.value = hp
		txt.text = "HP %d / %d" % [hp, max_hp])


## Profile picture in the top-left corner (the character with the current head and shirt colour).
## Clicking it opens / closes the profile panel below it: hat and hair choices, and a shirt colour
## picker. Each head button shows a preview drawn with the same artwork as the player.
func _build_hat_picker(layer: CanvasLayer) -> void:
	var profile := Button.new()
	profile.position = Vector2(12, 8)
	profile.custom_minimum_size = Vector2(PROFILE_SIZE, PROFILE_SIZE)
	profile.focus_mode = Control.FOCUS_NONE  # keep arrow keys for walking
	profile.tooltip_text = "Profile: change hat / hair"
	layer.add_child(profile)
	var portrait := Control.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.clip_contents = true
	portrait.draw.connect(func() -> void:
		portrait.draw_rect(Rect2(Vector2(4, 4), portrait.size - Vector2(8, 8)), Color(0.42, 0.33, 0.22))  # dusty ground
		Player.draw_portrait(portrait, portrait.size * 0.5 + Vector2(0, 4), 2.4))
	profile.add_child(portrait)

	var panel := PanelContainer.new()
	panel.position = Vector2(12, 8 + PROFILE_SIZE + 6)
	panel.visible = false
	layer.add_child(panel)
	profile.pressed.connect(func() -> void: panel.visible = not panel.visible)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var row := GridContainer.new()
	row.columns = 6
	box.add_child(row)
	var group := ButtonGroup.new()
	for i in HeadArt.count():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for walking
		b.custom_minimum_size = Vector2(56, 56)
		b.tooltip_text = HeadArt.style_name(i)
		b.button_pressed = i == Player.head_style
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.draw.connect(func() -> void: HeadArt.draw(icon, i, icon.size * 0.5, -PI * 0.5, 1.45))
		b.add_child(icon)
		b.pressed.connect(func() -> void:
			player.set_head(i)
			portrait.queue_redraw())
		row.add_child(b)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: panel.visible = false)
	box.add_child(close)


var _shoot_touch := -1  # finger index holding the Shoot button (-1 = none)
var _pinch_fingers := {}  # finger index -> screen position, for fingers free to pinch


## Two free fingers moving apart / together zoom the camera (limits are set in Player).
## Fingers that start on the joystick or the Shoot button don't count.
func _pinch_input(event: InputEvent) -> void:
	if player == null or get_tree().paused:
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		if not touch.pressed:
			_pinch_fingers.erase(touch.index)
		elif not (stick != null and stick.get_global_rect().has_point(touch.position)) \
				and not (shoot_btn != null and shoot_btn.get_global_rect().has_point(touch.position)):
			_pinch_fingers[touch.index] = touch.position
		return
	var drag := event as InputEventScreenDrag
	if drag == null or not _pinch_fingers.has(drag.index):
		return
	if _pinch_fingers.size() == 2:
		var old_d: float = _pinch_fingers.values()[0].distance_to(_pinch_fingers.values()[1])
		_pinch_fingers[drag.index] = drag.position
		var new_d: float = _pinch_fingers.values()[0].distance_to(_pinch_fingers.values()[1])
		if old_d > 8.0:
			player.pinch_zoom(new_d / old_d)
	else:
		_pinch_fingers[drag.index] = drag.position


## Second-finger taps. A phone only turns the FIRST finger into mouse clicks, so while one finger
## holds the joystick, taps on the ammo icons (reload) and the Shoot button would be ignored.
## Real touch events are handled here, by hit-testing those two controls.
func _input(event: InputEvent) -> void:
	_pinch_input(event)
	var touch := event as InputEventScreenTouch
	if touch == null or player == null or get_tree().paused:
		return
	if touch.pressed:
		if ammo_icons != null and ammo_icons.visible and ammo_icons.get_global_rect().has_point(touch.position):
			player.reload()
		elif shoot_btn != null and not shoot_btn.disabled and shoot_btn.get_global_rect().has_point(touch.position):
			_shoot_touch = touch.index
			shoot_btn.button_down.emit()  # same as pressing it with the mouse
		else:
			for b in door_buttons.values():
				if b.visible and not b.disabled and b.get_global_rect().has_point(touch.position):
					b.pressed.emit()
					break
	elif touch.index == _shoot_touch:
		_shoot_touch = -1
		shoot_btn.button_up.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/map_editor.tscn")
			KEY_F3:  # debug: show / hide NPC field of view
				NpcNode.show_fov = not NpcNode.show_fov
				for n in get_tree().get_nodes_in_group("npcs"):
					(n as Node2D).queue_redraw()
			KEY_E:
				_use_door(false)
			KEY_K:
				_use_door(true)
