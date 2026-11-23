extends Node2D
## Play-test screen: loads the working map with collisions and lighting and spawns a player.

const HeadArt := preload("res://scripts/head_art.gd")

var renderer: MapRenderer
var player: Player
var door_prompt: Label
var ammo_label: Label
var reload_bar: ProgressBar
var target_label: Label
var interact_label: Label
var message_label: Label
var shoot_btn: Button
var reload_btn: Button
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
const COMBAT_FONT := 10  # font size in the compact combat box

## Special-action cards dealt along the bottom of the screen during combat (one per turn).
## Effects are in Player.play_card().
const COMBAT_CARDS := [
	{"kind": "dash", "title": "Dash", "desc": "Double your movement this turn.", "accent": Color(0.25, 0.55, 0.9)},
	{"kind": "aim", "title": "Aimed Shot", "desc": "This turn's shot flies dead straight, hits 50% harder and reaches 50% further.", "accent": Color(0.8, 0.25, 0.2)},
	{"kind": "reload", "title": "Quick Reload", "desc": "Refill your gun without using your action.", "accent": Color(0.8, 0.6, 0.15)},
]
const CARD_GAP := 12.0
var card_row: Control
var cards: Array = []  # ActionCard nodes
var _last_card := ""  # kind of the card played this turn (for its USED stamp)
var ammo_icons: Control
const AMMO_SCALE := 2.0  # how much bigger the ammo graphic is drawn than its 22 px design
const PROFILE_SIZE := 80.0  # profile picture button in the top-left corner
const HUD_X := 12.0 + PROFILE_SIZE + 8.0  # health, ammo and info lines start right of the profile picture
var door_buttons := {}  # "Open" / "Kick" / "Close" -> Button
var _msg_time := 0.0


func _process(delta: float) -> void:
	_check_game_over()
	renderer.update_canopy_fade(player.position, delta)
	renderer.update_roof_fade(player.position, delta)
	_update_ammo()
	_update_combat_status()
	_update_combat_cards()
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
		var can_shoot := is_instance_valid(player.target) and armed and my_go
		if fists and can_shoot and player.turn_mode and not player.in_punch_reach(player.target):
			can_shoot = false  # in combat a punch needs the target right next to you
		var walled: bool = not fists and player.in_wall_cover()
		if walled:
			can_shoot = false  # hiding behind a wall: no line to shoot along
		shoot_btn.text = "Punch" if fists else "Shoot"
		shoot_btn.disabled = not can_shoot
		var verb := "Punch" if fists else "Shoot at"
		shoot_btn.tooltip_text = ("%s the target (hold to keep going)" % verb) if can_shoot else (
				"Wait for your turn" if not my_go else
				"Behind a wall: run to another spot to shoot" if walled else
				"Target an NPC, barrel or crate first" if not is_instance_valid(player.target) else
				"Move next to the target to punch" if fists else "Pick a gun first")
		if not can_shoot:
			player.fire_held = false  # a disabled button never sends button_up
	if reload_btn != null:
		var gun := Weapons.is_ranged(Player.weapon)
		var go := not player.turn_mode or (player.my_turn and player.action_left)
		var can_reload := gun and go and not player.is_reloading() and player.ammo() < Weapons.mag_size(Player.weapon)
		reload_btn.disabled = not can_reload
		reload_btn.tooltip_text = "Reload now%s" % (" (uses your action)" if player.turn_mode else "") if can_reload else (
				"Pick a gun first" if not gun else
				"Wait for your turn" if not go else
				"Already reloading" if player.is_reloading() else "Magazine is full")
	if _msg_time > 0.0:
		_msg_time -= delta
		message_label.modulate.a = clampf(_msg_time / 0.5, 0.0, 1.0)  # fade over the last half second
	var door := _active_door()
	if door == null:
		door_prompt.text = ""
	elif door.is_open:
		door_prompt.text = "Open door nearby"
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
	var near_open := door != null and door.is_open
	var crate: PropNode = player.target as PropNode if is_instance_valid(player.target) else null
	var crate_ready := crate != null and crate.is_openable() and not crate.opened and _crate_in_reach(crate)
	door_buttons["Open"].visible = near_closed or crate_ready
	door_buttons["Kick"].visible = near_closed
	door_buttons["Close"].visible = near_open


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
		target_label.text = "No target   (click an NPC, barrel or crate to target)"
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
	var txt := "%s   Ammo %d / %d" % [Weapons.label(w), player.ammo(), Weapons.mag_size(w)]
	if player.is_reloading():
		txt += "   Reloading..."
	elif player.ammo() < Weapons.mag_size(w):
		txt += ""
	ammo_label.text = txt
	reload_bar.visible = player.is_reloading()
	reload_bar.value = player.reload_progress()
	if ammo_icons != null:
		ammo_icons.visible = true
		ammo_icons.queue_redraw()


