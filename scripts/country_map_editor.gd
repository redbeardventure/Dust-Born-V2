extends Control
## Country map editor. Pick a tool on the right:
##   Locations: add places, drag them, link each to a playable map.
##   Mountains: add, drag, resize, delete.
##   Rivers / Rails: open paths made of points. Lakes / Ground: closed shapes (ground patches
##   tint the land: grass, desert, rock, snow, marsh).
## Changes are saved as soon as they are made.

const CountryMap := preload("res://scripts/country_map.gd")
const MapView := preload("res://scripts/country_map_view.gd")

## tool key -> button label
const TOOLS := {
	"locations": "Locations",
	"mountains": "Mountains",
	"river": "Rivers",
	"lake": "Lakes",
	"rail": "Rail tracks",
	"ground": "Ground",
}
const TOOL_HELP := {
	"locations": "Click \"Add location\", then click the map. Drag a location to move it. Click one to edit it.",
	"mountains": "Turn on \"Add mountains\" and click the map to place them. Drag a mountain to move it. Click one to resize or delete it.",
	"river": "Click \"New river\", then click the map to lay down points. Drag points to reshape. Right-click a point to remove it.",
	"lake": "Click \"New lake\", then click the map to outline it (3 or more points). Drag points to reshape. Right-click a point to remove it.",
	"rail": "Click \"New rail track\", then click the map to lay down points. Drag points to reshape. Right-click a point to remove it.",
	"ground": "Click \"New ground patch\", then click the map to outline it (3 or more points). Pick its terrain below. Right-click a point to remove it.",
}
const FEATURE_NAMES := {"river": "river", "lake": "lake", "rail": "rail track", "ground": "ground patch"}

var data: Dictionary
var view: MapView
var tool := "locations"
var selected := -1        # location
var sel_mtn := -1
var sel_feat := -1

var help: Label
var status: Label
var sec_loc: Control
var sec_mtn: Control
var sec_feat: Control
var add_btn: Button
var loc_fields: Control
var name_edit: LineEdit
var desc_edit: TextEdit
var icon_opt: OptionButton
var link_opt: OptionButton
var order_spin: SpinBox
var start_btn: Button
var mtn_add: Button
var mtn_fields: Control
var size_slider: HSlider
var feat_new: Button
var points_btn: Button
var feat_fields: Control
var ground_row: Control
var ground_opt: OptionButton
var confirm: ConfirmationDialog

## Link string for each item of link_opt ("" = nothing linked).
var _links: Array = []


