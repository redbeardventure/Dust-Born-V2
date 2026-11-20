extends Node2D
## Map building / editing screen.
##
## Tools: Select, Polygon, Rectangle, Wall, Prop, Light, Spawn.
## Right or middle mouse drag = pan, wheel = zoom, arrows = pan. Ctrl+Z / Ctrl+Y undo / redo, Ctrl+S save.

enum Tool { SELECT, POLYGON, RECT, WALL, PROP, LIGHT, SPAWN }

const TOOL_NAMES := ["Select (V)", "Polygon (P)", "Rectangle (R)", "Wall (W)", "Prop (O)", "Light (L)", "Spawn (T)"]
const TOOL_HINTS := [
	"SELECT: click to select, drag to move. Drag white handles to edit points. Double-click an edge to add a point, right-click a point to remove it. Del deletes. [ ] change draw order.",
	"POLYGON: click to add points. Click the first point, press Enter or right-click to close. Backspace removes the last point, Esc cancels.",
	"RECTANGLE: drag to draw a rectangular room/area. 'Auto-walls' also builds walls around it.",
	"WALL: click to add points. Click the first point to close the loop, Enter or right-click to finish an open wall.",
	"PROP: click to place the selected prop.",
	"LIGHT: click to place a light with the settings on the left.",
	"SPAWN: click to set the player start position.",
]
const GRID := 32.0
const HANDLE_PX := 7.0
const MAX_UNDO := 60
const PROP_ICON_PX := 40
const RMB_DRAG_PX := 5.0
const DRAG_START_PX := 8.0  # mouse travel before a click turns into moving an object
const OverlayScript := preload("res://scripts/editor_overlay.gd")

var data: Dictionary
var renderer: MapRenderer
var overlay: Node2D
var camera: Camera2D
var ui: CanvasLayer

var cur_tool: int = Tool.SELECT
var sel_kind := ""
var sel_idx := -1

var cur_points := PackedVector2Array()
var rect_start := Vector2.ZERO
var rect_active := false
var drag := ""
var drag_vertex := -1
var drag_press_screen := Vector2.ZERO
var drag_origin := Vector2.ZERO
var drag_orig_points := PackedVector2Array()
var drag_orig_pos := Vector2.ZERO

var _rmb_down := false
var _rmb_travel := 0.0
var _prop_icons := {}
var _terrain_icons := {}
var undo_stack: Array = []
var redo_stack: Array = []
var _last_undo_key := ""
var _last_undo_time := 0

var _ui_lock := false
var _dialog_mode := "open"

# UI references
var tool_buttons: Array = []
var terrain_keys: Array = []
var prop_keys: Array = []
var terrain_opt: OptionButton
var prop_opt: OptionButton
var theme_opt: OptionButton
var wall_style_opt: OptionButton
var palette := "fantasy"  # which theme's items the terrain/prop lists show ("all" shows everything)
var scale_spin: SpinBox
var rot_spin: SpinBox
var rand_check: CheckBox
var radius_slider: HSlider
var energy_slider: HSlider
var light_color: ColorPickerButton
var flicker_check: CheckBox
var light_box: VBoxContainer
var wall_width: SpinBox
var snap_check: CheckBox
var grid_check: CheckBox
var light_check: CheckBox
var autowall_check: CheckBox
var ambient_btn: ColorPickerButton
var width_spin: SpinBox
var height_spin: SpinBox
var scatter_spin: SpinBox
var sel_label: Label
var file_label: Label
var status_label: Label
var file_dialog: FileDialog


func _ready() -> void:
	MapData.ensure_loaded()
	data = MapData.working

	renderer = MapRenderer.new()
	renderer.lighting_enabled = false
	add_child(renderer)
	renderer.build(data)

	# Overlay lives on its own canvas layer that follows the camera, so ambient darkness never dims it.
	var ov_layer := CanvasLayer.new()
	ov_layer.layer = 1
	ov_layer.follow_viewport_enabled = true
	add_child(ov_layer)
	overlay = OverlayScript.new()
	overlay.editor = self
	ov_layer.add_child(overlay)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()

	_build_ui()
	_set_palette(str(data.get("theme", "fantasy")))
	_fit_camera()
	_sync_ui()


# ------------------------------------------------------------------ UI construction

func _header(parent: Control, text: String) -> void:
	parent.add_child(HSeparator.new())
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	parent.add_child(l)


## Collapsible section: a clickable header plus a content box (returned) that it shows/hides.
func _section(parent: Control, text: String, collapsed: bool = false) -> VBoxContainer:
	parent.add_child(HSeparator.new())
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.focus_mode = Control.FOCUS_NONE
	head.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	head.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.65))
	head.add_theme_color_override("font_pressed_color", Color(0.95, 0.85, 0.5))
	parent.add_child(head)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.visible = not collapsed
	parent.add_child(content)
	var update := func() -> void:
		head.text = ("▸  " if not content.visible else "▾  ") + text
	update.call()
	head.pressed.connect(func() -> void:
		content.visible = not content.visible
		update.call())
	return content


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _check(parent: Control, text: String, on: bool, cb: Callable = Callable()) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	if cb.is_valid():
		c.toggled.connect(cb)
	parent.add_child(c)
	return c


