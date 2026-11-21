extends Control

## Built-in sample maps offered on the Play screen (theme keys understood by SampleMap.create).
const SAMPLE_THEMES := ["fantasy", "train", "desert", "snow", "town", "swamp", "wagon"]

var center: CenterContainer
var menu_box: VBoxContainer
var maps_panel: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1b2012")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	menu_box = VBoxContainer.new()
	menu_box.custom_minimum_size = Vector2(300, 0)
	menu_box.add_theme_constant_override("separation", 10)
	center.add_child(menu_box)

	var title := Label.new()
	title.text = "GAME MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	menu_box.add_child(title)

	_button(menu_box, "Play", _show_maps)
	_button(menu_box, "Map Editor", func() -> void:
		get_tree().change_scene_to_file("res://scenes/map_editor.tscn"))
	_button(menu_box, "Quit", func() -> void: get_tree().quit())


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	parent.add_child(l)


# ---------------------------------------------------------------- map choice

## Replaces the main menu with a list of every playable map.
func _show_maps() -> void:
	menu_box.visible = false
	if maps_panel != null:
		maps_panel.queue_free()

	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(380, 0)
	outer.add_theme_constant_override("separation", 10)
	center.add_child(outer)
	maps_panel = outer

	var title := Label.new()
	title.text = "CHOOSE A MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	outer.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(380, 460)
	outer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	# Map currently open in the editor (may include unsaved changes).
	if not MapData.working.is_empty():
		_heading(list, "Current")
		_button(list, "Continue: %s" % MapData.current_path.get_file().get_basename(), func() -> void:
			_play())

	var saved := _saved_maps()
	if not saved.is_empty():
		_heading(list, "Your maps")
		for path in saved:
			_button(list, path.get_file().get_basename(), _play_file.bind(path))

	_heading(list, "Sample maps")
	for t in SAMPLE_THEMES:
		_button(list, str(MapData.THEMES[t]["label"]), _play_sample.bind(t))

	_button(outer, "Back", func() -> void:
		maps_panel.queue_free()
		maps_panel = null
		menu_box.visible = true)


## Saved map files in user://maps, sorted by name.
func _saved_maps() -> Array:
	var out: Array = []
	var dir := DirAccess.open(MapData.MAP_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "json":
			out.append(MapData.MAP_DIR.path_join(f))
	out.sort_custom(func(a, b) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)
	return out


func _play_file(path: String) -> void:
	var d := MapData.load_map(path)
	if d.is_empty():
		push_error("Could not load map: %s" % path)
		return
	MapData.working = d
	MapData.current_path = path
	_play()


func _play_sample(theme: String) -> void:
	MapData.working = SampleMap.create(theme)
	# Own file name, so saving it later from the editor never overwrites another map.
	MapData.current_path = MapData.MAP_DIR.path_join("%s_sample.json" % theme)
	_play()


func _play() -> void:
	MapData.ensure_loaded()
	get_tree().change_scene_to_file("res://scenes/game_view.tscn")
