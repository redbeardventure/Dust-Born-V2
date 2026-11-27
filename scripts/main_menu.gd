extends Control

## Built-in sample maps offered on the Play screen (theme keys understood by SampleMap.create).
const Loadout := preload("res://scripts/loadout.gd")
const CountryMap := preload("res://scripts/country_map.gd")
const MapView := preload("res://scripts/country_map_view.gd")
const SAMPLE_THEMES := ["fantasy", "train", "desert", "snow", "town", "swamp", "wagon"]
const CREAM := Color("f6e7c1")

var center: CenterContainer
var menu_box: VBoxContainer
var maps_panel: Control
var list_overlay: Control
var toast_label: Label
var country: Dictionary
var completed: Array = []   # ids of finished locations


func _ready() -> void:
	MapData.install_bundled_maps()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	CountryMap.pending_id = -1  # nothing is being played from the country map any more
	var bg := ColorRect.new()
	bg.color = Color("1b2012")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# The country map is the backdrop of the main screen (clicking happens on the Play screen).
	var backdrop := MapView.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var data := CountryMap.load_data()
	backdrop.set_map(data)
	add_child(backdrop)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	menu_box = VBoxContainer.new()
	menu_box.custom_minimum_size = Vector2(300, 0)
	menu_box.add_theme_constant_override("separation", 24)
	center.add_child(menu_box)

	var title := Label.new()
	title.text = "Dustborn: Sundown"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_title(title, 56)
	menu_box.add_child(title)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	menu_box.add_child(row)

	_big_button(row, "Play", _show_maps)
	if not _is_mobile():
		_big_button(row, "Map Editor", func() -> void:
			get_tree().change_scene_to_file("res://scenes/map_editor.tscn"))
		_big_button(row, "Country Map Editor", func() -> void:
			get_tree().change_scene_to_file("res://scenes/country_map_editor.tscn"))
	_big_button(row, "Quit", func() -> void: get_tree().quit())

	# Coming back from a won country-map location: go straight to the map.
	if CountryMap.open_map_screen:
		CountryMap.open_map_screen = false
		_show_maps()


## Cream text with a dark outline, readable over the parchment.
func _style_title(l: Label, font_size: int) -> void:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", CREAM)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	l.add_theme_constant_override("outline_size", maxi(font_size / 4, 6))


## True on Android/iOS, including web exports running in a mobile browser.
func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 44
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Large main-menu button, laid out side by side in an HBoxContainer.
func _big_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := _button(parent, text, cb)
	b.custom_minimum_size = Vector2(200, 90)
	b.add_theme_font_size_override("font_size", 28)
	return b


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	parent.add_child(l)


# ---------------------------------------------------------------- map choice

## Replaces the main menu with the country map. Clicking a location plays its linked map;
## the "..." button (top right) lists every map.
func _show_maps() -> void:
	menu_box.visible = false
	if maps_panel != null:
		maps_panel.queue_free()
	list_overlay = null

	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	maps_panel = panel

	country = CountryMap.load_data()
	var view := MapView.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_map(country)
	completed = CountryMap.load_progress()
	view.states = CountryMap.states(country, completed)
	view.progress_enabled = true
	view.location_pressed.connect(_on_location_pressed)
	panel.add_child(view)

	var title := Label.new()
	title.text = "CHOOSE A MAP"
	_style_title(title, 32)
	panel.add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 14)

	var back := _button(panel, "Back", _close_maps)
	back.custom_minimum_size = Vector2(110, 56)
	back.add_theme_font_size_override("font_size", 24)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 14)

	var more := _button(panel, "...", _show_map_list)
	more.custom_minimum_size = Vector2(80, 56)
	more.add_theme_font_size_override("font_size", 28)
	more.tooltip_text = "All maps"
	more.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)

	var reset := _button(panel, "Reset progress", func() -> void:
		CountryMap.reset_progress()
		completed = []
		view.states = CountryMap.states(country, completed)
		view.queue_redraw()
		_toast("Progress reset."))
	reset.custom_minimum_size = Vector2(170, 44)
	reset.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)