func _ready() -> void:
	MapData.install_bundled_maps()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	data = CountryMap.load_data()

	var bg := ColorRect.new()
	bg.color = Color("1b2012")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	view = MapView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.editable = true
	view.set_map(data)
	view.location_pressed.connect(_on_location_pressed)
	view.location_moved.connect(func(_i: int) -> void: _save())
	view.mountain_pressed.connect(_on_mountain_pressed)
	view.mountain_moved.connect(func(_i: int) -> void: _save())
	view.feature_pressed.connect(_on_feature_pressed)
	view.feature_changed.connect(_save)
	view.background_pressed.connect(_on_background_pressed)
	row.add_child(view)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	row.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	# Scrolls when the fields don't fit the window height.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Country Map Editor"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	var tools := GridContainer.new()
	tools.columns = 2
	tools.add_theme_constant_override("h_separation", 6)
	tools.add_theme_constant_override("v_separation", 6)
	box.add_child(tools)
	var group := ButtonGroup.new()
	for key: String in TOOLS:
		var b := Button.new()
		b.text = str(TOOLS[key])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == tool
		b.custom_minimum_size.y = 38
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_tool.bind(key))
		tools.add_child(b)

	help = Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	box.add_child(HSeparator.new())

	_build_location_section(box)
	_build_mountain_section(box)
	_build_feature_section(box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var regen := Button.new()
	regen.text = "Regenerate landscape..."
	regen.custom_minimum_size.y = 40
	regen.pressed.connect(func() -> void: confirm.popup_centered())
	box.add_child(regen)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size.y = 44
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	box.add_child(back)

	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Replace every river, lake, rail track, ground patch and mountain with a new random landscape? Locations are kept."
	confirm.confirmed.connect(_on_regenerate)
	add_child(confirm)

	_set_tool("locations")


func _build_location_section(box: Control) -> void:
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	box.add_child(sec)
	sec_loc = sec
	add_btn = Button.new()
	add_btn.text = "Add location"
	add_btn.toggle_mode = true
	add_btn.custom_minimum_size.y = 44
	sec.add_child(add_btn)

	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 6)
	sec.add_child(fields)
	loc_fields = fields
	_label(fields, "Name")
	name_edit = LineEdit.new()
	name_edit.text_changed.connect(_on_name_changed)
	fields.add_child(name_edit)
	_label(fields, "Description (shown before the map starts)")
	desc_edit = TextEdit.new()
	desc_edit.custom_minimum_size = Vector2(0, 130)
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	desc_edit.text_changed.connect(_on_desc_changed)
	fields.add_child(desc_edit)
	_label(fields, "Icon")
	icon_opt = OptionButton.new()
	for key: String in CountryMap.ICON_ORDER:
		icon_opt.add_item(str(CountryMap.ICON_LABELS[key]))
	icon_opt.item_selected.connect(_on_icon_selected)
	fields.add_child(icon_opt)
	_label(fields, "Linked map")
	link_opt = OptionButton.new()
	link_opt.item_selected.connect(_on_link_selected)
	fields.add_child(link_opt)
	_label(fields, "Journey order (1 = start, 0 = not in the journey)")
	var order_row := HBoxContainer.new()
	order_row.add_theme_constant_override("separation", 8)
	fields.add_child(order_row)
	order_spin = SpinBox.new()
	order_spin.min_value = 0
	order_spin.step = 1
	order_spin.rounded = true
	order_spin.value_changed.connect(_on_order_changed)
	order_row.add_child(order_spin)
	start_btn = Button.new()
	start_btn.text = "Set as start"
	start_btn.pressed.connect(func() -> void: _on_order_changed(1.0))
	order_row.add_child(start_btn)
	var order_hint := Label.new()
	order_hint.text = "Players must finish each location in this order to unlock the next."
	order_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(order_hint)
	var del := Button.new()
	del.text = "Delete location"
	del.custom_minimum_size.y = 40
	del.pressed.connect(_on_delete_location)
	fields.add_child(del)


func _build_mountain_section(box: Control) -> void:
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	box.add_child(sec)
	sec_mtn = sec
	mtn_add = Button.new()
	mtn_add.text = "Add mountains"
	mtn_add.toggle_mode = true
	mtn_add.custom_minimum_size.y = 44
	sec.add_child(mtn_add)

	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 6)
	sec.add_child(fields)
	mtn_fields = fields
	_label(fields, "Size")
	size_slider = HSlider.new()
	size_slider.min_value = 0.5
	size_slider.max_value = 2.0
	size_slider.step = 0.05
	size_slider.value_changed.connect(_on_size_changed)
	fields.add_child(size_slider)
	var del := Button.new()
	del.text = "Delete mountain"
	del.custom_minimum_size.y = 40
	del.pressed.connect(_on_delete_mountain)
	fields.add_child(del)