func _row(parent: Control, text: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 82
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	parent.add_child(h)


func _spin(parent: Control, text: String, lo: float, hi: float, val: float, step: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	if cb.is_valid():
		s.value_changed.connect(cb)
	_row(parent, text, s)
	return s


func _slider(parent: Control, text: String, lo: float, hi: float, val: float, step: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size.y = 20
	if cb.is_valid():
		s.value_changed.connect(cb)
	_row(parent, text, s)
	return s


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = 280
	ui.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	var root := box

	var title := Label.new()
	title.text = "MAP EDITOR"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	file_label = Label.new()
	file_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(file_label)

	# Theme
	box = _section(root, "Theme")
	theme_opt = OptionButton.new()
	for t in MapData.THEME_ORDER:
		theme_opt.add_item("All items" if t == "all" else str(MapData.THEMES[t]["label"]))
	theme_opt.item_selected.connect(_on_theme_selected)
	box.add_child(theme_opt)
	_button(box, "Apply theme ground + ambient", _apply_theme_look)

	# Tools
	box = _section(root, "Tools")
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	box.add_child(tgrid)
	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.text = TOOL_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_tool.bind(i))
		tgrid.add_child(b)
		tool_buttons.append(b)
	tool_buttons[0].button_pressed = true

	# Terrain
	box = _section(root, "Terrain / overlay (polygon, rectangle)")
	terrain_opt = OptionButton.new()
	terrain_opt.item_selected.connect(_on_terrain_selected)
	box.add_child(terrain_opt)
	autowall_check = _check(box, "Auto-walls on rectangles", true)
	wall_style_opt = OptionButton.new()
	for s in MapData.WALL_STYLE_ORDER:
		wall_style_opt.add_item(str(MapData.WALL_STYLES[s][0]))
	wall_style_opt.item_selected.connect(_on_wall_style)
	_row(box, "Wall style", wall_style_opt)
	wall_width = _spin(box, "Wall width", 4, 120, 12, 1, _on_wall_width)

	# Props
	box = _section(root, "Prop")
	prop_opt = OptionButton.new()
	prop_opt.item_selected.connect(_on_prop_selected)
	box.add_child(prop_opt)
	scale_spin = _spin(box, "Scale", 0.2, 4.0, 1.0, 0.05, _on_prop_scale)
	rot_spin = _spin(box, "Rotation", -180, 180, 0, 5, _on_prop_rot)
	rand_check = _check(box, "Randomize scale/rotation on place", true)
	var sg := HBoxContainer.new()
	box.add_child(sg)
	scatter_spin = SpinBox.new()
	scatter_spin.min_value = 5
	scatter_spin.max_value = 500
	scatter_spin.value = 60
	sg.add_child(scatter_spin)
	var sb := Button.new()
	sb.text = "Scatter forest"
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.pressed.connect(_scatter)
	sg.add_child(sb)

	# Lights
	light_box = VBoxContainer.new()
	root.add_child(light_box)
	box = _section(light_box, "Light")
	radius_slider = _slider(box, "Radius", 60, 900, 300, 10, func(_v: float) -> void: _on_light_changed())
	energy_slider = _slider(box, "Energy", 0.1, 3.0, 1.0, 0.05, func(_v: float) -> void: _on_light_changed())
	light_color = ColorPickerButton.new()
	light_color.color = Color(1.0, 0.75, 0.45)
	light_color.custom_minimum_size.y = 24
	light_color.color_changed.connect(func(_c: Color) -> void: _on_light_changed())
	_row(box, "Color", light_color)
	flicker_check = _check(box, "Flicker", true, func(_on: bool) -> void: _on_light_changed())
	_update_light_box()

	# Scene / view
	box = _section(root, "Scene", true)
	ambient_btn = ColorPickerButton.new()
	ambient_btn.color = data["ambient"]
	ambient_btn.custom_minimum_size.y = 24
	ambient_btn.color_changed.connect(_on_ambient_changed)
	_row(box, "Ambient", ambient_btn)
	var sz: Vector2 = data["size"]
	width_spin = _spin(box, "Map width", 256, 8192, sz.x, 64, func(_v: float) -> void: _on_size_changed())
	height_spin = _spin(box, "Map height", 256, 8192, sz.y, 64, func(_v: float) -> void: _on_size_changed())
	light_check = _check(box, "Lighting preview", false, _on_lighting_toggled)
	snap_check = _check(box, "Snap to grid (Alt = toggle)", false)
	grid_check = _check(box, "Show grid", true)

	# Selection
	box = _section(root, "Selection")
	sel_label = Label.new()
	sel_label.text = "Nothing selected"
	box.add_child(sel_label)
	var agrid := GridContainer.new()
	agrid.columns = 2
	box.add_child(agrid)
	_button(agrid, "Delete (Del)", _delete_selected)
	_button(agrid, "Fit view (F)", _fit_camera)
	_button(agrid, "Bring forward ( ] )", _reorder.bind(1))
	_button(agrid, "Send back ( [ )", _reorder.bind(-1))

	# Map actions
	box = _section(root, "Map", true)
	var mgrid := GridContainer.new()
	mgrid.columns = 2
	box.add_child(mgrid)
	_button(mgrid, "Undo", undo)
	_button(mgrid, "Redo", redo)
	_button(mgrid, "Save (Ctrl+S)", _save)
	_button(mgrid, "Save as...", _open_dialog.bind("save"))
	_button(mgrid, "Open...", _open_dialog.bind("open"))
	_button(mgrid, "New blank", _new_map)
	_button(mgrid, "Load sample", _load_sample)
	_button(mgrid, "Clear props", _clear_props)
	box = root
	var play := _button(box, "▶  Play-test this map", _play)
	play.custom_minimum_size.y = 34
	_button(box, "Main menu", _to_menu)

	# Status bar
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	status_label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.x = 600
	bar.add_child(status_label)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 290

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_USERDATA
	file_dialog.filters = PackedStringArray(["*.json ; Map files"])
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


# ------------------------------------------------------------------ helpers

func _terrain_key() -> String:
	return terrain_keys[maxi(terrain_opt.selected, 0)]


func _prop_key() -> String:
	return prop_keys[maxi(prop_opt.selected, 0)]


## Snapping follows the checkbox; holding Alt inverts it for the current action.
func _snap_on() -> bool:
	return snap_check != null and (snap_check.button_pressed != Input.is_key_pressed(KEY_ALT))


func _snap(p: Vector2) -> Vector2:
	if _snap_on():
		return p.snapped(Vector2(GRID, GRID))
	return p


func _mw() -> Vector2:
	var vs := get_viewport_rect().size
	return camera.position + (get_viewport().get_mouse_position() - vs * 0.5) / camera.zoom.x


func _visible_rect() -> Rect2:
	var vs := get_viewport_rect().size / camera.zoom.x
	return Rect2(camera.position - vs * 0.5, vs)


func _fit_camera() -> void:
	var sz: Vector2 = data["size"]
	var vs := get_viewport_rect().size - Vector2(290, 60)
	var z := clampf(minf(vs.x / sz.x, vs.y / sz.y), 0.1, 4.0)
	camera.zoom = Vector2(z, z)
	camera.position = sz * 0.5 - Vector2(145.0 / z, 0)


func _zoom_at(f: float) -> void:
	var vs := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var before := camera.position + (m - vs * 0.5) / camera.zoom.x
	var nz := clampf(camera.zoom.x * f, 0.1, 4.0)
	camera.zoom = Vector2(nz, nz)
	var after := camera.position + (m - vs * 0.5) / camera.zoom.x
	camera.position += before - after


func _sel_points() -> PackedVector2Array:
	if sel_kind == "polygon":
		return data["polygons"][sel_idx]["points"]
	if sel_kind == "wall":
		return data["walls"][sel_idx]["points"]
	return PackedVector2Array()


func _sel_closed() -> bool:
	return sel_kind == "polygon" or (sel_kind == "wall" and data["walls"][sel_idx]["closed"])


func _set_sel_points(pts: PackedVector2Array) -> void:
	if sel_kind == "polygon":
		data["polygons"][sel_idx]["points"] = pts
		renderer.rebuild_terrain()
	elif sel_kind == "wall":
		data["walls"][sel_idx]["points"] = pts
		renderer.rebuild_walls()


func _rebuild_kind(kind: String) -> void:
	match kind:
		"polygon":
			renderer.rebuild_terrain()
		"wall":
			renderer.rebuild_walls()
		"prop":
			renderer.rebuild_props()
		"light":
			renderer.rebuild_lights()


func _vertex_at(pts: PackedVector2Array, pos: Vector2) -> int:
	var best := -1
	var best_d := HANDLE_PX * 1.8 / camera.zoom.x
	for i in pts.size():
		var d := pts[i].distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _nearest_edge(pts: PackedVector2Array, closed: bool, pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	var segs := pts.size() if closed else pts.size() - 1
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b))
		if d < best_d:
			best_d = d
			best = i
	if best_d > 12.0 / camera.zoom.x:
		return -1
	return best


func _pick(pos: Vector2) -> Array:
	var z := camera.zoom.x
	for i in range(data["lights"].size() - 1, -1, -1):
		if pos.distance_to(data["lights"][i]["pos"]) < 14.0 / z:
			return ["light", i]
	for i in range(data["props"].size() - 1, -1, -1):
		var pr: Dictionary = data["props"][i]
		var rad: float = MapData.PROPS.get(pr["type"], MapData.PROPS["tree"])["radius"] * float(pr["scale"])
		if pos.distance_to(pr["pos"]) < maxf(rad * 0.8, 8.0 / z):
			return ["prop", i]
	for i in range(data["walls"].size() - 1, -1, -1):
		var w: Dictionary = data["walls"][i]
		if MapData.dist_to_path(pos, w["points"], w["closed"]) < float(w["width"]) * 0.5 + 8.0 / z:
			return ["wall", i]
	for i in range(data["polygons"].size() - 1, -1, -1):
		var pts: PackedVector2Array = data["polygons"][i]["points"]
		if pts.size() >= 3 and Geometry2D.is_point_in_polygon(pos, pts):
			return ["polygon", i]
	return []


# ------------------------------------------------------------------ undo / redo

func push_undo(key: String = "") -> void:
	var now := Time.get_ticks_msec()
	if key != "" and key == _last_undo_key and now - _last_undo_time < 700:
		_last_undo_time = now
		return
	_last_undo_key = key
	_last_undo_time = now
	undo_stack.append(data.duplicate(true))
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()


func undo() -> void:
	if undo_stack.is_empty():
		return
	redo_stack.append(data.duplicate(true))
	_replace_data(undo_stack.pop_back())


func redo() -> void:
	if redo_stack.is_empty():
		return
	undo_stack.append(data.duplicate(true))
	_replace_data(redo_stack.pop_back())


func _replace_data(nd: Dictionary) -> void:
	data = nd
	MapData.working = nd
	sel_kind = ""
	sel_idx = -1
	cur_points = PackedVector2Array()
	drag = ""
	renderer.build(data)
	_set_palette(str(data.get("theme", "fantasy")))
	_ui_lock = true
	ambient_btn.color = data["ambient"]
	var sz: Vector2 = data["size"]
	width_spin.set_value_no_signal(sz.x)
	height_spin.set_value_no_signal(sz.y)
	_ui_lock = false
	_sync_ui()


# ------------------------------------------------------------------ selection / UI sync

func _select(kind: String, idx: int) -> void:
	sel_kind = kind
	sel_idx = idx
	_sync_ui()


func _sync_ui() -> void:
	if sel_label == null:
		return
	_ui_lock = true
	file_label.text = "File: %s" % MapData.current_path.get_file()
	if sel_kind == "":
		sel_label.text = "Nothing selected"
	else:
		sel_label.text = "Selected: %s #%d" % [sel_kind, sel_idx]
	match sel_kind:
		"polygon":
			var ptype: String = data["polygons"][sel_idx]["type"]
			if not terrain_keys.has(ptype):
				_set_palette("all")
			terrain_opt.select(maxi(terrain_keys.find(ptype), 0))
		"wall":
			wall_width.set_value_no_signal(data["walls"][sel_idx]["width"])
			wall_style_opt.select(maxi(MapData.WALL_STYLE_ORDER.find(data["walls"][sel_idx].get("style", "wall")), 0))
		"prop":
			var pr: Dictionary = data["props"][sel_idx]
			if not prop_keys.has(pr["type"]):
				_set_palette("all")
			prop_opt.select(maxi(prop_keys.find(pr["type"]), 0))
			scale_spin.set_value_no_signal(pr["scale"])
			rot_spin.set_value_no_signal(rad_to_deg(float(pr["rot"])))
		"light":
			var l: Dictionary = data["lights"][sel_idx]
			radius_slider.set_value_no_signal(l["radius"])
			energy_slider.set_value_no_signal(l["energy"])
			light_color.color = l["color"]
			flicker_check.set_pressed_no_signal(l["flicker"])
	_ui_lock = false
	_update_light_box()
	overlay.queue_redraw()


## Light settings are shown only for a selected light, or with the Light tool (settings for new lights).
func _update_light_box() -> void:
	if light_box != null:
		light_box.visible = sel_kind == "light" or cur_tool == Tool.LIGHT


## Small swatch cropped from the terrain texture; translucent overlays are shown over grey.
func _terrain_icon(key: String) -> Texture2D:
	if _terrain_icons.has(key):
		return _terrain_icons[key]
	var src: Image = MapData.get_texture(key).get_image()
	var crop := src.get_region(Rect2i(0, 0, 96, 96))
	var img := Image.create_empty(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 1.0))
	img.blend_rect(crop, Rect2i(0, 0, 96, 96), Vector2i.ZERO)
	img.resize(PROP_ICON_PX, PROP_ICON_PX, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_terrain_icons[key] = tex
	return tex


## Renders a small preview of a prop once (via an off-screen viewport) and caches it.
func _prop_icon(key: String) -> Texture2D:
	if _prop_icons.has(key):
		return _prop_icons[key]
	var vp := SubViewport.new()
	vp.size = Vector2i(PROP_ICON_PX, PROP_ICON_PX)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var node := PropNode.new()
	node.kind = key
	node.seed_v = 1
	var rad: float = MapData.PROPS[key]["radius"]
	var s := (PROP_ICON_PX * 0.42) / maxf(rad, 1.0)
	node.scale = Vector2(s, s)
	node.position = Vector2(PROP_ICON_PX, PROP_ICON_PX) * 0.5
	vp.add_child(node)
	add_child(vp)
	var tex := vp.get_texture()
	_prop_icons[key] = tex
	return tex


## Fills the terrain/prop dropdowns with the items of a theme ("all" lists everything).
func _set_palette(p: String) -> void:
	if not MapData.THEME_ORDER.has(p):
		p = "fantasy"
	palette = p
	terrain_keys = MapData.theme_terrain(p).duplicate()
	prop_keys = MapData.theme_props(p).duplicate()
	prop_keys.sort_custom(func(a, b) -> bool:
		return str(MapData.PROPS[a]["label"]).naturalnocasecmp_to(str(MapData.PROPS[b]["label"])) < 0)
	terrain_keys.sort_custom(func(a, b) -> bool:
		return str(MapData.TERRAIN[a]["label"]).naturalnocasecmp_to(str(MapData.TERRAIN[b]["label"])) < 0)
	terrain_opt.clear()
	terrain_opt.add_theme_constant_override("icon_max_width", PROP_ICON_PX)
	for k in terrain_keys:
		terrain_opt.add_icon_item(_terrain_icon(k), str(MapData.TERRAIN[k]["label"]))
	prop_opt.clear()
	prop_opt.add_theme_constant_override("icon_max_width", PROP_ICON_PX)
	for k in prop_keys:
		prop_opt.add_icon_item(_prop_icon(k), str(MapData.PROPS[k]["label"]))
	terrain_opt.select(0)
	prop_opt.select(0)
	theme_opt.select(MapData.THEME_ORDER.find(p))


func _on_theme_selected(i: int) -> void:
	var p: String = MapData.THEME_ORDER[i]
	if p != "all":
		push_undo()
		data["theme"] = p
	_set_palette(p)
	_sync_ui()


## Sets the map's base ground and ambient light to the current theme's defaults.
func _apply_theme_look() -> void:
	var t := str(data.get("theme", "fantasy"))
	if not MapData.THEMES.has(t):
		return
	push_undo()
	data["background"] = MapData.THEMES[t]["background"]
	data["ambient"] = MapData.THEMES[t]["ambient"]
	_ui_lock = true
	ambient_btn.color = data["ambient"]
	_ui_lock = false
	renderer.rebuild_terrain()
	renderer.refresh_ambient()


func _wall_style() -> String:
	return MapData.WALL_STYLE_ORDER[maxi(wall_style_opt.selected, 0)]


func _on_wall_style(i: int) -> void:
	var style: String = MapData.WALL_STYLE_ORDER[i]
	var def_w: float = MapData.WALL_STYLES[style][1]
	if _ui_lock:
		return
	if sel_kind == "wall":
		push_undo()
		data["walls"][sel_idx]["style"] = style
		data["walls"][sel_idx]["width"] = def_w
		renderer.rebuild_walls()
	wall_width.set_value_no_signal(def_w)


func _set_tool(t: int) -> void:
	cur_tool = t
	cur_points = PackedVector2Array()
	rect_active = false
	tool_buttons[t].set_pressed_no_signal(true)
	_update_light_box()
	overlay.queue_redraw()


func _on_terrain_selected(i: int) -> void:
	if _ui_lock or sel_kind != "polygon":
		return
	push_undo()
	data["polygons"][sel_idx]["type"] = terrain_keys[i]
	renderer.rebuild_terrain()


func _on_prop_selected(i: int) -> void:
	if _ui_lock or sel_kind != "prop":
		return
	push_undo()
	data["props"][sel_idx]["type"] = prop_keys[i]
	renderer.rebuild_props()


func _on_prop_scale(v: float) -> void:
	if _ui_lock or sel_kind != "prop":
		return
	push_undo("prop_scale")
	data["props"][sel_idx]["scale"] = v
	renderer.rebuild_props()


func _on_prop_rot(v: float) -> void:
	if _ui_lock or sel_kind != "prop":
		return
	push_undo("prop_rot")
	data["props"][sel_idx]["rot"] = deg_to_rad(v)
	renderer.rebuild_props()


func _on_wall_width(v: float) -> void:
	if _ui_lock or sel_kind != "wall":
		return
	push_undo("wall_w")
	data["walls"][sel_idx]["width"] = v
	renderer.rebuild_walls()


func _on_light_changed() -> void:
	if _ui_lock or sel_kind != "light":
		return
	push_undo("light")
	var l: Dictionary = data["lights"][sel_idx]
	l["radius"] = radius_slider.value
	l["energy"] = energy_slider.value
	l["color"] = light_color.color
	l["flicker"] = flicker_check.button_pressed
	renderer.rebuild_lights()


func _on_ambient_changed(c: Color) -> void:
	if _ui_lock:
		return
	push_undo("ambient")
	data["ambient"] = c
	renderer.refresh_ambient()


func _on_size_changed() -> void:
	if _ui_lock:
		return
	push_undo("size")
	data["size"] = Vector2(width_spin.value, height_spin.value)
	renderer.rebuild_terrain()


func _on_lighting_toggled(on: bool) -> void:
	renderer.set_lighting(on)


# ------------------------------------------------------------------ input

func _process(delta: float) -> void:
	var pan := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP)))
	if pan != Vector2.ZERO:
		camera.position += pan * 700.0 * delta / camera.zoom.x
	if status_label != null:
		var m := _mw()
		status_label.text = "x %d  y %d   zoom %d%%   |   %s" % [m.x, m.y, camera.zoom.x * 100.0, TOOL_HINTS[cur_tool]]
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				_zoom_at(1.1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				_zoom_at(1.0 / 1.1)
		MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				drag = "pan"
			elif drag == "pan":
				drag = ""
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_left_press(e)
			else:
				_left_release()
		MOUSE_BUTTON_RIGHT:
			# Drag = pan the view. A click without dragging keeps its old action (finish path).
			if e.pressed:
				_rmb_down = drag == ""
				_rmb_travel = 0.0
			else:
				if _rmb_down and _rmb_travel < RMB_DRAG_PX:
					_right_press()
				elif drag == "pan" and _rmb_down:
					drag = ""
				_rmb_down = false


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if _rmb_down:
		_rmb_travel += e.relative.length()
		if _rmb_travel >= RMB_DRAG_PX:
			drag = "pan"
	if drag == "pan":
		camera.position -= e.relative / camera.zoom.x
		return
	if drag == "move_pending" or drag == "vertex_pending":
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			drag = ""
			return
		if e.position.distance_to(drag_press_screen) < DRAG_START_PX:
			return
		push_undo()
		drag_origin = _mw()
		match sel_kind:
			"polygon", "wall":
				drag_orig_points = _sel_points()
			"prop":
				drag_orig_pos = data["props"][sel_idx]["pos"]
			"light":
				drag_orig_pos = data["lights"][sel_idx]["pos"]
		drag = "move" if drag == "move_pending" else "vertex"
	var pos := _mw()
	if drag == "move":
		_do_move(pos)
	elif drag == "vertex":
		var pts := PackedVector2Array(_sel_points())
		pts[drag_vertex] = _snap(pos)
		_set_sel_points(pts)


func _on_key(e: InputEventKey) -> void:
	var ctrl := e.ctrl_pressed or e.meta_pressed
	match e.keycode:
		KEY_Z:
			if ctrl:
				if e.shift_pressed:
					redo()
				else:
					undo()
			return
		KEY_Y:
			if ctrl:
				redo()
			return
		KEY_S:
			if ctrl:
				_save()
			return
		KEY_BACKSPACE:
			if cur_points.size() > 0:
				cur_points.resize(cur_points.size() - 1)
			else:
				_delete_selected()
		KEY_DELETE:
			_delete_selected()
		KEY_ENTER, KEY_KP_ENTER:
			_finish_path(cur_tool == Tool.POLYGON)
		KEY_ESCAPE:
			if drag == "move" or drag == "vertex":
				undo()  # cancel the drag in progress
				redo_stack.clear()
				return
			cur_points = PackedVector2Array()
			rect_active = false
			_select("", -1)
		KEY_BRACKETRIGHT:
			_reorder(1)
		KEY_BRACKETLEFT:
			_reorder(-1)
		KEY_F:
			_fit_camera()
		KEY_V:
			_set_tool(Tool.SELECT)
		KEY_P:
			_set_tool(Tool.POLYGON)
		KEY_R:
			_set_tool(Tool.RECT)
		KEY_W:
			_set_tool(Tool.WALL)
		KEY_O:
			_set_tool(Tool.PROP)
		KEY_L:
			_set_tool(Tool.LIGHT)
		KEY_T:
			_set_tool(Tool.SPAWN)


func _left_press(e: InputEventMouseButton) -> void:
	var pos := _mw()
	var sp := _snap(pos)
	match cur_tool:
		Tool.SELECT:
			_select_press(pos, e.double_click)
		Tool.POLYGON, Tool.WALL:
			_path_click(sp)
		Tool.RECT:
			rect_start = sp
			rect_active = true
		Tool.PROP:
			_place_prop(sp)
		Tool.LIGHT:
			_place_light(sp)
		Tool.SPAWN:
			push_undo()
			data["spawn"] = sp


func _left_release() -> void:
	if rect_active:
		_finish_rect()
	if drag == "move":
		_do_move(_mw(), true)
	if drag == "move" or drag == "vertex" or drag == "move_pending" or drag == "vertex_pending":
		drag = ""


func _right_press() -> void:
	if cur_points.size() > 0:
		_finish_path(cur_tool == Tool.POLYGON)
		return
	if cur_tool == Tool.SELECT and (sel_kind == "polygon" or sel_kind == "wall"):
		var pts := _sel_points()
		var vi := _vertex_at(pts, _mw())
		var min_pts := 3 if sel_kind == "polygon" else 2
		if vi >= 0 and pts.size() > min_pts:
			push_undo()
			var np := PackedVector2Array(pts)
			np.remove_at(vi)
			_set_sel_points(np)
			return
	_select("", -1)


func _select_press(pos: Vector2, dbl: bool) -> void:
	if sel_kind == "polygon" or sel_kind == "wall":
		var pts := _sel_points()
		var vi := _vertex_at(pts, pos)
		if vi >= 0:
			drag = "vertex_pending"
			drag_press_screen = get_viewport().get_mouse_position()
			drag_vertex = vi
			return
		if dbl:
			var ei := _nearest_edge(pts, _sel_closed(), pos)
			if ei >= 0:
				push_undo()
				var np := PackedVector2Array(pts)
				np.insert(ei + 1, _snap(pos))
				_set_sel_points(np)
				return
	var hit := _pick(pos)
	if hit.is_empty():
		_select("", -1)
		return
	_select(hit[0], hit[1])
	# A plain click only selects. Moving starts once the mouse has dragged DRAG_START_PX.
	drag = "move_pending"
	drag_press_screen = get_viewport().get_mouse_position()
	drag_origin = pos
	match sel_kind:
		"polygon", "wall":
			drag_orig_points = _sel_points()
		"prop":
			drag_orig_pos = data["props"][sel_idx]["pos"]
		"light":
			drag_orig_pos = data["lights"][sel_idx]["pos"]


## Moves the selection with the cursor. Follows the mouse exactly while dragging;
## with `snap` true (on release) the result is aligned to the grid.
func _do_move(pos: Vector2, snap: bool = false) -> void:
	var delta := pos - drag_origin
	if snap and _snap_on():
		match sel_kind:
			"polygon", "wall":
				if drag_orig_points.size() > 0:
					delta = _snap(drag_orig_points[0] + delta) - drag_orig_points[0]
			"prop", "light":
				delta = _snap(drag_orig_pos + delta) - drag_orig_pos
	match sel_kind:
		"polygon", "wall":
			var np := PackedVector2Array()
			for p in drag_orig_points:
				np.append(p + delta)
			_set_sel_points(np)
		"prop":
			data["props"][sel_idx]["pos"] = drag_orig_pos + delta
			renderer.rebuild_props()
		"light":
			data["lights"][sel_idx]["pos"] = drag_orig_pos + delta
			renderer.rebuild_lights()


func _path_click(p: Vector2) -> void:
	if cur_points.size() >= 3 and p.distance_to(cur_points[0]) < 14.0 / camera.zoom.x:
		_finish_path(true)
		return
	if cur_points.size() > 0 and cur_points[cur_points.size() - 1].is_equal_approx(p):
		return
	cur_points.append(p)


func _finish_path(closed: bool) -> void:
	var pts := cur_points
	cur_points = PackedVector2Array()
	if cur_tool == Tool.POLYGON:
		if pts.size() < 3:
			return
		push_undo()
		data["polygons"].append(MapData.new_poly(_terrain_key(), pts))
		renderer.rebuild_terrain()
		_select("polygon", data["polygons"].size() - 1)
	elif cur_tool == Tool.WALL:
		if pts.size() < 2:
			return
		push_undo()
		data["walls"].append(MapData.new_wall(pts, closed and pts.size() >= 3, wall_width.value, _wall_style()))
		renderer.rebuild_walls()
		_select("wall", data["walls"].size() - 1)


func _finish_rect() -> void:
	rect_active = false
	var r := Rect2(rect_start, _snap(_mw()) - rect_start).abs()
	if r.size.x < 8.0 or r.size.y < 8.0:
		return
	push_undo()
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	data["polygons"].append(MapData.new_poly(_terrain_key(), pts))
	renderer.rebuild_terrain()
	if autowall_check.button_pressed:
		var rect_style := _wall_style()
		if rect_style == "rail":
			rect_style = "wall"
		data["walls"].append(MapData.new_wall(pts, true, wall_width.value, rect_style))
		renderer.rebuild_walls()
	_select("polygon", data["polygons"].size() - 1)


func _place_prop(p: Vector2) -> void:
	push_undo()
	var sc := scale_spin.value
	var rot := deg_to_rad(rot_spin.value)
	if rand_check.button_pressed:
		sc *= randf_range(0.8, 1.25)
		rot = randf() * TAU
	data["props"].append(MapData.new_prop(_prop_key(), p, sc, rot))
	renderer.rebuild_props()
	_select("prop", data["props"].size() - 1)


func _place_light(p: Vector2) -> void:
	push_undo()
	data["lights"].append(MapData.new_light(p, radius_slider.value, light_color.color, energy_slider.value, flicker_check.button_pressed))
	renderer.rebuild_lights()
	_select("light", data["lights"].size() - 1)


func _delete_selected() -> void:
	if sel_kind == "":
		return
	push_undo()
	var key := {"polygon": "polygons", "wall": "walls", "prop": "props", "light": "lights"}[sel_kind] as String
	data[key].remove_at(sel_idx)
	var kind := sel_kind
	_select("", -1)
	_rebuild_kind(kind)


func _reorder(dir: int) -> void:
	if sel_kind == "" or sel_kind == "light":
		return
	var key := {"polygon": "polygons", "wall": "walls", "prop": "props"}[sel_kind] as String
	var arr: Array = data[key]
	var j := sel_idx + dir
	if j < 0 or j >= arr.size():
		return
	push_undo()
	var tmp: Variant = arr[sel_idx]
	arr[sel_idx] = arr[j]
	arr[j] = tmp
	_rebuild_kind(sel_kind)
	_select(sel_kind, j)


func _scatter() -> void:
	push_undo()
	var n := int(scatter_spin.value)
	MapData.scatter_props(data, n, maxi(n / 6, 1), maxi(n / 6, 1))
	renderer.rebuild_props()


func _clear_props() -> void:
	push_undo()
	data["props"] = []
	_select("", -1)
	renderer.rebuild_props()


func _new_map() -> void:
	var nd := MapData.empty(str(data.get("theme", "fantasy")))
	undo_stack.append(data.duplicate(true))
	redo_stack.clear()
	MapData.current_path = MapData.DEFAULT_PATH
	_replace_data(nd)
	_fit_camera()


func _load_sample() -> void:
	undo_stack.append(data.duplicate(true))
	redo_stack.clear()
	_replace_data(SampleMap.create(str(data.get("theme", "fantasy"))))
	_fit_camera()


# ------------------------------------------------------------------ files / navigation

func _save() -> void:
	if MapData.save_map(data, MapData.current_path):
		status_label.text = "Saved to %s" % ProjectSettings.globalize_path(MapData.current_path)
	_sync_ui()


func _open_dialog(mode: String) -> void:
	_dialog_mode = mode
	DirAccess.make_dir_recursive_absolute(MapData.MAP_DIR)
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if mode == "save" else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Save map" if mode == "save" else "Open map"
	file_dialog.current_dir = MapData.MAP_DIR
	file_dialog.popup_centered(Vector2i(640, 420))


func _on_file_selected(path: String) -> void:
	if _dialog_mode == "save":
		if not path.ends_with(".json"):
			path += ".json"
		MapData.current_path = path
		_save()
	else:
		var loaded := MapData.load_map(path)
		if loaded.is_empty():
			status_label.text = "Could not load %s" % path
			return
		undo_stack.append(data.duplicate(true))
		redo_stack.clear()
		MapData.current_path = path
		_replace_data(loaded)
		_fit_camera()


func _play() -> void:
	MapData.working = data
	get_tree().change_scene_to_file("res://scenes/game_view.tscn")


func _to_menu() -> void:
	MapData.working = data
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ------------------------------------------------------------------ overlay drawing

func draw_overlay(o: Node2D) -> void:
	if data.is_empty():
		return
	var z := camera.zoom.x
	var lw := 1.5 / z
	var size: Vector2 = data["size"]
	var vr := _visible_rect()

	if grid_check.button_pressed:
		var step := GRID
		while step * z < 14.0:
			step *= 2.0
		var gcol := Color(1, 1, 1, 0.10)
		var x := floorf(maxf(vr.position.x, 0.0) / step) * step
		while x <= minf(vr.end.x, size.x):
			o.draw_line(Vector2(x, 0), Vector2(x, size.y), gcol, 1.0 / z)
			x += step
		var y := floorf(maxf(vr.position.y, 0.0) / step) * step
		while y <= minf(vr.end.y, size.y):
			o.draw_line(Vector2(0, y), Vector2(size.x, y), gcol, 1.0 / z)
			y += step
	o.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.6), false, 2.0 / z)

	# Light markers and spawn
	for l in data["lights"]:
		o.draw_circle(l["pos"], 6.0 / z, Color(1, 0.9, 0.4, 0.9))
		o.draw_arc(l["pos"], 9.0 / z, 0.0, TAU, 16, Color(0, 0, 0, 0.8), lw)
	var sp: Vector2 = data["spawn"]
	o.draw_circle(sp, 10.0 / z, Color(0.2, 1.0, 0.4, 0.35))
	o.draw_arc(sp, 10.0 / z, 0.0, TAU, 20, Color(0.2, 1.0, 0.4), 2.0 / z)
	o.draw_line(sp + Vector2(-6, 0) / z, sp + Vector2(6, 0) / z, Color(0.2, 1.0, 0.4), lw)
	o.draw_line(sp + Vector2(0, -6) / z, sp + Vector2(0, 6) / z, Color(0.2, 1.0, 0.4), lw)

	_draw_selection(o, z, lw)

	var sel_col := Color(1.0, 0.85, 0.2)
	var mouse := _snap(_mw())
	# In-progress path
	if cur_points.size() > 0:
		var pts := PackedVector2Array(cur_points)
		pts.append(mouse)
		o.draw_polyline(pts, sel_col, 2.0 / z)
		for p in cur_points:
			_handle(o, p, z)
		if cur_points.size() >= 3:
			var near := mouse.distance_to(cur_points[0]) < 14.0 / z
			o.draw_arc(cur_points[0], 12.0 / z, 0.0, TAU, 20, Color(0.3, 1, 0.4) if near else sel_col, 2.0 / z)
	if rect_active:
		var r := Rect2(rect_start, mouse - rect_start).abs()
		o.draw_rect(r, Color(1, 0.85, 0.2, 0.18))
		o.draw_rect(r, sel_col, false, 2.0 / z)

	# Cursor ghosts
	match cur_tool:
		Tool.PROP:
			var rad: float = MapData.PROPS[_prop_key()]["radius"] * scale_spin.value
			o.draw_arc(mouse, rad, 0.0, TAU, 32, Color(1, 1, 1, 0.6), lw)
		Tool.LIGHT:
			o.draw_arc(mouse, radius_slider.value, 0.0, TAU, 48, Color(1, 0.85, 0.4, 0.5), lw)
		Tool.POLYGON, Tool.WALL, Tool.RECT:
			o.draw_circle(mouse, 3.0 / z, sel_col)


