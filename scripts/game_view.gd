extends Node2D
## Play-test screen: loads the working map with collisions and lighting and spawns a player.

const HatArt := preload("res://scripts/hat_art.gd")

var renderer: MapRenderer
var player: Player


func _process(delta: float) -> void:
	renderer.update_canopy_fade(player.position, delta)


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
	hint.text = "Click: walk there   WASD / arrows: move   Shift: run   Esc: back to editor"
	hint.position = Vector2(12, 8)
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 1)
	hint.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hint)
	_build_hat_picker(layer)


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
	var row := HBoxContainer.new()
	box.add_child(row)
	var group := ButtonGroup.new()
	for i in HatArt.count():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE  # keep arrow keys for walking
		b.custom_minimum_size = Vector2(56, 56)
		b.tooltip_text = HatArt.style_name(i)
		b.button_pressed = i == Player.hat_style
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.draw.connect(func() -> void: HatArt.draw(icon, i, icon.size * 0.5, -PI * 0.5, 1.45))
		b.add_child(icon)
		b.pressed.connect(func() -> void:
			player.set_hat(i)
			title.text = "Hat: %s" % HatArt.style_name(i))
		row.add_child(b)
	title.text = "Hat: %s" % HatArt.style_name(Player.hat_style)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/map_editor.tscn")