func _build_feature_section(box: Control) -> void:
	var sec := VBoxContainer.new()
	sec.add_theme_constant_override("separation", 6)
	box.add_child(sec)
	sec_feat = sec
	feat_new = Button.new()
	feat_new.custom_minimum_size.y = 44
	feat_new.pressed.connect(_on_new_feature)
	sec.add_child(feat_new)

	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 6)
	sec.add_child(fields)
	feat_fields = fields
	points_btn = Button.new()
	points_btn.text = "Add / insert points"
	points_btn.toggle_mode = true
	points_btn.custom_minimum_size.y = 40
	points_btn.toggled.connect(func(on: bool) -> void:
		view.adding = on
		view.queue_redraw())
	fields.add_child(points_btn)
	var gr := VBoxContainer.new()
	fields.add_child(gr)
	ground_row = gr
	_label(gr, "Terrain")
	ground_opt = OptionButton.new()
	for key: String in CountryMap.GROUND_ORDER:
		ground_opt.add_item(str(CountryMap.GROUND_STYLES[key]))
	ground_opt.item_selected.connect(_on_ground_selected)
	gr.add_child(ground_opt)
	var del := Button.new()
	del.text = "Delete shape"
	del.custom_minimum_size.y = 40
	del.pressed.connect(_on_delete_feature)
	fields.add_child(del)


func _label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	parent.add_child(l)


func _locations() -> Array:
	return data["locations"]


func _save() -> void:
	if CountryMap.save_data(data):
		status.text = "Saved."
	else:
		status.text = "Could not save the country map."


# ---------------------------------------------------------------- tools and selection

func _set_tool(key: String) -> void:
	tool = key
	view.tool = key
	view.adding = false
	selected = -1
	sel_mtn = -1
	sel_feat = -1
	add_btn.button_pressed = false
	mtn_add.button_pressed = false
	points_btn.button_pressed = false
	sec_loc.visible = key == "locations"
	sec_mtn.visible = key == "mountains"
	sec_feat.visible = CountryMap.FEATURE_KINDS.has(key)
	help.text = str(TOOL_HELP[key])
	feat_new.text = "New %s" % str(FEATURE_NAMES.get(key, ""))
	_refresh_panel()


## Shows the fields of whatever is selected and hides them when nothing is.
func _refresh_panel() -> void:
	view.selected = selected
	view.selected_mountain = sel_mtn
	view.selected_feature = sel_feat
	view.queue_redraw()

	loc_fields.visible = selected >= 0
	if selected >= 0:
		var loc: Dictionary = _locations()[selected]
		name_edit.text = str(loc["name"])
		desc_edit.text = str(loc["description"])
		icon_opt.select(maxi(CountryMap.ICON_ORDER.find(str(loc["icon"])), 0))
		_fill_links(str(loc["map"]))
		var place := CountryMap.sequence_position(data, int(loc["id"]))
		order_spin.max_value = (data["sequence"] as Array).size() + (1 if place == 0 else 0)
		order_spin.set_value_no_signal(place)

	mtn_fields.visible = sel_mtn >= 0
	if sel_mtn >= 0:
		size_slider.set_value_no_signal(float(data["mountains"][sel_mtn]["size"]))

	feat_fields.visible = sel_feat >= 0
	if sel_feat >= 0:
		var f: Dictionary = data["features"][sel_feat]
		ground_row.visible = str(f["kind"]) == "ground"
		if ground_row.visible:
			ground_opt.select(maxi(CountryMap.GROUND_ORDER.find(str(f.get("style", "grass"))), 0))
		points_btn.set_pressed_no_signal(view.adding)


func _fill_links(current: String) -> void:
	_links = [""]
	link_opt.clear()
	link_opt.add_item("(none)")
	for m: Dictionary in CountryMap.available_maps():
		link_opt.add_item(str(m["label"]))
		_links.append(str(m["link"]))
	var idx := _links.find(current)
	if idx < 0:
		link_opt.add_item("(missing) %s" % current.get_file())
		_links.append(current)
		idx = _links.size() - 1
	link_opt.select(idx)