## Loaded rounds are bright, spent ones dark. While reloading, rounds fill in one by one with the progress.
func _draw_ammo_icons() -> void:
	var w := Player.weapon
	var mag := Weapons.mag_size(w)
	if mag <= 0:
		return
	var loaded := player.ammo()
	if player.is_reloading():
		loaded = int(floor(player.reload_progress() * mag))
	var c := ammo_icons
	# Drawn on a small design grid, then scaled up and centred in the box above the Shoot button.
	var content_w := 22.0 if w == "pistol" else float(mag) * ((7.0 if w == "shotgun" else 5.0) + 3.0) - 3.0
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


## E opens/closes the nearest door, K kicks a closed one open.
## `only` limits the action: "open" never closes, "close" never opens.
func _use_door(kick: bool, only: String = "") -> void:
	# Open (or E) on a targeted crate the player is standing next to opens it.
	var crate: PropNode = player.target as PropNode if is_instance_valid(player.target) else null
	if not kick and only != "close" and crate != null and crate.is_openable() and _crate_in_reach(crate):
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
		door.open(player.position, kick)
		if kick:
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

	player = Player.new()
	player.map_size = data["size"]
	player.position = data["spawn"]
	add_child(player)

	var layer := CanvasLayer.new()
	add_child(layer)
	var hint := Label.new()
	hint.text = "Click: walk there   Right-click: attack toward cursor   Click NPC / barrel / crate: target   Click door / window: go to it"
	hint.position = Vector2(HUD_X, 8)
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hint)
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
	combat.changed.connect(_refresh_combat_panel)
	_build_combat_panel(layer)
	_build_combat_cards(layer)
	_build_hat_picker(layer)
	_build_weapon_bar(layer)
	_build_action_bar(layer)
	_build_health_bar(layer)