func _handle(o: Node2D, p: Vector2, z: float) -> void:
	var h := HANDLE_PX / z
	var r := Rect2(p - Vector2(h, h) * 0.5, Vector2(h, h))
	o.draw_rect(r, Color.WHITE)
	o.draw_rect(r, Color.BLACK, false, 1.0 / z)


func _draw_selection(o: Node2D, z: float, lw: float) -> void:
	var col := Color(1.0, 0.85, 0.2)
	match sel_kind:
		"polygon", "wall":
			if sel_idx < 0 or sel_idx >= data["polygons" if sel_kind == "polygon" else "walls"].size():
				return
			var pts := PackedVector2Array(_sel_points())
			if pts.size() < 2:
				return
			if _sel_closed():
				pts.append(pts[0])
			o.draw_polyline(pts, col, 2.0 / z)
			for p in _sel_points():
				_handle(o, p, z)
		"prop":
			if sel_idx >= data["props"].size():
				return
			var pr: Dictionary = data["props"][sel_idx]
			var rad: float = MapData.PROPS.get(pr["type"], MapData.PROPS["tree"])["radius"] * float(pr["scale"])
			o.draw_arc(pr["pos"], rad + 4.0, 0.0, TAU, 32, col, 2.0 / z)
		"light":
			if sel_idx >= data["lights"].size():
				return
			var l: Dictionary = data["lights"][sel_idx]
			o.draw_arc(l["pos"], float(l["radius"]), 0.0, TAU, 48, col, lw)
			o.draw_arc(l["pos"], 12.0 / z, 0.0, TAU, 16, col, 2.0 / z)