func _on_background_pressed(norm: Vector2) -> void:
	match tool:
		"locations":
			if add_btn.button_pressed:
				var id := CountryMap.next_id(data)
				_locations().append({"id": id, "name": "New location", "pos": norm, "icon": "town", "map": "", "description": ""})
				CountryMap.set_sequence_position(data, id, 9999)  # joins the end of the journey
				selected = _locations().size() - 1
				add_btn.button_pressed = false
				view.refresh()
				_save()
			else:
				selected = -1
		"mountains":
			if mtn_add.button_pressed:
				data["mountains"].append({"pos": norm, "size": 1.0, "seed": randi() % 100000})
				sel_mtn = data["mountains"].size() - 1
				view.refresh()
				_save()
			else:
				sel_mtn = -1
		_:
			sel_feat = -1
			view.adding = false
	_refresh_panel()


# ---------------------------------------------------------------- locations

func _on_location_pressed(i: int) -> void:
	selected = i
	add_btn.button_pressed = false
	_refresh_panel()


func _on_name_changed(text: String) -> void:
	if selected < 0:
		return
	_locations()[selected]["name"] = text
	view.queue_redraw()
	_save()


func _on_desc_changed() -> void:
	if selected < 0 or str(_locations()[selected]["description"]) == desc_edit.text:
		return
	_locations()[selected]["description"] = desc_edit.text
	_save()


func _on_icon_selected(idx: int) -> void:
	if selected < 0:
		return
	_locations()[selected]["icon"] = CountryMap.ICON_ORDER[idx]
	view.queue_redraw()
	_save()


func _on_link_selected(idx: int) -> void:
	if selected < 0:
		return
	_locations()[selected]["map"] = _links[idx]
	view.queue_redraw()
	_save()


func _on_order_changed(v: float) -> void:
	if selected < 0:
		return
	CountryMap.set_sequence_position(data, int(_locations()[selected]["id"]), int(v))
	view.refresh()
	_refresh_panel()
	_save()


func _on_delete_location() -> void:
	if selected < 0:
		return
	(data["sequence"] as Array).erase(int(_locations()[selected]["id"]))
	_locations().remove_at(selected)
	selected = -1
	view.refresh()
	_refresh_panel()
	_save()


# ---------------------------------------------------------------- mountains

func _on_mountain_pressed(i: int) -> void:
	sel_mtn = i
	_refresh_panel()


func _on_size_changed(v: float) -> void:
	if sel_mtn < 0:
		return
	data["mountains"][sel_mtn]["size"] = v
	view.update_shapes()
	_save()


func _on_delete_mountain() -> void:
	if sel_mtn < 0:
		return
	data["mountains"].remove_at(sel_mtn)
	sel_mtn = -1
	view.refresh()
	_refresh_panel()
	_save()


# ---------------------------------------------------------------- rivers, lakes, rails, ground

func _on_new_feature() -> void:
	var f := {"kind": tool, "pts": []}
	if tool == "ground":
		f["style"] = CountryMap.GROUND_ORDER[ground_opt.selected] if ground_opt.selected >= 0 else "grass"
	data["features"].append(f)
	sel_feat = data["features"].size() - 1
	view.adding = true
	view.refresh()
	_refresh_panel()


func _on_feature_pressed(i: int) -> void:
	sel_feat = i
	view.adding = false
	_refresh_panel()


func _on_ground_selected(idx: int) -> void:
	if sel_feat < 0:
		return
	data["features"][sel_feat]["style"] = CountryMap.GROUND_ORDER[idx]
	view.update_shapes()
	_save()


func _on_delete_feature() -> void:
	if sel_feat < 0:
		return
	data["features"].remove_at(sel_feat)
	sel_feat = -1
	view.adding = false
	view.refresh()
	_refresh_panel()
	_save()


func _on_regenerate() -> void:
	data["seed"] = randi() % 100000
	data.merge(CountryMap.generate_scenery(int(data["seed"]), _locations()), true)
	view.set_map(data)
	_set_tool(tool)
	_save()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		if tool == "locations":
			_on_delete_location()
		elif tool == "mountains":
			_on_delete_mountain()