## Weapon HUD: one button at the bottom right showing the equipped weapon (fists at the start).
## Clicking it opens the weapon wheel, which pauses the game.
func _build_weapon_bar(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	layer.add_child(panel)
	weapon_btn = Button.new()
	weapon_btn.focus_mode = Control.FOCUS_NONE  # keep keys for walking / shooting
	weapon_btn.custom_minimum_size = Vector2(96, 96)
	weapon_btn.pressed.connect(_open_weapon_wheel)
	panel.add_child(weapon_btn)
	weapon_icon = Control.new()
	weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	weapon_icon.draw.connect(func() -> void:
		Weapons.draw_icon_at(weapon_icon, Player.weapon, weapon_icon.size * 0.5 - Vector2(0, 6), 62.0)
		var f := ThemeDB.fallback_font
		weapon_icon.draw_string(f, Vector2(0, weapon_icon.size.y - 6), Weapons.label(Player.weapon), HORIZONTAL_ALIGNMENT_CENTER, weapon_icon.size.x, 13, Color(1, 1, 1, 0.9)))
	weapon_btn.add_child(weapon_icon)
	# Bottom-right, so it stays clear of the hat picker in the top-right corner.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -8
	panel.offset_bottom = -40


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
	get_tree().paused = true


func _close_weapon_wheel() -> void:
	if _wheel_layer == null:
		return
	_wheel_layer.queue_free()
	_wheel_layer = null
	if not _game_over:
		get_tree().paused = false


## Win: every bounty NPC on the map is dead. A map without bounties is won once no hostile NPC
## is left alive (after at least one hostile has been seen, so a peaceful map never "ends").
func _check_game_over() -> void:
	if _game_over:
		return
	var won := false
	var why := ""
	if _bounty_total > 0:
		won = get_tree().get_nodes_in_group("bounty").is_empty()
		why = "Every bounty has been collected." if _bounty_total > 1 else "The bounty has been collected."
	else:
		var hostiles := 0
		for n in get_tree().get_nodes_in_group("npcs"):
			if n is NpcNode and (n as NpcNode).disposition == "hostile" and (n as NpcNode).hp > 0:
				hostiles += 1
		if hostiles > 0:
			_saw_hostile = true
		won = _saw_hostile and hostiles == 0
		why = "All hostiles have been defeated."
	if won:
		_show_game_over(why)


func _show_game_over(why: String) -> void:
	_game_over = true
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
	title.text = "BOUNTY COLLECTED" if _bounty_total > 0 else "VICTORY"
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
	back.text = "Back to editor"
	back.custom_minimum_size = Vector2(130, 40)
	back.pressed.connect(func() -> void:
		get_tree().paused = false
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
	card_row.visible = on
	if combat_border != null:
		combat_border.visible = on
	door_prompt.offset_top = -60.0 - (90.0 if on else 0.0)
	message_label.offset_top = -100.0 - (90.0 if on else 0.0)
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
	var defs := [["Open", false, "open"], ["Kick", true, ""], ["Close", false, "close"]]
	for d in defs:
		var b := Button.new()
		b.text = d[0]
		b.focus_mode = Control.FOCUS_NONE  # keep keys for walking / shooting
		b.custom_minimum_size = Vector2(90, 56)
		b.pressed.connect(_use_door.bind(d[1], d[2]))
		b.visible = false  # shown by _update_door_buttons() when a matching door is near
		col.add_child(b)
		door_buttons[d[0]] = b
	# Shoot: fires at the current target; holding it keeps firing at the weapon's rate.
	# Disabled (in _process) while there is no target or no gun selected.
	# Drawn ammo just above the Shoot button: a revolver cylinder for the pistol, a row of rounds otherwise.
	ammo_icons = Control.new()
	ammo_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_icons.custom_minimum_size = Vector2(90, 22.0 * AMMO_SCALE + 6.0)
	ammo_icons.visible = false
	ammo_icons.draw.connect(_draw_ammo_icons)
	col.add_child(ammo_icons)
	shoot_btn = Button.new()
	shoot_btn.text = "Shoot"
	shoot_btn.focus_mode = Control.FOCUS_NONE
	shoot_btn.custom_minimum_size = Vector2(90, 56)
	shoot_btn.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	shoot_btn.button_down.connect(func() -> void:
		player.fire_held = true
		if is_instance_valid(player.target):
			player.shoot_at(player.target.global_position))  # a quick tap still fires once
	shoot_btn.button_up.connect(func() -> void: player.fire_held = false)
	col.add_child(shoot_btn)

	# Reload: refills the magazine now. In a fight it uses the turn's action (the Quick Reload card doesn't).
	reload_btn = Button.new()
	reload_btn.text = "Reload"
	reload_btn.focus_mode = Control.FOCUS_NONE
	reload_btn.custom_minimum_size = Vector2(90, 56)
	reload_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	reload_btn.pressed.connect(func() -> void: player.reload())
	col.add_child(reload_btn)
	# Skip turn: shown only in combat; gives up whatever is left of your turn.
	skip_btn = Button.new()
	skip_btn.text = "Skip turn"
	skip_btn.tooltip_text = "Do nothing this turn and pass to the next in the initiative order"
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.custom_minimum_size = Vector2(90, 40)
	skip_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	skip_btn.visible = false
	skip_btn.pressed.connect(func() -> void:
		player.fire_held = false
		combat.end_player_turn())
	col.add_child(skip_btn)
	# End combat: shown only in combat; usable only while no enemy is attacking you.
	end_combat_btn = Button.new()
	end_combat_btn.text = "End combat"
	end_combat_btn.focus_mode = Control.FOCUS_NONE
	end_combat_btn.custom_minimum_size = Vector2(90, 40)
	end_combat_btn.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	end_combat_btn.visible = false
	end_combat_btn.pressed.connect(func() -> void:
		player.fire_held = false
		combat.player_end_combat())
	col.add_child(end_combat_btn)
	# Start combat yourself: you go first, and keep taking turns while nobody has noticed you.
	fight_btn = Button.new()
	fight_btn.text = "Start combat"
	fight_btn.tooltip_text = "Start a fight on your terms: you act first, and keep acting while no hostile has noticed you (sneak up from behind)"
	fight_btn.focus_mode = Control.FOCUS_NONE
	fight_btn.custom_minimum_size = Vector2(90, 40)
	fight_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	fight_btn.pressed.connect(func() -> void: combat.start_player_initiated())
	col.add_child(fight_btn)
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
	col.add_child(untarget_btn)
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
	col.add_child(auto_btn)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -130
	panel.offset_bottom = -40


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
	profile.tooltip_text = "Profile: change hat / hair and shirt colour"
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
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
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
			title.text = HeadArt.style_name(i)
			portrait.queue_redraw())
		row.add_child(b)
	title.text = HeadArt.style_name(Player.head_style)
	# Shirt colour: swatch button that opens Godot's colour picker.
	var shirt_row := HBoxContainer.new()
	box.add_child(shirt_row)
	var shirt_lbl := Label.new()
	shirt_lbl.text = "Shirt colour"
	shirt_row.add_child(shirt_lbl)
	var shirt := ColorPickerButton.new()
	shirt.focus_mode = Control.FOCUS_NONE
	shirt.custom_minimum_size = Vector2(80, 28)
	shirt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shirt.edit_alpha = false
	shirt.color = Player.shirt_color
	shirt.color_changed.connect(func(c: Color) -> void:
		player.set_shirt_color(c)
		portrait.queue_redraw())
	shirt_row.add_child(shirt)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: panel.visible = false)
	box.add_child(close)


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
