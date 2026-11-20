extends Node2D
## Play-test screen: loads the working map with collisions and lighting and spawns a player.

const HeadArt := preload("res://scripts/head_art.gd")

var renderer: MapRenderer
var player: Player
var door_prompt: Label
var ammo_label: Label
var reload_bar: ProgressBar
var target_label: Label


func _process(delta: float) -> void:
	renderer.update_canopy_fade(player.position, delta)
	_update_ammo()
	var door := renderer.nearest_door(player.position)
	if door == null:
		door_prompt.text = ""
	elif door.is_open:
		door_prompt.text = "E: close door"
	else:
		door_prompt.text = "E: open door     K: kick it open"


func _update_ammo() -> void:
	if ammo_label == null:
		return
	var t := player.target
	if t != null and is_instance_valid(t):
		target_label.text = "Target: %s   HP %d / %d   (Space / F: fire, Tab: next, X: clear)" % [t.get("npc_name"), t.get("hp"), NpcNode.MAX_HP]
	else:
		target_label.text = "No target   (Tab or click an NPC to target)"
	var w := Player.weapon
	if not Weapons.is_ranged(w):
		ammo_label.text = ""
		reload_bar.visible = false
		return
	var txt := "%s   Ammo %d / %d" % [Weapons.label(w), player.ammo(), Weapons.mag_size(w)]
	if player.is_reloading():
		txt += "   Reloading..."
	elif player.ammo() < Weapons.mag_size(w):
		txt += "   (R: reload)"
	ammo_label.text = txt
	reload_bar.visible = player.is_reloading()
	reload_bar.value = player.reload_progress()


## E opens/closes the nearest door, K kicks a closed one open.
func _use_door(kick: bool) -> void:
	var door := renderer.nearest_door(player.position)
	if door == null:
		return
	if door.is_open:
		if kick or door.blocks_point(player.position):
			return  # can't close a door on yourself
		door.close()
	else:
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
	hint.text = "Click: walk there   WASD / arrows: move   Shift: run   Right-click: shoot at cursor   Click NPC / Tab: target   Space / F: shoot target   R: reload   E: use door   K: kick door   Esc: back to editor"
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
	_build_hat_picker(layer)
	_build_weapon_bar(layer)
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
		b.custom_minimum_size = Vector2(48, 48)
		b.tooltip_text = Weapons.tooltip(key)
		b.button_pressed = key == Player.weapon
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.draw.connect(func() -> void: Weapons.draw_icon(icon, key, icon.size))
		b.add_child(icon)
		b.pressed.connect(player.set_weapon.bind(key))
		col.add_child(b)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_right = -8


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
	target_label = Label.new()
	target_label.position = Vector2(12, 94)
	target_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	target_label.add_theme_constant_override("shadow_offset_x", 1)
	target_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(target_label)
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