func _close_maps() -> void:
	if maps_panel != null:
		maps_panel.queue_free()
		maps_panel = null
	list_overlay = null
	menu_box.visible = true


## Only the next location of the journey can be played (and ones already finished, to replay).
func _on_location_pressed(i: int) -> void:
	var loc: Dictionary = country["locations"][i]
	var id := int(loc["id"])
	var states: Dictionary = CountryMap.states(country, completed)
	if str(states.get(id, "locked")) == "locked":
		var next := CountryMap.current_id(country, completed)
		if (country["sequence"] as Array).has(id) and next >= 0:
			_toast("Finish %s first." % CountryMap.location_name(country, next))
		else:
			_toast("%s isn't open yet." % str(loc["name"]))
		return
	var link := str(loc.get("map", ""))
	if link == "":
		_toast("%s has no map linked yet." % str(loc["name"]))
		return
	_show_description(loc, link)


## Popup with the location's description. The map only starts when Play is clicked.
func _show_description(loc: Dictionary, link: String) -> void:
	if list_overlay != null:
		return
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	maps_panel.add_child(overlay)
	list_overlay = overlay  # also stops other clicks while the popup is open
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(c)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.11, 0.07, 0.97)
	style.border_color = Color(0.85, 0.65, 0.25)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	c.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = str(loc["name"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	box.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(420, 220)
	box.add_child(scroll)
	var text := Label.new()
	text.text = str(loc.get("description", "")).strip_edges()
	if text.text == "":
		text.text = "No description yet."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 20)
	scroll.add_child(text)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var cancel := _button(row, "Cancel", func() -> void:
		overlay.queue_free()
		list_overlay = null)
	cancel.custom_minimum_size = Vector2(150, 54)
	var play := _button(row, "Play", func() -> void:
		overlay.queue_free()
		list_overlay = null
		CountryMap.pending_id = int(loc["id"])  # winning the map marks this location complete
		if not _play_link(link):
			CountryMap.pending_id = -1
			_toast("The map linked to %s could not be found." % str(loc["name"])))
	play.custom_minimum_size = Vector2(150, 54)
	play.add_theme_font_size_override("font_size", 24)


## Plays a country-map link ("sample:<theme>" or a map file path). False if it can't be found.
func _play_link(link: String) -> bool:
	if link.begins_with("sample:"):
		var theme := link.trim_prefix("sample:")
		if not MapData.THEMES.has(theme):
			return false
		_play_sample(theme)
		return true
	if not FileAccess.file_exists(link):
		return false
	_play_file(link)
	return true


func _toast(text: String) -> void:
	if toast_label != null and is_instance_valid(toast_label):
		toast_label.queue_free()
	var l := Label.new()
	l.text = text
	_style_title(l, 24)
	maps_panel.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 28)
	toast_label = l
	var tw := l.create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)


## Overlay with every playable map as a list (opened by the "..." button).
func _show_map_list() -> void:
	if list_overlay != null:
		return
	CountryMap.pending_id = -1  # maps started from this list don't count towards the journey
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	maps_panel.add_child(overlay)
	list_overlay = overlay
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(c)

	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(380, 0)
	outer.add_theme_constant_override("separation", 10)
	c.add_child(outer)

	var title := Label.new()
	title.text = "ALL MAPS"
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
		_button(list, "Continue: %s" % MapData.current_path.get_file().get_basename(), _play)

	var saved := _saved_maps()
	if not saved.is_empty():
		_heading(list, "Your maps")
		for path in saved:
			_button(list, path.get_file().get_basename(), _play_file.bind(path))

	_heading(list, "Sample maps")
	for t in SAMPLE_THEMES:
		_button(list, str(MapData.THEMES[t]["label"]), _play_sample.bind(t))

	_button(outer, "Back", func() -> void:
		overlay.queue_free()
		list_overlay = null)


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
	Loadout.gold = Loadout.START_GOLD
	Loadout.weapons = []
	MapData.ensure_loaded()
	get_tree().change_scene_to_file("res://scenes/game_view.tscn")
