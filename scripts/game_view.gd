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
var ride_btn: Button
var shoot_btn: Button
var ammo_icons: Control
var door_buttons := {}  # "Open" / "Kick" / "Close" -> Button
var _msg_time := 0.0


func _process(delta: float) -> void:
	if ride_btn != null:
		ride_btn.visible = player.mount != null or player.nearest_horse() != null
		ride_btn.text = "Dismount" if player.mount != null else "Ride"
	renderer.update_canopy_fade(player.position, delta)
	renderer.update_roof_fade(player.position, delta)
	_update_ammo()
	if shoot_btn != null:
		var can_shoot := is_instance_valid(player.target) and Weapons.is_ranged(Player.weapon)
		shoot_btn.disabled = not can_shoot
		shoot_btn.tooltip_text = "Shoot at the target (hold to keep firing)" if can_shoot else (
				"Pick a gun first" if not Weapons.is_ranged(Player.weapon) else "Target an NPC, barrel or crate first")
		if not can_shoot:
			player.fire_held = false  # a disabled button never sends button_up
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
		target_label.text = "Target: %s   HP %d / %d" % [t.get("npc_name"), t.get("hp"), NpcNode.MAX_HP]
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
		ammo_icons.position.x = ammo_label.position.x + ammo_label.get_minimum_size().x + 10.0
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


## E opens/closes the nearest door, K kicks a closed one open.
## `only` limits the action: "open" never closes, "close" never opens.
func _use_door(kick: bool, only: String = "") -> void:
	# Open (or E) on a targeted crate the player is standing next to opens it.
	var crate: PropNode = player.target as PropNode if is_instance_valid(player.target) else null
	if not kick and only != "close" and crate != null and crate.is_openable() and _crate_in_reach(crate):
		if crate.opened:
			_flash_message("Already opened")
			return
		var found := crate.open_container(player.global_position)
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
	var reach := door.width + 24.0
	player.refresh_nav(Rect2(door.position - Vector2(reach, reach), Vector2(reach, reach) * 2.0))


func _ready() -> void:
	MapData.ensure_loaded()
	var data := MapData.working

	renderer = MapRenderer.new()
	renderer.physics_enabled = true
	add_child(renderer)
	renderer.build(data)

	player = Player.new()
	player.map_size = data["size"]
	player.position = data["spawn"]
	add_child(player)

	var layer := CanvasLayer.new()
	add_child(layer)
	var hint := Label.new()
	hint.text = "Click: walk there   Right-click: shoot at cursor   Click NPC / barrel / crate: target   Click door / window: go to it   Click horse: ride it"
	hint.position = Vector2(12, 8)
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
	_build_hat_picker(layer)
	_build_weapon_bar(layer)
	_build_action_bar(layer)
	_build_health_bar(layer)


## Vertical column of weapon buttons on the right edge of the screen.
func _build_weapon_bar(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var group := ButtonGroup.new()
	for key in Weapons.PLAYER_CHOICES:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE  # keep keys for walking / shooting
		b.custom_minimum_size = Vector2(96, 96)
		b.tooltip_text = Weapons.tooltip(key)
		b.button_pressed = key == Player.weapon
		var tex := Weapons.icon_texture(key)
		if tex != null:
			# Image icon (e.g. the revolver), scaled to fit inside the button with a small margin.
			var img := TextureRect.new()
			img.texture = tex
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			img.offset_left = 8
			img.offset_top = 8
			img.offset_right = -8
			img.offset_bottom = -8
			b.add_child(img)
		else:
			var icon := Control.new()
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.draw.connect(func() -> void: Weapons.draw_icon(icon, key, icon.size))
			b.add_child(icon)
		b.pressed.connect(player.set_weapon.bind(key))
		col.add_child(b)
	# Bottom-right, so the taller column stays clear of the hat picker in the top-right corner.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -8
	panel.offset_bottom = -40


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
	# Ride / Dismount: shown when a horse is within reach, or while riding.
	ride_btn = Button.new()
	ride_btn.text = "Ride"
	ride_btn.focus_mode = Control.FOCUS_NONE
	ride_btn.custom_minimum_size = Vector2(90, 56)
	ride_btn.add_theme_color_override("font_color", Color(0.95, 0.8, 0.5))
	ride_btn.pressed.connect(player.toggle_mount)
	ride_btn.visible = false
	col.add_child(ride_btn)
	# Shoot: fires at the current target; holding it keeps firing at the weapon's rate.
	# Disabled (in _process) while there is no target or no gun selected.
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
	bar.position = Vector2(12, 34)
	bar.custom_minimum_size = Vector2(200, 18)
	bar.max_value = Player.MAX_HP
	bar.value = player.hp
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.8, 0.2, 0.2)
	bar.add_theme_stylebox_override("fill", fill)
	layer.add_child(bar)
	var txt := Label.new()
	txt.position = Vector2(220, 32)
	txt.text = "HP %d / %d" % [player.hp, Player.MAX_HP]
	layer.add_child(txt)
	# Ammo for the selected weapon, with a reload bar; updated every frame in _process.
	ammo_label = Label.new()
	ammo_label.position = Vector2(12, 56)
	ammo_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	ammo_label.add_theme_constant_override("shadow_offset_x", 1)
	ammo_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(ammo_label)
	# Drawn ammo next to the ammo text: a revolver cylinder for the pistol, a row of rounds otherwise.
	ammo_icons = Control.new()
	ammo_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_icons.custom_minimum_size = Vector2(120, 22)
	ammo_icons.position = Vector2(12, 55)
	ammo_icons.draw.connect(_draw_ammo_icons)
	layer.add_child(ammo_icons)
	target_label = Label.new()
	target_label.position = Vector2(12, 94)
	target_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	target_label.add_theme_constant_override("shadow_offset_x", 1)
	target_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(target_label)
	interact_label = Label.new()
	interact_label.position = Vector2(12, 116)
	interact_label.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))  # cyan, like the selection brackets
	interact_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	interact_label.add_theme_constant_override("shadow_offset_x", 1)
	interact_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(interact_label)
	reload_bar = ProgressBar.new()
	reload_bar.position = Vector2(12, 80)
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
	purse_icon.position = Vector2(330, 33)
	purse_icon.custom_minimum_size = Vector2(20, 20)
	purse_icon.draw.connect(func() -> void: LootDrop.draw_icon(purse_icon, "gold", Vector2(10, 10), 1.0))
	layer.add_child(purse_icon)
	var purse := Label.new()
	purse.position = Vector2(354, 32)
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


## Top-right row of hat buttons; each shows a preview drawn with the same artwork as the player.
func _build_hat_picker(layer: CanvasLayer) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -8
	panel.offset_right = -8
	panel.offset_top = 8
	layer.add_child(panel)
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
			title.text = HeadArt.style_name(i))
		row.add_child(b)
	title.text = HeadArt.style_name(Player.head_style)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/map_editor.tscn")
			KEY_E:
				_use_door(false)
			KEY_K:
				_use_door(true)
