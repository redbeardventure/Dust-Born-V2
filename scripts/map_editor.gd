extends Node2D
## Map building / editing screen.
##
## Tools: Select, Polygon, Rectangle, Wall, Prop, Light, Spawn, NPC.
## Right or middle mouse drag = pan, wheel = zoom, arrows = pan. Ctrl+Z / Ctrl+Y undo / redo, Ctrl+S save.

enum Tool { SELECT, POLYGON, RECT, WALL, PROP, LIGHT, SPAWN, NPC, OPENING, ROOF }

const TOOL_NAMES := ["Select (V)", "Polygon (P)", "Rectangle (R)", "Wall (W)", "Prop (O)", "Light (L)", "Spawn (T)", "NPC (N)", "Door / Window (D)", "Roof (H)"]
const PATROL_HINT := "PATROL AREA: click to add points. Click the first point, press Enter or right-click to close. Backspace removes the last point, Esc cancels."
const TOOL_HINTS := [
	"SELECT: click to select, drag to move. Drag white handles to edit points. Double-click an edge to add a point, right-click a point to remove it. Del deletes. [ ] change draw order. C copies, V pastes at the cursor. Drag on empty ground or an unselected floor to box-select (Shift adds; Shift-click toggles one). Ctrl+G groups, Ctrl+Shift+G ungroups, Ctrl+A selects all. Q / E rotate the selection 15° (hold to keep turning).",
	"POLYGON: click to add points. Click the first point, press Enter or right-click to close. Backspace removes the last point, Esc cancels.",
	"RECTANGLE: drag to draw a rectangular room/area. 'Auto-walls' also builds walls around it.",
	"WALL: click to add points. Click the first point to close the loop, Enter or right-click to finish an open wall.",
	"PROP: click to place the selected prop.",
	"LIGHT: click to place a light with the settings on the left.",
	"SPAWN: click to set the player start position.",
	"NPC: click to place a non-player character with the settings at the top. Select it, then use 'Draw patrol area' to set where it wanders.",
	"DOOR / WINDOW: click on a wall to set a door or window into it (it snaps to the wall and cuts a gap). Windows let light through; doors can be opened or kicked open in play-test.",
	"ROOF: click to add points. Click the first point, press Enter or right-click to close. Roofs sit above everything. In play-test the whole roof lifts when one of its doors is opened (and stays off), while the player is near one of its windows, or when the player walks under it (a roof with no doors then stays off too). Use the roof button below the tools to show / hide them.",
]
const GRID := 32.0
const HANDLE_PX := 7.0
const MAX_UNDO := 60
const PROP_ICON_PX := 40
const RMB_DRAG_PX := 5.0
const DRAG_START_PX := 8.0  # mouse travel before a click turns into moving an object
const OverlayScript := preload("res://scripts/editor_overlay.gd")
const HeadArt := preload("res://scripts/head_art.gd")

var data: Dictionary
var renderer: MapRenderer
var overlay: Node2D
var camera: Camera2D
var ui: CanvasLayer

var cur_tool: int = Tool.SELECT
var sel_kind := ""
var sel_idx := -1

var cur_points := PackedVector2Array()
var drawing_patrol := false  # cur_points is a patrol area for the selected NPC
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
var _head_icons := {}
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
var prop_loot_opt: OptionButton
var prop_loot_row: HBoxContainer
var prop_lock_check: CheckBox
var prop_loot_panel: PanelContainer
var radius_slider: HSlider
var energy_slider: HSlider
var light_color: ColorPickerButton
var flicker_check: CheckBox
var light_box: PanelContainer
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
var sel_bar: PanelContainer
var prop_bar: PanelContainer
var wall_bar: PanelContainer
var terrain_bar: PanelContainer
var roof_bar: PanelContainer
var roof_opt: OptionButton
var roof_keys: Array = []
var roof_toggle: Button
var copy_btn: Button
var paste_btn: Button
## Copied object: {"kind": sel_kind, "item": deep copy of its data}; empty = nothing copied.
var clipboard := {}
var _paste_count := 0  # pastes from the toolbar button step further from the original each time
## Multi-selection ([[kind, idx], ...]) while sel_kind == "multi".
var multi: Array = []
var drag_multi_orig: Array = []  # copies of the multi-selected items when a drag starts
var marquee_start := Vector2.ZERO
var _pending_hit: Array = []  # area (polygon / roof) under a press: selected on click, box-select on drag
var group_btn: Button
var ungroup_btn: Button
const ROTATE_STEP_DEG := 15.0  # rotate buttons and Q / E turn the selection by this much
var npc_bar: PanelContainer
var npc_name_edit: LineEdit
var npc_weapon_opt: OptionButton
var opening_bar: PanelContainer
var opening_kind_opt: OptionButton
var opening_width: SpinBox
var npc_head_opt: OptionButton
var npc_loot_opt: OptionButton
var npc_disp_opt: OptionButton
var npc_bounty_check: CheckBox
var npc_hp_spin: SpinBox
var patrol_btn: Button
var clear_patrol_btn: Button
var scene_panel: PanelContainer
var top_stack: HFlowContainer
var file_label: Label
var status_label: Label
var file_dialog: FileDialog


func _ready() -> void:
	MapData.ensure_loaded()
	data = MapData.working

	renderer = MapRenderer.new()
	renderer.lighting_enabled = true  # matches the "Lighting preview" checkbox default
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
	_set_palette("all")  # the theme no longer filters terrain/props; every item is listed
	_sync_theme_opt()
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


func _row(parent: Control, text: String, ctrl: Control, label_w: float = 82.0) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = label_w
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
	_inline_spin_arrows(s)
	_row(parent, text, s)
	return s


## Draws a SpinBox's up/down arrows inside its input box (one shared frame) instead of
## as a separate column next to it.
func _inline_spin_arrows(s: SpinBox) -> void:
	var le := s.get_line_edit()
	var base := le.get_theme_stylebox("normal")
	var field: StyleBoxFlat
	if base is StyleBoxFlat:
		field = (base as StyleBoxFlat).duplicate()
	else:
		field = StyleBoxFlat.new()
		field.bg_color = Color(0.1, 0.11, 0.13)
		field.border_color = Color(0.3, 0.32, 0.38)
		field.set_border_width_all(1)
		field.set_corner_radius_all(3)
		field.set_content_margin_all(4)
	# Input part: open on the right so it joins the arrow column.
	var left := field.duplicate() as StyleBoxFlat
	left.border_width_right = 0
	left.corner_radius_top_right = 0
	left.corner_radius_bottom_right = 0
	le.add_theme_stylebox_override("normal", left)
	le.add_theme_stylebox_override("read_only", left)
	le.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Arrow column: same fill and border, open on the left, split into an up and a down half.
	var up := field.duplicate() as StyleBoxFlat
	up.border_width_left = 0
	up.border_width_bottom = 0
	up.corner_radius_top_left = 0
	up.corner_radius_bottom_left = 0
	up.corner_radius_bottom_right = 0
	up.set_content_margin_all(0)
	var down := field.duplicate() as StyleBoxFlat
	down.border_width_left = 0
	down.border_width_top = 0
	down.corner_radius_top_left = 0
	down.corner_radius_bottom_left = 0
	down.corner_radius_top_right = 0
	down.set_content_margin_all(0)
	for pair in [["up", up], ["down", down]]:
		var name_p: String = pair[0]
		var sb: StyleBoxFlat = pair[1]
		var hov := sb.duplicate() as StyleBoxFlat
		hov.bg_color = sb.bg_color.lightened(0.12)
		var prs := sb.duplicate() as StyleBoxFlat
		prs.bg_color = sb.bg_color.lightened(0.22)
		s.add_theme_stylebox_override(name_p + "_background", sb)
		s.add_theme_stylebox_override(name_p + "_background_disabled", sb)
		s.add_theme_stylebox_override(name_p + "_background_hovered", hov)
		s.add_theme_stylebox_override(name_p + "_background_pressed", prs)
	s.add_theme_stylebox_override("field_and_buttons_separator", StyleBoxEmpty.new())
	s.add_theme_stylebox_override("up_down_buttons_separator", StyleBoxEmpty.new())
	s.add_theme_constant_override("field_and_buttons_separation", 0)
	s.add_theme_constant_override("buttons_vertical_separation", 0)


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


## Vertical strip of icon buttons (one per tool) down the right edge of the screen.
func _build_tool_bar() -> void:
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	bar.add_child(col)
	var group := ButtonGroup.new()
	for i in TOOL_NAMES.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = TOOL_NAMES[i]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_set_tool.bind(i))
		# Active tool: bright gold border on a lighter blue fill, so it stands out from the others.
		var active := StyleBoxFlat.new()
		active.bg_color = Color(0.22, 0.36, 0.58)
		active.border_color = Color(1.0, 0.82, 0.25)
		active.set_border_width_all(3)
		active.set_corner_radius_all(6)
		active.shadow_color = Color(1.0, 0.8, 0.2, 0.45)
		active.shadow_size = 4
		b.add_theme_stylebox_override("pressed", active)
		b.add_theme_stylebox_override("hover_pressed", active)
		var ic := Control.new()
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.draw.connect(_draw_tool_icon.bind(ic, i))
		b.add_child(ic)
		col.add_child(b)
		tool_buttons.append(b)
	tool_buttons[0].button_pressed = true
	# Roof visibility toggle: not a tool, so it stays out of the tool button group.
	col.add_child(HSeparator.new())
	roof_toggle = Button.new()
	roof_toggle.toggle_mode = true
	roof_toggle.button_pressed = true
	roof_toggle.custom_minimum_size = Vector2(44, 44)
	roof_toggle.tooltip_text = "Show / hide roofs"
	roof_toggle.focus_mode = Control.FOCUS_NONE
	var roof_ic := Control.new()
	roof_ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	roof_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roof_ic.draw.connect(_draw_roof_toggle_icon.bind(roof_ic))
	roof_toggle.add_child(roof_ic)
	roof_toggle.toggled.connect(func(on: bool) -> void:
		renderer.set_roofs_visible(on)
		if not on and sel_kind == "roof":
			_select("", -1)
		roof_ic.queue_redraw()
		overlay.queue_redraw())
	col.add_child(roof_toggle)
	# Anchor to the left edge, vertically centred.
	bar.anchor_left = 0.0
	bar.anchor_right = 0.0
	bar.anchor_top = 0.5
	bar.anchor_bottom = 0.5
	bar.grow_horizontal = Control.GROW_DIRECTION_END
	bar.grow_vertical = Control.GROW_DIRECTION_BOTH
	bar.offset_left = 8


## Settings / file / save / undo / redo / play icon buttons in the top-left corner of the screen.
func _build_history_bar() -> void:
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	# Gear: shows / hides the Scene Settings panel below the bar.
	var gear := Button.new()
	gear.toggle_mode = true
	gear.custom_minimum_size = Vector2(44, 44)
	gear.tooltip_text = "Scene Settings"
	gear.focus_mode = Control.FOCUS_NONE
	gear.toggled.connect(func(on: bool) -> void: scene_panel.visible = on)
	var gear_icon := Control.new()
	gear_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gear_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gear_icon.draw.connect(_draw_history_icon.bind(gear_icon, "gear"))
	gear.add_child(gear_icon)
	row.add_child(gear)
	# "..." file menu
	var menu := MenuButton.new()
	menu.custom_minimum_size = Vector2(44, 44)
	menu.tooltip_text = "File menu"
	menu.flat = false  # MenuButton is flat by default; match the other icon buttons
	menu.focus_mode = Control.FOCUS_NONE
	var popup := menu.get_popup()
	popup.add_item("Save As...", 0)
	popup.add_item("Open...", 1)
	popup.add_item("New", 2)
	popup.add_separator()
	popup.add_item("Main menu", 3)
	popup.id_pressed.connect(_on_file_menu)
	var menu_icon := Control.new()
	menu_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_icon.draw.connect(_draw_history_icon.bind(menu_icon, "menu"))
	menu.add_child(menu_icon)
	row.add_child(menu)
	var defs := [["Save (Ctrl+S)", "save", _save], ["Undo (Ctrl+Z)", "undo", undo], ["Redo (Ctrl+Y)", "redo", redo],
			["Copy selected (C / Ctrl+C)", "copy", _copy_selected], ["Paste (V / Ctrl+V)", "paste", _paste.bind(false)],
			["Play-test this map", "play", _play]]
	for d in defs:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = d[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(d[2])
		var ic := Control.new()
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.draw.connect(_draw_history_icon.bind(ic, d[1]))
		b.add_child(ic)
		row.add_child(b)
		if d[1] == "copy":
			copy_btn = b
		elif d[1] == "paste":
			paste_btn = b
	_update_clip_buttons()
	bar.offset_left = 8
	bar.offset_top = 8


func _on_file_menu(id: int) -> void:
	match id:
		0:
			_open_dialog("save")
		1:
			_open_dialog("open")
		2:
			_new_map()
		3:
			_to_menu()


## Curved arrow: points left for undo, mirrored (points right) for redo. "play" draws a play triangle.
func _draw_history_icon(c: Control, kind: String) -> void:
	var u := minf(c.size.x, c.size.y) / 44.0
	var o := (c.size - Vector2(44, 44) * u) * 0.5
	var m := kind == "redo"
	var P := func(x: float, y: float) -> Vector2:
		return o + Vector2(44.0 - x if m else x, y) * u
	var col := Color(0.95, 0.95, 0.95)
	if kind == "gear":  # cog: toothed ring with a hole
		var cen: Vector2 = P.call(22, 22)
		var teeth := PackedVector2Array()
		for i in 32:
			var a := TAU * float(i) / 32.0
			var r := (13.0 if (i / 2) % 2 == 0 else 9.5) * u  # 8 teeth, 2 points each
			teeth.append(cen + Vector2(cos(a), sin(a)) * r)
		c.draw_colored_polygon(teeth, col)
		c.draw_circle(cen, 4.5 * u, Color(0.2, 0.22, 0.26))
		return
	if kind == "menu":  # three dots
		for x in [12.0, 22.0, 32.0]:
			c.draw_circle(P.call(x, 22), 2.8 * u, col)
		return
	if kind == "save":  # floppy disk
		var blue := Color(0.45, 0.65, 0.95)
		c.draw_rect(Rect2(P.call(10, 9), Vector2(24, 26) * u), blue)
		c.draw_rect(Rect2(P.call(10, 9), Vector2(24, 26) * u), Color(0.1, 0.12, 0.2), false, 1.5 * u)
		c.draw_rect(Rect2(P.call(15, 9), Vector2(14, 8) * u), col)  # shutter
		c.draw_rect(Rect2(P.call(24, 11), Vector2(3, 5) * u), Color(0.2, 0.25, 0.4))
		c.draw_rect(Rect2(P.call(14, 22), Vector2(16, 13) * u), col)  # label
		c.draw_line(P.call(17, 26), P.call(27, 26), Color(0.5, 0.5, 0.55), 1.2 * u)
		c.draw_line(P.call(17, 30), P.call(27, 30), Color(0.5, 0.5, 0.55), 1.2 * u)
		return
	if kind == "play":
		c.draw_colored_polygon(PackedVector2Array([P.call(15, 10), P.call(15, 34), P.call(35, 22)]), Color(0.4, 0.9, 0.5))
		return
	var dim := Color(col, 0.35) if c.get_parent() is Button and (c.get_parent() as Button).disabled else col
	if kind == "copy":  # two overlapping sheets
		var back := Color(0.2, 0.22, 0.26)
		c.draw_rect(Rect2(P.call(10, 8), Vector2(18, 22) * u), back)
		c.draw_rect(Rect2(P.call(10, 8), Vector2(18, 22) * u), dim, false, 2.0 * u)
		c.draw_rect(Rect2(P.call(17, 15), Vector2(18, 22) * u), back)
		c.draw_rect(Rect2(P.call(17, 15), Vector2(18, 22) * u), dim, false, 2.0 * u)
		for y in [21.0, 26.0, 31.0]:
			c.draw_line(P.call(21, y), P.call(31, y), Color(dim, dim.a * 0.6), 1.5 * u)
		return
	if kind == "paste":  # clipboard with a sheet on it
		var board := Color(0.62, 0.45, 0.28, dim.a)
		c.draw_rect(Rect2(P.call(10, 10), Vector2(24, 27) * u), board)
		c.draw_rect(Rect2(P.call(10, 10), Vector2(24, 27) * u), Color(0.15, 0.1, 0.05, dim.a), false, 1.5 * u)
		c.draw_rect(Rect2(P.call(17, 7), Vector2(10, 6) * u), Color(0.75, 0.75, 0.8, dim.a))  # clip
		c.draw_rect(Rect2(P.call(14, 15), Vector2(16, 18) * u), dim)  # sheet
		for y in [20.0, 24.0, 28.0]:
			c.draw_line(P.call(17, y), P.call(27, y), Color(0.45, 0.45, 0.5, dim.a), 1.2 * u)
		return
	var arc := PackedVector2Array()
	for i in 17:
		var a := PI + (PI * 1.45) * float(i) / 16.0  # left side, over the top, down the right
		arc.append(P.call(22.0 + cos(a) * 9.0, 24.0 + sin(a) * 9.0))
	c.draw_polyline(arc, col, 3.0 * u)
	c.draw_colored_polygon(PackedVector2Array([P.call(13, 32), P.call(7, 23), P.call(19, 23)]), col)


## Prop type / scale / rotation bar at the top of the screen. Shown while a prop is selected or the Prop tool is active
## (the Prop tool needs the same settings to place new props).
func _build_prop_bar() -> void:
	prop_bar = PanelContainer.new()
	prop_bar.visible = false
	_top_stack().add_child(prop_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	prop_bar.add_child(row)
	prop_opt = OptionButton.new()
	prop_opt.custom_minimum_size.x = 200
	prop_opt.item_selected.connect(_on_prop_selected)
	row.add_child(prop_opt)
	scale_spin = _spin(row, "Scale", 0.2, 4.0, 1.0, 0.05, _on_prop_scale)
	rot_spin = _spin(row, "Rotate", -180, 180, 0, 5, _on_prop_rot)
	rand_check = _check(row, "Randomize on place", true)
	# Loot inside the prop: only shown for props that can hold it (barrels and crates).
	# It gets its own panel in the top stack, so it wraps onto a second line instead of running off-screen.
	prop_loot_panel = PanelContainer.new()
	prop_loot_panel.visible = false
	_top_stack().add_child(prop_loot_panel)
	prop_loot_row = HBoxContainer.new()
	prop_loot_panel.add_child(prop_loot_row)
	prop_loot_opt = _option(MapData.NPC_LOOT)
	prop_loot_opt.custom_minimum_size.x = 120
	prop_loot_opt.item_selected.connect(_on_prop_loot)
	_row(prop_loot_row, "Loot", prop_loot_opt, 40)
	prop_lock_check = _check(prop_loot_row, "Locked (needs a key)", false, _on_prop_locked)
	# Scatter settings stay hidden; _scatter() still reads this value.
	scatter_spin = SpinBox.new()
	scatter_spin.min_value = 5
	scatter_spin.max_value = 500
	scatter_spin.value = 60
	scatter_spin.visible = false
	row.add_child(scatter_spin)


## Terrain dropdown. Shown while a polygon/rectangle is selected or the Polygon/Rectangle tool is active.
func _build_terrain_bar() -> void:
	terrain_bar = PanelContainer.new()
	terrain_bar.visible = false
	_top_stack().add_child(terrain_bar)
	var row := HBoxContainer.new()
	terrain_bar.add_child(row)
	terrain_opt = OptionButton.new()
	terrain_opt.custom_minimum_size.x = 200
	terrain_opt.item_selected.connect(_on_terrain_selected)
	_row(row, "Terrain", terrain_opt)


## Roof texture bar. Shown while a roof is selected or the Roof tool is active.
func _build_roof_bar() -> void:
	roof_bar = PanelContainer.new()
	roof_bar.visible = false
	_top_stack().add_child(roof_bar)
	var row := HBoxContainer.new()
	roof_bar.add_child(row)
	roof_opt = OptionButton.new()
	roof_opt.custom_minimum_size.x = 200
	roof_opt.add_theme_constant_override("icon_max_width", PROP_ICON_PX)
	roof_keys = MapData.ROOFS.keys()
	for k in roof_keys:
		roof_opt.add_icon_item(_terrain_icon(k), str(MapData.ROOFS[k]["label"]))
	roof_opt.select(0)
	roof_opt.item_selected.connect(_on_roof_selected)
	_row(row, "Roof", roof_opt)


func _roof_key() -> String:
	return roof_keys[maxi(roof_opt.selected, 0)]


func _on_roof_selected(i: int) -> void:
	if _ui_lock or sel_kind != "roof":
		return
	push_undo()
	data["roofs"][sel_idx]["type"] = roof_keys[i]
	renderer.rebuild_roofs()


func _option(keys_to_labels: Dictionary) -> OptionButton:
	var o := OptionButton.new()
	for k in keys_to_labels:
		o.add_item(str(keys_to_labels[k]))
	o.item_selected.connect(func(_i: int) -> void: _on_npc_changed())
	return o


## Door / window bar. Shown while an opening is selected or the Door / Window tool is active.
func _build_opening_bar() -> void:
	opening_bar = PanelContainer.new()
	opening_bar.visible = false
	_top_stack().add_child(opening_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	opening_bar.add_child(row)
	opening_kind_opt = OptionButton.new()
	for k in MapData.OPENING_KINDS:
		opening_kind_opt.add_item(str(MapData.OPENING_KINDS[k][0]))
	opening_kind_opt.item_selected.connect(_on_opening_kind)
	_row(row, "Type", opening_kind_opt, 40)
	opening_width = _spin(row, "Width", 24, 200, 48, 4, _on_opening_width)


func _opening_kind() -> String:
	return MapData.OPENING_KINDS.keys()[maxi(opening_kind_opt.selected, 0)]


func _on_opening_kind(i: int) -> void:
	var kind: String = MapData.OPENING_KINDS.keys()[i]
	var def_w: float = MapData.OPENING_KINDS[kind][1]
	if _ui_lock:
		return
	if sel_kind == "opening":
		push_undo()
		data["openings"][sel_idx]["kind"] = kind
		data["openings"][sel_idx]["width"] = def_w
		renderer.rebuild_openings()
	opening_width.set_value_no_signal(def_w)


func _on_opening_width(v: float) -> void:
	if _ui_lock or sel_kind != "opening":
		return
	push_undo("opening_w")
	data["openings"][sel_idx]["width"] = v
	renderer.rebuild_openings()


## Finds the wall centre line closest to `pos` (within reach). Returns {pos, rot, thick}, or {} if none is close.
func _wall_snap(pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := 22.0 / camera.zoom.x + 8.0
	for w in data["walls"]:
		if w.get("style", "wall") == "rail":
			continue
		var pts: PackedVector2Array = w["points"]
		var segs := pts.size() if w["closed"] else pts.size() - 1
		for i in segs:
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if a.distance_to(b) < 0.01:
				continue
			var c := Geometry2D.get_closest_point_to_segment(pos, a, b)
			var d := pos.distance_to(c)
			if d < best_d:
				best_d = d
				best = {"pos": c, "rot": (b - a).angle(), "thick": float(w["width"])}
	return best


func _place_opening(p: Vector2) -> void:
	push_undo()
	var s := _wall_snap(p)
	var o := MapData.new_opening(_opening_kind(), s.get("pos", p), s.get("rot", 0.0), opening_width.value, s.get("thick", 12.0))
	data["openings"].append(o)
	renderer.rebuild_openings()
	_select("opening", data["openings"].size() - 1)


## Local-space test: is `pos` over opening `o`?
func _in_opening(o: Dictionary, pos: Vector2) -> bool:
	var l: Vector2 = (pos - o["pos"]).rotated(-float(o["rot"]))
	return absf(l.x) < float(o["width"]) * 0.5 + 4.0 and absf(l.y) < maxf(float(o["thick"]) * 0.5, 8.0) + 6.0 / camera.zoom.x


func _opening_corners(o: Dictionary, grow: float = 0.0) -> PackedVector2Array:
	var hx := float(o["width"]) * 0.5 + grow
	var hy := maxf(float(o["thick"]), 10.0) * 0.5 + grow
	var r := float(o["rot"])
	var c: Vector2 = o["pos"]
	return PackedVector2Array([
		c + Vector2(-hx, -hy).rotated(r), c + Vector2(hx, -hy).rotated(r),
		c + Vector2(hx, hy).rotated(r), c + Vector2(-hx, hy).rotated(r)])


## NPC settings bar. Shown while an NPC is selected or the NPC tool is active
## (the NPC tool uses the same settings for newly placed NPCs).
func _build_npc_bar() -> void:
	npc_bar = PanelContainer.new()
	npc_bar.visible = false
	_top_stack().add_child(npc_bar)
	# Two compact rows so the bar stays narrow enough for the space beside the side panel and tool bar.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	npc_bar.add_child(col)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	col.add_child(row1)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	col.add_child(row2)
	npc_name_edit = LineEdit.new()
	npc_name_edit.text = "NPC"
	npc_name_edit.placeholder_text = "NPC name"
	npc_name_edit.custom_minimum_size.x = 120
	npc_name_edit.text_changed.connect(func(_t: String) -> void: _on_npc_changed())
	npc_name_edit.text_submitted.connect(func(_t: String) -> void: npc_name_edit.release_focus())
	_row(row1, "Name", npc_name_edit, 46)
	npc_weapon_opt = _option(MapData.NPC_WEAPONS)
	npc_weapon_opt.custom_minimum_size.x = 110
	_row(row1, "Weapon", npc_weapon_opt, 52)
	# Item 0 = no head; item i+1 = HeadArt style i (hats, then hair).
	npc_head_opt = OptionButton.new()
	npc_head_opt.custom_minimum_size.x = 150
	npc_head_opt.add_theme_constant_override("icon_max_width", PROP_ICON_PX)
	npc_head_opt.add_item("None")
	for i in HeadArt.count():
		npc_head_opt.add_icon_item(_head_icon(i), HeadArt.style_name(i))
	npc_head_opt.item_selected.connect(func(_i: int) -> void: _on_npc_changed())
	_row(row1, "Head", npc_head_opt, 40)
	npc_loot_opt = _option(MapData.NPC_LOOT)
	npc_loot_opt.custom_minimum_size.x = 120
	_row(row2, "Loot", npc_loot_opt, 46)
	npc_disp_opt = _option(MapData.NPC_DISPOSITIONS)
	npc_disp_opt.custom_minimum_size.x = 90
	_row(row2, "Attitude", npc_disp_opt, 52)
	npc_hp_spin = _spin(row2, "Health", 1, 999, MapData.DEFAULT_NPC_HP, 1, func(_v: float) -> void: _on_npc_changed())
	# Bounty: only for hostile NPCs. Killing every bounty target wins the play-test.
	npc_bounty_check = _check(row2, "Bounty", false, func(_on: bool) -> void: _on_npc_changed())
	npc_bounty_check.tooltip_text = "Wanted outlaw (hostile only). The play-test is won once every bounty is killed."
	patrol_btn = _button(row2, "Draw patrol area", _start_patrol_draw)
	clear_patrol_btn = _button(row2, "Clear patrol", _clear_patrol)


## Wall style / width / auto-walls bar. Shown while a wall is selected or a tool that creates walls is active.
func _build_wall_bar() -> void:
	wall_bar = PanelContainer.new()
	wall_bar.visible = false
	_top_stack().add_child(wall_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wall_bar.add_child(row)
	wall_style_opt = OptionButton.new()
	for s in MapData.WALL_STYLE_ORDER:
		wall_style_opt.add_item(str(MapData.WALL_STYLES[s][0]))
	wall_style_opt.item_selected.connect(_on_wall_style)
	_row(row, "Wall style", wall_style_opt)
	wall_width = _spin(row, "Wall width", 4, 120, 12, 1, _on_wall_width)
	autowall_check = _check(row, "Auto-walls on rectangles", true)


## Centred row at the top of the screen that holds the contextual bars.
func _top_stack() -> HFlowContainer:
	if top_stack == null:
		top_stack = HFlowContainer.new()
		top_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_stack.alignment = FlowContainer.ALIGNMENT_CENTER
		top_stack.add_theme_constant_override("h_separation", 6)
		top_stack.add_theme_constant_override("v_separation", 4)
		ui.add_child(top_stack)
		# Spans from the icon bar in the top-left corner to the right edge.
		top_stack.anchor_right = 1.0
		top_stack.offset_left = 348  # leaves room for the settings/undo/redo buttons in the top-left corner
		top_stack.offset_right = -8
		top_stack.offset_top = 8
	return top_stack


## Icon bar along the top of the screen, shown only while something is selected.
func _build_selection_bar() -> void:
	sel_bar = PanelContainer.new()
	sel_bar.visible = false
	_top_stack().add_child(sel_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	sel_bar.add_child(row)
	sel_label = Label.new()
	sel_label.custom_minimum_size.x = 130
	sel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(sel_label)
	var defs := [
		["Delete (Del)", "delete", _delete_selected],
		["Bring forward ( ] )", "forward", _reorder.bind(1)],
		["Send back ( [ )", "back", _reorder.bind(-1)],
		["Rotate left 15° (Q, hold to keep turning)", "rot_left", _rotate_by_field.bind(-1.0)],
		["Rotate right 15° (E, hold to keep turning)", "rot_right", _rotate_by_field.bind(1.0)],
		["Group: select and move together (Ctrl+G)", "group", _group_selected],
		["Ungroup (Ctrl+Shift+G)", "ungroup", _ungroup_selected],
	]
	for d in defs:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.tooltip_text = d[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(d[2])
		var ic := Control.new()
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.draw.connect(_draw_sel_icon.bind(ic, d[1]))
		b.add_child(ic)
		row.add_child(b)
		if d[1] == "group":
			group_btn = b
		elif d[1] == "ungroup":
			ungroup_btn = b
		if d[1] == "rot_left" or d[1] == "rot_right":
			b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS  # turn on mouse-down, not on release


func _draw_sel_icon(c: Control, kind: String) -> void:
	var u := minf(c.size.x, c.size.y) / 44.0
	var o := (c.size - Vector2(44, 44) * u) * 0.5
	var P := func(x: float, y: float) -> Vector2:
		return o + Vector2(x, y) * u
	var w := 2.0 * u
	var off := c.get_parent() is Button and (c.get_parent() as Button).disabled
	var gcol := Color(0.55, 0.85, 1.0, 0.35 if off else 1.0)
	match kind:
		"rot_left", "rot_right":  # curved arrow round a square; mirrored for right
			var m := kind == "rot_right"
			var Q := func(x: float, y: float) -> Vector2:
				return P.call(44.0 - x if m else x, y)
			var white := Color(0.95, 0.95, 0.95)
			c.draw_rect(Rect2(P.call(16, 18), Vector2(12, 12) * u), Color(0.55, 0.85, 1.0, 0.8))
			var arc := PackedVector2Array()
			for i in 15:
				var a := -PI * 0.15 - PI * 1.3 * float(i) / 14.0
				arc.append(Q.call(22.0 + cos(a) * 13.0, 24.0 + sin(a) * 13.0))
			c.draw_polyline(arc, white, 2.5 * u)
			# Arrowhead at the end of the arc, pointing along it.
			var tip: Vector2 = arc[arc.size() - 1]
			var dir: Vector2 = (tip - arc[arc.size() - 2]).normalized()
			var side := dir.orthogonal()
			c.draw_colored_polygon(PackedVector2Array([tip + dir * 6.0 * u, tip + side * 5.0 * u, tip - side * 5.0 * u]), white)
		"group", "ungroup":  # three shapes inside a dashed frame; ungroup = frame broken apart
			c.draw_rect(Rect2(P.call(12, 13), Vector2(10, 10) * u), gcol)
			c.draw_circle(P.call(29, 18), 5.0 * u, gcol)
			c.draw_colored_polygon(PackedVector2Array([P.call(16, 33), P.call(22, 25), P.call(28, 33)]), gcol)
			var fr := [P.call(7, 8), P.call(37, 8), P.call(37, 37), P.call(7, 37), P.call(7, 8)]
			if kind == "group":
				for i in 4:
					c.draw_dashed_line(fr[i], fr[i + 1], Color(1.0, 0.85, 0.2, gcol.a), 1.6 * u, 4.0 * u)
			else:
				var red := Color(0.95, 0.4, 0.35, gcol.a)
				for corner in [[P.call(7, 15), P.call(7, 8), P.call(14, 8)], [P.call(30, 8), P.call(37, 8), P.call(37, 15)],
						[P.call(37, 30), P.call(37, 37), P.call(30, 37)], [P.call(14, 37), P.call(7, 37), P.call(7, 30)]]:
					c.draw_polyline(PackedVector2Array(corner), red, 1.8 * u)
		"delete":  # trash can
			var red := Color(0.9, 0.35, 0.35)
			c.draw_rect(Rect2(P.call(13, 15), Vector2(18, 20) * u), red, false, w)
			c.draw_line(P.call(10, 14), P.call(34, 14), red, w)
			c.draw_rect(Rect2(P.call(18, 9), Vector2(8, 5) * u), red, false, w)
			for x in [18.0, 22.0, 26.0]:
				c.draw_line(P.call(x, 19), P.call(x, 31), red, 1.5 * u)
		"forward", "back":  # two stacked squares, front one highlighted
			var hi := Color(0.95, 0.8, 0.35)
			var lo := Color(0.55, 0.55, 0.6)
			var edge := Color(0.1, 0.1, 0.1)
			var ra := Rect2(P.call(10, 10), Vector2(18, 18) * u)
			var rb := Rect2(P.call(18, 18), Vector2(18, 18) * u)
			# Drawn back-to-front: the highlighted square is on top for "forward", underneath for "back".
			var order := [[ra, lo], [rb, hi]] if kind == "forward" else [[rb, hi], [ra, lo]]
			for e in order:
				c.draw_rect(e[0], e[1])
				c.draw_rect(e[0], edge, false, 1.2 * u)


## House roof (pitched, two shaded halves); crossed out when roofs are hidden.
func _draw_roof_icon(c: Control, shown: bool) -> void:
	var s := c.size
	var u := minf(s.x, s.y) / 44.0
	var o := (s - Vector2(44, 44) * u) * 0.5
	var P := func(x: float, y: float) -> Vector2:
		return o + Vector2(x, y) * u
	var a := 1.0 if shown else 0.45
	c.draw_colored_polygon(PackedVector2Array([P.call(22, 9), P.call(38, 24), P.call(22, 24)]), Color(0.78, 0.4, 0.3, a))
	c.draw_colored_polygon(PackedVector2Array([P.call(22, 9), P.call(22, 24), P.call(6, 24)]), Color(0.62, 0.3, 0.22, a))
	c.draw_colored_polygon(PackedVector2Array([P.call(6, 24), P.call(38, 24), P.call(38, 34), P.call(6, 34)]), Color(0.7, 0.36, 0.27, a))
	c.draw_polyline(PackedVector2Array([P.call(6, 34), P.call(6, 24), P.call(22, 9), P.call(38, 24), P.call(38, 34), P.call(6, 34)]), Color(0.15, 0.08, 0.06, a), 1.5 * u)
	c.draw_line(P.call(22, 9), P.call(22, 24), Color(0.15, 0.08, 0.06, a), 1.5 * u)


func _draw_roof_toggle_icon(c: Control) -> void:
	var shown := roof_toggle == null or roof_toggle.button_pressed
	_draw_roof_icon(c, shown)
	if not shown:
		var u := minf(c.size.x, c.size.y) / 44.0
		var o := (c.size - Vector2(44, 44) * u) * 0.5
		c.draw_line(o + Vector2(7, 38) * u, o + Vector2(37, 8) * u, Color(0.95, 0.35, 0.3), 3.0 * u)


func _draw_tool_icon(c: Control, tool_id: int) -> void:
	var s := c.size
	var u := minf(s.x, s.y) / 44.0  # icon designed on a 44px button
	var o := (s - Vector2(44, 44) * u) * 0.5
	var P := func(x: float, y: float) -> Vector2:
		return o + Vector2(x, y) * u
	var white := Color(0.95, 0.95, 0.95)
	var gold := Color(0.95, 0.8, 0.35)
	var w := 2.0 * u
	match tool_id:
		Tool.SELECT:  # mouse arrow
			var arrow := PackedVector2Array([P.call(14, 9), P.call(14, 32), P.call(20, 27), P.call(24, 36), P.call(28, 34), P.call(24, 25), P.call(32, 25)])
			c.draw_colored_polygon(arrow, white)
			c.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color(0.1, 0.1, 0.1), 1.2 * u)
		Tool.POLYGON:  # outline with vertex dots
			var pts := PackedVector2Array([P.call(22, 8), P.call(35, 17), P.call(30, 33), P.call(14, 33), P.call(9, 17)])
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), gold, w)
			for p in pts:
				c.draw_circle(p, 3.0 * u, white)
		Tool.RECT:
			c.draw_rect(Rect2(P.call(9, 12), Vector2(26, 20) * u), Color(0.5, 0.75, 0.5, 0.35))
			c.draw_rect(Rect2(P.call(9, 12), Vector2(26, 20) * u), gold, false, w)
			for p in [P.call(9, 12), P.call(35, 12), P.call(9, 32), P.call(35, 32)]:
				c.draw_rect(Rect2(p - Vector2(2.5, 2.5) * u, Vector2(5, 5) * u), white)
		Tool.WALL:  # brick wall
			var brick := Color(0.7, 0.45, 0.35)
			for r in 3:
				var y := 10.0 + r * 8.0
				c.draw_rect(Rect2(P.call(8, y), Vector2(28, 7) * u), brick)
				var mortar := Color(0.2, 0.12, 0.1)
				var xs := [15.0, 25.0] if r % 2 == 0 else [20.0, 30.0]
				for x in xs:
					c.draw_line(P.call(x, y), P.call(x, y + 7), mortar, 1.2 * u)
				c.draw_line(P.call(8, y + 7.5), P.call(36, y + 7.5), mortar, 1.2 * u)
		Tool.PROP:  # tree
			c.draw_rect(Rect2(P.call(20, 24), Vector2(4, 11) * u), Color(0.5, 0.33, 0.2))
			c.draw_circle(P.call(22, 18), 10.0 * u, Color(0.3, 0.65, 0.3))
			c.draw_circle(P.call(19, 15), 4.0 * u, Color(0.45, 0.8, 0.4))
		Tool.LIGHT:  # bulb with rays
			var cen: Vector2 = P.call(22, 22)
			c.draw_circle(cen, 7.0 * u, Color(1.0, 0.85, 0.4))
			for k in 8:
				var d := Vector2.RIGHT.rotated(k * TAU / 8.0)
				c.draw_line(cen + d * 10.0 * u, cen + d * 15.0 * u, Color(1.0, 0.85, 0.4), w)
		Tool.SPAWN:  # flag
			c.draw_line(P.call(14, 9), P.call(14, 36), white, w)
			c.draw_colored_polygon(PackedVector2Array([P.call(14, 9), P.call(34, 15), P.call(14, 22)]), Color(0.9, 0.3, 0.3))
		Tool.OPENING:  # wall with a door gap and a window
			var wall_c := Color(0.6, 0.57, 0.5)
			c.draw_rect(Rect2(P.call(6, 20), Vector2(9, 5) * u), wall_c)
			c.draw_rect(Rect2(P.call(29, 20), Vector2(9, 5) * u), wall_c)
			c.draw_rect(Rect2(P.call(15, 21), Vector2(14, 3) * u), Color("7a5230"))
			c.draw_arc(P.call(15, 22.5), 14.0 * u, -PI * 0.5, 0.0, 10, Color(1, 1, 1, 0.35), 1.0 * u)
			c.draw_rect(Rect2(P.call(10, 8), Vector2(24, 7) * u), Color(0.62, 0.84, 0.95, 0.6))
			c.draw_rect(Rect2(P.call(10, 8), Vector2(24, 7) * u), Color("4a3a2c"), false, 1.5 * u)
			c.draw_line(P.call(22, 8), P.call(22, 15), Color("4a3a2c"), 1.5 * u)
		Tool.ROOF:  # pitched roof with vertex dots
			_draw_roof_icon(c, true)
			for p in [P.call(6, 34), P.call(6, 24), P.call(22, 9), P.call(38, 24), P.call(38, 34)]:
				c.draw_circle(p, 2.5 * u, white)
		Tool.NPC:  # person with a dashed patrol loop
			var green := Color("4caf5a")
			c.draw_circle(P.call(22, 18), 7.0 * u, green)
			c.draw_arc(P.call(22, 18), 7.0 * u, 0.0, TAU, 16, Color(0.06, 0.09, 0.12), 1.5 * u)
			c.draw_circle(P.call(22, 16), 2.0 * u, Color("e8c9a0"))
			c.draw_arc(P.call(22, 34), 9.0 * u, PI, TAU, 10, green, 4.0 * u)
			var loop := PackedVector2Array([P.call(7, 12), P.call(37, 10), P.call(38, 38), P.call(8, 38)])
			c.draw_polyline(loop + PackedVector2Array([loop[0]]), gold, 1.5 * u)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)

	var box: Control

	# Scene settings: a panel under the gear button in the top-left bar (hidden until the gear is pressed).
	# Placed right of the left tool bar so it never covers the tools.
	scene_panel = PanelContainer.new()
	scene_panel.visible = false
	scene_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	scene_panel.custom_minimum_size.x = 280
	ui.add_child(scene_panel)
	scene_panel.offset_left = 72
	scene_panel.offset_top = 68  # just below the top-left icon bar
	# Fully opaque background (the default panel style is see-through).
	var scene_style := StyleBoxFlat.new()
	scene_style.bg_color = Color(0.13, 0.14, 0.17, 1.0)
	scene_style.border_color = Color(0.3, 0.32, 0.38, 1.0)
	scene_style.set_border_width_all(1)
	scene_style.set_corner_radius_all(4)
	scene_style.set_content_margin_all(8)
	scene_panel.add_theme_stylebox_override("panel", scene_style)
	var scene_box := VBoxContainer.new()
	scene_box.add_theme_constant_override("separation", 4)
	scene_panel.add_child(scene_box)
	var scene_title := Label.new()
	scene_title.text = "Scene Settings"
	scene_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	scene_box.add_child(scene_title)
	box = scene_box
	file_label = Label.new()
	file_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(file_label)
	# Theme = the map's base background only; each entry shows a swatch of its ground.
	theme_opt = OptionButton.new()
	theme_opt.add_theme_constant_override("icon_max_width", PROP_ICON_PX)
	for t in _theme_keys():
		theme_opt.add_icon_item(_terrain_icon(MapData.THEMES[t]["background"]), str(MapData.THEMES[t]["label"]))
	theme_opt.item_selected.connect(_on_theme_selected)
	_row(box, "Theme", theme_opt)
	ambient_btn = ColorPickerButton.new()
	ambient_btn.color = data["ambient"]
	ambient_btn.custom_minimum_size.y = 24
	ambient_btn.color_changed.connect(_on_ambient_changed)
	_row(box, "Ambient", ambient_btn)
	var sz: Vector2 = data["size"]
	width_spin = _spin(box, "Map width", 256, 8192, sz.x, 64, func(_v: float) -> void: _on_size_changed())
	height_spin = _spin(box, "Map height", 256, 8192, sz.y, 64, func(_v: float) -> void: _on_size_changed())
	light_check = _check(box, "Lighting preview", true, _on_lighting_toggled)
	snap_check = _check(box, "Snap to grid (Alt = toggle)", false)
	grid_check = _check(box, "Show grid", false)

	_build_tool_bar()
	_build_history_bar()

	_build_terrain_bar()
	_build_roof_bar()
	_build_wall_bar()
	_build_prop_bar()
	_build_npc_bar()
	_build_opening_bar()

	# Light settings bar at the top (shown for a selected light or the Light tool).
	light_box = PanelContainer.new()
	light_box.visible = false
	_top_stack().add_child(light_box)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 8)
	light_box.add_child(lrow)
	radius_slider = _slider(lrow, "Radius", 60, 900, 300, 10, func(_v: float) -> void: _on_light_changed())
	radius_slider.custom_minimum_size.x = 110
	energy_slider = _slider(lrow, "Energy", 0.1, 3.0, 1.0, 0.05, func(_v: float) -> void: _on_light_changed())
	energy_slider.custom_minimum_size.x = 110
	light_color = ColorPickerButton.new()
	light_color.color = Color(1.0, 0.75, 0.45)
	light_color.custom_minimum_size = Vector2(48, 24)
	light_color.color_changed.connect(func(_c: Color) -> void: _on_light_changed())
	_row(lrow, "Color", light_color, 40)
	flicker_check = _check(lrow, "Flicker", true, func(_on: bool) -> void: _on_light_changed())
	_update_light_box()

	_build_selection_bar()
	top_stack.move_child(sel_bar, 0)

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
	ui.move_child(scene_panel, -1)  # draw (and take clicks) above the tool bar it may overlap

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
	var vs := get_viewport_rect().size - Vector2(120, 140)  # room for the tool bar, top bars and status bar
	var z := clampf(minf(vs.x / sz.x, vs.y / sz.y), 0.1, 4.0)
	camera.zoom = Vector2(z, z)
	camera.position = sz * 0.5


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
	if sel_kind == "roof":
		return data["roofs"][sel_idx]["points"]
	if sel_kind == "wall":
		return data["walls"][sel_idx]["points"]
	if sel_kind == "npc":
		return data["npcs"][sel_idx]["patrol"]
	return PackedVector2Array()


## True when the selection has editable points (polygon / wall outline or an NPC's patrol area).
func _has_points() -> bool:
	return sel_kind == "polygon" or sel_kind == "roof" or sel_kind == "wall" or sel_kind == "npc"


func _sel_closed() -> bool:
	return sel_kind == "polygon" or sel_kind == "roof" or sel_kind == "npc" or (sel_kind == "wall" and data["walls"][sel_idx]["closed"])


func _set_sel_points(pts: PackedVector2Array) -> void:
	if sel_kind == "polygon":
		data["polygons"][sel_idx]["points"] = pts
		renderer.update_polygon(sel_idx)
	elif sel_kind == "roof":
		data["roofs"][sel_idx]["points"] = pts
		renderer.rebuild_roofs()
	elif sel_kind == "wall":
		data["walls"][sel_idx]["points"] = pts
		renderer.rebuild_walls()
	elif sel_kind == "npc":
		data["npcs"][sel_idx]["patrol"] = pts
		renderer.rebuild_npcs()


func _rebuild_kind(kind: String) -> void:
	match kind:
		"polygon":
			renderer.rebuild_terrain()
		"roof":
			renderer.rebuild_roofs()
		"wall":
			renderer.rebuild_walls()
		"prop":
			renderer.rebuild_props()
		"light":
			renderer.rebuild_lights()
		"npc":
			renderer.rebuild_npcs()
		"opening":
			renderer.rebuild_openings()


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
	for i in range(data["npcs"].size() - 1, -1, -1):
		if pos.distance_to(data["npcs"][i]["pos"]) < maxf(26.0, 20.0 / z):  # generous, so NPCs are easy to grab
			return ["npc", i]
	for i in range(data["openings"].size() - 1, -1, -1):
		if _in_opening(data["openings"][i], pos):
			return ["opening", i]
	for i in range(data["props"].size() - 1, -1, -1):
		var pr: Dictionary = data["props"][i]
		var rad: float = MapData.PROPS.get(pr["type"], MapData.PROPS["tree"])["radius"] * float(pr["scale"])
		if pos.distance_to(pr["pos"]) < maxf(rad * 0.8, 8.0 / z):
			return ["prop", i]
	for i in range(data["walls"].size() - 1, -1, -1):
		var w: Dictionary = data["walls"][i]
		if MapData.dist_to_path(pos, w["points"], w["closed"]) < float(w["width"]) * 0.5 + 8.0 / z:
			return ["wall", i]
	# Roofs cover everything, so they are picked last: things under a roof stay selectable.
	if renderer.roofs_visible:
		for i in range(data["roofs"].size() - 1, -1, -1):
			var rpts: PackedVector2Array = data["roofs"][i]["points"]
			if rpts.size() >= 3 and Geometry2D.is_point_in_polygon(pos, rpts):
				return ["roof", i]
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
	multi = []
	cur_points = PackedVector2Array()
	drawing_patrol = false
	drag = ""
	renderer.build(data)
	_sync_theme_opt()
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
	multi = []
	_sync_ui()


func _sync_ui() -> void:
	if sel_label == null:
		return
	_ui_lock = true
	file_label.text = "File: %s" % MapData.current_path.get_file()
	if sel_kind == "":
		sel_label.text = "Nothing selected"
	elif sel_kind == "multi":
		sel_label.text = "Selected: %d objects%s" % [multi.size(), "  (group)" if _sel_is_one_group() else ""]
	else:
		sel_label.text = "Selected: %s #%d" % [sel_kind, sel_idx]
	if group_btn != null:
		group_btn.disabled = _sel_list().size() < 2 or _sel_is_one_group()
		ungroup_btn.disabled = not _sel_has_group()
		group_btn.get_child(0).queue_redraw()
		ungroup_btn.get_child(0).queue_redraw()
	match sel_kind:
		"polygon":
			var ptype: String = data["polygons"][sel_idx]["type"]
			if not terrain_keys.has(ptype):
				_set_palette("all")
			terrain_opt.select(maxi(terrain_keys.find(ptype), 0))
		"roof":
			roof_opt.select(maxi(roof_keys.find(str(data["roofs"][sel_idx]["type"])), 0))
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
			prop_loot_opt.select(maxi(MapData.NPC_LOOT.keys().find(str(pr.get("loot", "none"))), 0))
			prop_lock_check.set_pressed_no_signal(bool(pr.get("locked", false)))
		"light":
			var l: Dictionary = data["lights"][sel_idx]
			radius_slider.set_value_no_signal(l["radius"])
			energy_slider.set_value_no_signal(l["energy"])
			light_color.color = l["color"]
			flicker_check.set_pressed_no_signal(l["flicker"])
		"npc":
			var n: Dictionary = data["npcs"][sel_idx]
			npc_name_edit.text = str(n["name"])
			npc_weapon_opt.select(maxi(MapData.NPC_WEAPONS.keys().find(n["weapon"]), 0))
			npc_loot_opt.select(maxi(MapData.NPC_LOOT.keys().find(n["loot"]), 0))
			npc_disp_opt.select(maxi(MapData.NPC_DISPOSITIONS.keys().find(n["disposition"]), 0))
			npc_head_opt.select(clampi(int(n.get("head", -1)) + 1, 0, HeadArt.count()))
			npc_bounty_check.set_pressed_no_signal(bool(n.get("bounty", false)))
			npc_hp_spin.set_value_no_signal(int(n.get("hp", MapData.DEFAULT_NPC_HP)))
			_sync_bounty_check()
		"opening":
			var o: Dictionary = data["openings"][sel_idx]
			opening_kind_opt.select(maxi(MapData.OPENING_KINDS.keys().find(o["kind"]), 0))
			opening_width.set_value_no_signal(o["width"])
	_ui_lock = false
	sel_bar.visible = sel_kind != ""
	_update_clip_buttons()
	_update_light_box()
	overlay.queue_redraw()


## Light settings are shown only for a selected light, or with the Light tool (settings for new lights).
func _update_light_box() -> void:
	if light_box != null:
		light_box.visible = sel_kind == "light" or cur_tool == Tool.LIGHT
	if terrain_bar != null:
		terrain_bar.visible = sel_kind == "polygon" or cur_tool == Tool.POLYGON or cur_tool == Tool.RECT
	if roof_bar != null:
		roof_bar.visible = sel_kind == "roof" or cur_tool == Tool.ROOF
	if wall_bar != null:
		wall_bar.visible = sel_kind == "wall" or cur_tool == Tool.WALL or cur_tool == Tool.RECT
	if prop_bar != null:
		prop_bar.visible = sel_kind == "prop" or cur_tool == Tool.PROP
		_update_prop_loot_row()
	if opening_bar != null:
		opening_bar.visible = sel_kind == "opening" or cur_tool == Tool.OPENING
	if npc_bar != null:
		npc_bar.visible = sel_kind == "npc" or cur_tool == Tool.NPC
		patrol_btn.disabled = sel_kind != "npc"
		clear_patrol_btn.disabled = sel_kind != "npc" or data["npcs"][sel_idx]["patrol"].is_empty()


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


## Small preview of a hat/hair style (front pointing up), rendered once off-screen and cached.
func _head_icon(idx: int) -> Texture2D:
	if _head_icons.has(idx):
		return _head_icons[idx]
	var vp := SubViewport.new()
	vp.size = Vector2i(PROP_ICON_PX, PROP_ICON_PX)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var node := Node2D.new()
	node.position = Vector2(PROP_ICON_PX, PROP_ICON_PX) * 0.5
	node.draw.connect(func() -> void: HeadArt.draw(node, idx, Vector2.ZERO, -PI * 0.5, 1.1))
	vp.add_child(node)
	add_child(vp)
	var tex := vp.get_texture()
	_head_icons[idx] = tex
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


## Themes listed in the Theme dropdown (every real theme; "all" is only a palette filter).
func _theme_keys() -> Array:
	return MapData.THEME_ORDER.filter(func(t) -> bool: return MapData.THEMES.has(t))


## Points the Theme dropdown at the map's current background (prefers the map's own theme
## when several themes share the same ground, e.g. grass).
func _sync_theme_opt() -> void:
	var keys := _theme_keys()
	var bg := str(data.get("background", ""))
	var cur := str(data.get("theme", ""))
	var idx := -1
	if keys.has(cur) and MapData.THEMES[cur]["background"] == bg:
		idx = keys.find(cur)
	else:
		for i in keys.size():
			if MapData.THEMES[keys[i]]["background"] == bg:
				idx = i
				break
	theme_opt.select(idx)  # -1 = custom background not matching any theme


## Changes only the map's base background (the ground under everything).
func _on_theme_selected(i: int) -> void:
	var t: String = _theme_keys()[i]
	push_undo()
	data["theme"] = t
	data["background"] = MapData.THEMES[t]["background"]
	renderer.rebuild_terrain()


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
	drawing_patrol = false
	rect_active = false
	tool_buttons[t].set_pressed_no_signal(true)
	if t == Tool.ROOF and roof_toggle != null and not roof_toggle.button_pressed:
		roof_toggle.button_pressed = true  # drawing a roof you can't see makes no sense
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
		_update_prop_loot_row()  # Prop tool: the prop about to be placed may now hold loot
		return
	push_undo()
	data["props"][sel_idx]["type"] = prop_keys[i]
	if not MapData.LOOT_PROPS.has(prop_keys[i]):
		data["props"][sel_idx]["loot"] = "none"  # a tree can't hold loot
	renderer.rebuild_props()
	_update_prop_loot_row()


func _on_prop_loot(i: int) -> void:
	if _ui_lock or sel_kind != "prop":
		return
	push_undo()
	data["props"][sel_idx]["loot"] = MapData.NPC_LOOT.keys()[i]


func _on_prop_locked(on: bool) -> void:
	if _ui_lock or sel_kind != "prop":
		return
	push_undo()
	data["props"][sel_idx]["locked"] = on


## The Loot dropdown shows for barrels/crates: the selected prop, or the one the Prop tool will place.
func _update_prop_loot_row() -> void:
	if prop_loot_panel == null:
		return
	var key := ""
	if sel_kind == "prop":
		key = str(data["props"][sel_idx]["type"])
	elif not prop_keys.is_empty():
		key = _prop_key()
	prop_loot_panel.visible = prop_bar.visible and MapData.LOOT_PROPS.has(key)
	prop_lock_check.visible = key == "crate" or key == "trunk"  # barrels have no lid to lock


func _on_prop_scale(v: float) -> void:
	if _ui_lock or sel_kind != "prop":
		return
	push_undo("prop_scale")
	data["props"][sel_idx]["scale"] = v
	renderer.update_prop(sel_idx)


func _on_prop_rot(v: float) -> void:
	if _ui_lock or sel_kind != "prop":
		return
	push_undo("prop_rot")
	data["props"][sel_idx]["rot"] = deg_to_rad(v)
	renderer.update_prop(sel_idx)


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


func _npc_name() -> String:
	var t := npc_name_edit.text.strip_edges()
	return t if t != "" else "NPC"


func _on_npc_changed() -> void:
	if _ui_lock or sel_kind != "npc":
		_sync_bounty_check()  # NPC tool: the box follows the attitude picked for the next NPC
		return
	push_undo("npc")
	var n: Dictionary = data["npcs"][sel_idx]
	n["name"] = _npc_name()
	n["weapon"] = MapData.NPC_WEAPONS.keys()[maxi(npc_weapon_opt.selected, 0)]
	n["loot"] = MapData.NPC_LOOT.keys()[maxi(npc_loot_opt.selected, 0)]
	n["disposition"] = MapData.NPC_DISPOSITIONS.keys()[maxi(npc_disp_opt.selected, 0)]
	n["head"] = npc_head_opt.selected - 1
	n["hp"] = int(npc_hp_spin.value)
	n["bounty"] = npc_bounty_check.button_pressed and n["disposition"] == "hostile"
	_sync_bounty_check()
	renderer.rebuild_npcs()


## The Bounty box only applies to hostile NPCs: it's disabled (and cleared) for other attitudes.
func _sync_bounty_check() -> void:
	if npc_bounty_check == null:
		return
	var hostile: bool = MapData.NPC_DISPOSITIONS.keys()[maxi(npc_disp_opt.selected, 0)] == "hostile"
	npc_bounty_check.disabled = not hostile
	if not hostile:
		npc_bounty_check.set_pressed_no_signal(false)


func _start_patrol_draw() -> void:
	if sel_kind != "npc":
		return
	_set_tool(Tool.NPC)  # resets any half-drawn path
	drawing_patrol = true


func _clear_patrol() -> void:
	if sel_kind != "npc":
		return
	push_undo()
	data["npcs"][sel_idx]["patrol"] = PackedVector2Array()
	renderer.rebuild_npcs()
	_sync_ui()


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
		status_label.text = "x %d  y %d   zoom %d%%   |   %s" % [m.x, m.y, camera.zoom.x * 100.0, PATROL_HINT if drawing_patrol else TOOL_HINTS[cur_tool]]
	overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventKey and event.pressed:
		# Key repeat is only used for rotating (hold Q / E to keep turning).
		if not event.echo or event.keycode == KEY_Q or event.keycode == KEY_E:
			_on_key(event)


func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.pressed:
		get_viewport().gui_release_focus()  # leave the NPC name field so hotkeys work again
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
	if drag == "marquee_pending" and e.position.distance_to(drag_press_screen) >= DRAG_START_PX:
		drag = "marquee"
	if drag == "move_pending" or drag == "vertex_pending":
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			drag = ""
			return
		if e.position.distance_to(drag_press_screen) < DRAG_START_PX:
			return
		push_undo()
		drag_origin = _mw()
		match sel_kind:
			"multi":
				drag_multi_orig = _multi_snapshot()
			"polygon", "roof", "wall":
				drag_orig_points = _sel_points()
			"prop":
				drag_orig_pos = data["props"][sel_idx]["pos"]
			"light":
				drag_orig_pos = data["lights"][sel_idx]["pos"]
			"npc":
				drag_orig_points = _sel_points()
				drag_orig_pos = data["npcs"][sel_idx]["pos"]
			"opening":
				drag_orig_pos = data["openings"][sel_idx]["pos"]
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
		KEY_C:
			_copy_selected()
			return
		KEY_Q, KEY_E:
			# Rotate the selection by the degrees in the selection bar. Q = left, E = right.
			_rotate_by_field(-1.0 if e.keycode == KEY_Q else 1.0)
			return
		KEY_G:
			if ctrl:
				if e.shift_pressed:
					_ungroup_selected()
				else:
					_group_selected()
			return
		KEY_A:
			if ctrl:  # select everything (visible roofs included)
				_select_many(_objects_in_rect(Rect2(Vector2(-1e6, -1e6), Vector2(2e6, 2e6))))
			return
		KEY_V:
			# Ctrl+V always pastes. Plain V pastes while the Select tool is active (selecting
			# needs it anyway); from any other tool it still switches to Select as before.
			if ctrl or (cur_tool == Tool.SELECT and not clipboard.is_empty()):
				_paste(true)
			else:
				_set_tool(Tool.SELECT)
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
			drawing_patrol = false
			rect_active = false
			if drag == "marquee" or drag == "marquee_pending":
				drag = ""  # cancel the selection box
			_select("", -1)
		KEY_BRACKETRIGHT:
			_reorder(1)
		KEY_BRACKETLEFT:
			_reorder(-1)
		KEY_F:
			_fit_camera()
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
		KEY_N:
			_set_tool(Tool.NPC)
		KEY_D:
			_set_tool(Tool.OPENING)
		KEY_H:
			_set_tool(Tool.ROOF)


func _left_press(e: InputEventMouseButton) -> void:
	var pos := _mw()
	var sp := _snap(pos)
	match cur_tool:
		Tool.SELECT:
			_select_press(pos, e.double_click)
		Tool.POLYGON, Tool.WALL, Tool.ROOF:
			_path_click(sp)
		Tool.RECT:
			rect_start = sp
			rect_active = true
		Tool.PROP:
			_place_prop(sp)
		Tool.LIGHT:
			_place_light(sp)
		Tool.NPC:
			if drawing_patrol:
				_path_click(sp)
			else:
				_place_npc(sp)
		Tool.OPENING:
			_place_opening(pos)
		Tool.SPAWN:
			push_undo()
			data["spawn"] = sp


func _left_release() -> void:
	if rect_active:
		_finish_rect()
	if drag == "move":
		_do_move(_mw(), true)
	if drag == "marquee":
		_finish_marquee()
	elif drag == "marquee_pending":
		# Plain click (no drag) on a floor / roof area or on empty ground.
		if _pending_hit.is_empty():
			if not Input.is_key_pressed(KEY_SHIFT):
				_select("", -1)
		elif Input.is_key_pressed(KEY_SHIFT):
			_toggle_in_selection(_pending_hit[0], _pending_hit[1])
		else:
			_select_many(_with_group(_pending_hit[0], _pending_hit[1]))
		_pending_hit = []
	if drag == "move" or drag == "vertex" or drag == "move_pending" or drag == "vertex_pending" or drag == "marquee" or drag == "marquee_pending":
		drag = ""


func _right_press() -> void:
	if cur_points.size() > 0:
		_finish_path(cur_tool == Tool.POLYGON)
		return
	if drawing_patrol:
		drawing_patrol = false  # right-click with no points cancels patrol drawing
		return
	if cur_tool == Tool.SELECT and _has_points():
		var pts := _sel_points()
		var vi := _vertex_at(pts, _mw())
		var min_pts := 3 if sel_kind == "polygon" or sel_kind == "roof" else 2
		if vi >= 0 and pts.size() > min_pts:
			push_undo()
			var np := PackedVector2Array(pts)
			np.remove_at(vi)
			_set_sel_points(np)
			return
	_select("", -1)


func _select_press(pos: Vector2, dbl: bool) -> void:
	if _has_points():
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
	drag_press_screen = get_viewport().get_mouse_position()
	drag_origin = pos
	var shift := Input.is_key_pressed(KEY_SHIFT)
	# Empty ground, or a floor / roof area that isn't selected yet: dragging draws a selection
	# box (a plain click still selects the area, or clears the selection on empty ground).
	if hit.is_empty() or ((hit[0] == "polygon" or hit[0] == "roof") and not _is_selected(hit[0], hit[1])):
		_pending_hit = hit
		marquee_start = pos
		drag = "marquee_pending"
		return
	if shift:
		_toggle_in_selection(hit[0], hit[1])
		return
	if not _is_selected(hit[0], hit[1]):
		_select_many(_with_group(hit[0], hit[1]))  # clicking one member selects its whole group
	# A plain click only selects. Moving starts once the mouse has dragged DRAG_START_PX.
	drag = "move_pending"
	if sel_kind == "multi":
		drag_multi_orig = _multi_snapshot()
		return
	match sel_kind:
		"polygon", "roof", "wall":
			drag_orig_points = _sel_points()
		"prop":
			drag_orig_pos = data["props"][sel_idx]["pos"]
		"light":
			drag_orig_pos = data["lights"][sel_idx]["pos"]
		"npc":
			drag_orig_points = _sel_points()
			drag_orig_pos = data["npcs"][sel_idx]["pos"]
		"opening":
			drag_orig_pos = data["openings"][sel_idx]["pos"]


## Moves the selection with the cursor. Follows the mouse exactly while dragging;
## with `snap` true (on release) the result is aligned to the grid.
func _do_move(pos: Vector2, snap: bool = false) -> void:
	var delta := pos - drag_origin
	if sel_kind == "multi":
		if snap and _snap_on() and not multi.is_empty():
			var a := _item_anchor(multi[0][0], drag_multi_orig[0])
			delta = _snap(a + delta) - a
		_move_multi(delta)
		return
	if snap and _snap_on():
		match sel_kind:
			"polygon", "roof", "wall":
				if drag_orig_points.size() > 0:
					delta = _snap(drag_orig_points[0] + delta) - drag_orig_points[0]
			"prop", "light", "npc":
				delta = _snap(drag_orig_pos + delta) - drag_orig_pos
	match sel_kind:
		"polygon", "roof", "wall":
			var np := PackedVector2Array()
			for p in drag_orig_points:
				np.append(p + delta)
			_set_sel_points(np)
		"prop":
			data["props"][sel_idx]["pos"] = drag_orig_pos + delta
			renderer.update_prop(sel_idx)
		"light":
			data["lights"][sel_idx]["pos"] = drag_orig_pos + delta
			renderer.update_light(sel_idx)
		"opening":
			# Slides along (and snaps to) the nearest wall; stays where it is dropped if no wall is close.
			var o: Dictionary = data["openings"][sel_idx]
			var target := drag_orig_pos + delta
			var s := _wall_snap(target)
			o["pos"] = s.get("pos", target)
			if not s.is_empty():
				o["rot"] = s["rot"]
				o["thick"] = s["thick"]
			renderer.rebuild_openings()
		"npc":
			# The patrol area travels with the NPC.
			var moved := PackedVector2Array()
			for p in drag_orig_points:
				moved.append(p + delta)
			data["npcs"][sel_idx]["pos"] = drag_orig_pos + delta
			data["npcs"][sel_idx]["patrol"] = moved
			renderer.update_npc(sel_idx)


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
	if drawing_patrol:
		drawing_patrol = false
		if pts.size() >= 3 and sel_kind == "npc":
			push_undo()
			data["npcs"][sel_idx]["patrol"] = pts
			renderer.rebuild_npcs()
			_set_tool(Tool.SELECT)
			_sync_ui()
		return
	if cur_tool == Tool.POLYGON:
		if pts.size() < 3:
			return
		push_undo()
		data["polygons"].append(MapData.new_poly(_terrain_key(), pts))
		renderer.rebuild_terrain()
		_select("polygon", data["polygons"].size() - 1)
	elif cur_tool == Tool.ROOF:
		if pts.size() < 3:
			return
		push_undo()
		data["roofs"].append(MapData.new_roof(_roof_key(), pts))
		renderer.rebuild_roofs()
		_select("roof", data["roofs"].size() - 1)
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
	var loot := "none"
	if MapData.LOOT_PROPS.has(_prop_key()):
		loot = MapData.NPC_LOOT.keys()[maxi(prop_loot_opt.selected, 0)]
	var lock_it := prop_lock_check.button_pressed and (_prop_key() == "crate" or _prop_key() == "trunk")
	data["props"].append(MapData.new_prop(_prop_key(), p, sc, rot, -1, loot, lock_it))
	renderer.rebuild_props()
	_select("prop", data["props"].size() - 1)


func _place_light(p: Vector2) -> void:
	push_undo()
	data["lights"].append(MapData.new_light(p, radius_slider.value, light_color.color, energy_slider.value, flicker_check.button_pressed))
	renderer.rebuild_lights()
	_select("light", data["lights"].size() - 1)


func _place_npc(p: Vector2) -> void:
	push_undo()
	data["npcs"].append(MapData.new_npc(
		_npc_name(), p,
		MapData.NPC_WEAPONS.keys()[maxi(npc_weapon_opt.selected, 0)],
		MapData.NPC_LOOT.keys()[maxi(npc_loot_opt.selected, 0)],
		MapData.NPC_DISPOSITIONS.keys()[maxi(npc_disp_opt.selected, 0)],
		PackedVector2Array(), npc_head_opt.selected - 1))
	var placed: Dictionary = data["npcs"][data["npcs"].size() - 1]
	placed["hp"] = int(npc_hp_spin.value)
	placed["bounty"] = npc_bounty_check.button_pressed and placed["disposition"] == "hostile"
	renderer.rebuild_npcs()
	_select("npc", data["npcs"].size() - 1)


const KIND_KEYS := {"polygon": "polygons", "roof": "roofs", "wall": "walls", "prop": "props", "light": "lights", "npc": "npcs", "opening": "openings"}


func _copy_selected() -> void:
	var list := _sel_list()
	if list.is_empty() or drawing_patrol:
		return
	var items: Array = []
	for e in list:
		items.append([e[0], data[KIND_KEYS[e[0]]][e[1]].duplicate(true)])
	clipboard = {"items": items}
	_paste_count = 0
	_update_clip_buttons()


## Pastes the copied object(s). `at_cursor` (keyboard) centres them on the mouse; the toolbar
## button (mouse is over the button) drops them one grid step down-right of the original,
## further each time. Pasted groups become new groups, separate from the originals.
func _paste(at_cursor: bool) -> void:
	if clipboard.is_empty():
		return
	var items: Array = clipboard["items"]
	var delta: Vector2
	if at_cursor:
		delta = _snap(_mw()) - _items_center(items)
	else:
		_paste_count += 1
		delta = Vector2(GRID, GRID) * _paste_count
	push_undo()
	var new_groups := {}  # copied group id -> fresh id
	var next_id := _next_group_id()
	var pasted: Array = []
	var kinds := {}
	for e in items:
		var kind: String = e[0]
		var item := _translated(kind, e[1], delta)
		var g := int(item.get("group", 0))
		if items.size() == 1:
			item.erase("group")  # a lone copy of a group member is just a plain object
		elif g > 0:
			if not new_groups.has(g):
				new_groups[g] = next_id
				next_id += 1
			item["group"] = new_groups[g]
		if kind == "opening" and items.size() == 1:
			# A lone door / window snaps onto the nearest wall at the new spot, like when dragged.
			var s := _wall_snap(item["pos"])
			if not s.is_empty():
				item["pos"] = s["pos"]
				item["rot"] = s["rot"]
				item["thick"] = s["thick"]
		var key: String = KIND_KEYS[kind]
		data[key].append(item)
		pasted.append([kind, data[key].size() - 1])
		kinds[kind] = true
	for k in kinds:
		_rebuild_kind(k)
	if kinds.has("roof") and roof_toggle != null and not roof_toggle.button_pressed:
		roof_toggle.button_pressed = true  # show the roof that was just pasted
	_select_many(pasted)


## Copy of `item` moved by `delta` (points, positions and NPC patrol areas).
func _translated(kind: String, item: Dictionary, delta: Vector2) -> Dictionary:
	var out := item.duplicate(true)
	match kind:
		"polygon", "roof", "wall":
			out["points"] = _moved(item["points"], delta)
		"npc":
			out["pos"] = item["pos"] + delta
			out["patrol"] = _moved(item["patrol"], delta)
		_:
			out["pos"] = item["pos"] + delta
	return out


## Centre of the anchors of [[kind, item], ...].
func _items_center(items: Array) -> Vector2:
	if items.is_empty():
		return Vector2.ZERO
	var r := Rect2(_item_anchor(items[0][0], items[0][1]), Vector2.ZERO)
	for e in items:
		r = r.expand(_item_anchor(e[0], e[1]))
	return r.get_center()


# ------------------------------------------------------------------ multi-selection and groups

## Current selection as [[kind, idx], ...] (one entry for a single selection, none for nothing).
func _sel_list() -> Array:
	if sel_kind == "multi":
		return multi
	if sel_kind == "" or sel_idx < 0:
		return []
	return [[sel_kind, sel_idx]]


## Selects several objects. A single ungrouped object becomes a normal single selection
## (so its settings bar and point handles show).
func _select_many(list: Array) -> void:
	if list.is_empty():
		_select("", -1)
	elif list.size() == 1:
		_select(list[0][0], list[0][1])
	else:
		multi = list
		sel_kind = "multi"
		sel_idx = -1
		_sync_ui()


func _is_selected(kind: String, idx: int) -> bool:
	for e in _sel_list():
		if e[0] == kind and e[1] == idx:
			return true
	return false


## The object plus every other object in its group (just the object when ungrouped).
func _with_group(kind: String, idx: int) -> Array:
	var g := int(data[KIND_KEYS[kind]][idx].get("group", 0))
	if g <= 0:
		return [[kind, idx]]
	var out: Array = []
	for k in KIND_KEYS:
		var arr: Array = data[KIND_KEYS[k]]
		for i in arr.size():
			if int(arr[i].get("group", 0)) == g:
				out.append([k, i])
	return out


func _next_group_id() -> int:
	var hi := 0
	for k in KIND_KEYS:
		for item in data[KIND_KEYS[k]]:
			hi = maxi(hi, int(item.get("group", 0)))
	return hi + 1


## Group: the selected objects then select and move together (and copy as one group).
func _group_selected() -> void:
	var list := _sel_list()
	if list.size() < 2:
		return
	push_undo()
	var g := _next_group_id()
	for e in list:
		data[KIND_KEYS[e[0]]][e[1]]["group"] = g
	_sync_ui()


func _ungroup_selected() -> void:
	var list := _sel_list()
	if not _sel_has_group():
		return
	push_undo()
	for e in list:
		data[KIND_KEYS[e[0]]][e[1]].erase("group")
	_sync_ui()


## True when the whole selection is exactly one group (so "Group" would change nothing).
func _sel_is_one_group() -> bool:
	var list := _sel_list()
	if list.size() < 2:
		return false
	var g := int(data[KIND_KEYS[list[0][0]]][list[0][1]].get("group", 0))
	if g <= 0:
		return false
	for e in list:
		if int(data[KIND_KEYS[e[0]]][e[1]].get("group", 0)) != g:
			return false
	return _with_group(list[0][0], list[0][1]).size() == list.size()


func _sel_has_group() -> bool:
	for e in _sel_list():
		if int(data[KIND_KEYS[e[0]]][e[1]].get("group", 0)) > 0:
			return true
	return false


## Every object fully inside `r` (point objects: their position; shapes: all their points).
## Hidden roofs are skipped.
func _objects_in_rect(r: Rect2) -> Array:
	var out: Array = []
	for k in KIND_KEYS:
		if k == "roof" and not renderer.roofs_visible:
			continue
		var arr: Array = data[KIND_KEYS[k]]
		for i in arr.size():
			var item: Dictionary = arr[i]
			var inside := true
			if k == "polygon" or k == "roof" or k == "wall":
				var pts: PackedVector2Array = item["points"]
				inside = pts.size() > 0
				for p in pts:
					if not r.has_point(p):
						inside = false
						break
			else:
				inside = r.has_point(item["pos"])
			if inside:
				out.append([k, i])
	return out


## Selection box finished: select what it encloses, pulling in the rest of any group touched.
## With Shift held the result is added to the current selection.
func _finish_marquee() -> void:
	var r := Rect2(marquee_start, _mw() - marquee_start).abs()
	var found: Array = _sel_list().duplicate() if Input.is_key_pressed(KEY_SHIFT) else []
	for e in _objects_in_rect(r):
		for m in _with_group(e[0], e[1]):
			if not _list_has(found, m):
				found.append(m)
	_select_many(found)


func _list_has(list: Array, e: Array) -> bool:
	for x in list:
		if x[0] == e[0] and x[1] == e[1]:
			return true
	return false


## Shift-click: adds the object (with its group) to the selection, or removes it if already in.
func _toggle_in_selection(kind: String, idx: int) -> void:
	var list: Array = _sel_list().duplicate()
	var members := _with_group(kind, idx)
	if _list_has(list, [kind, idx]):
		for m in members:
			for j in range(list.size() - 1, -1, -1):
				if list[j][0] == m[0] and list[j][1] == m[1]:
					list.remove_at(j)
	else:
		for m in members:
			if not _list_has(list, m):
				list.append(m)
	_select_many(list)


## Rotates the selection by `angle` radians (positive = clockwise on screen) around the centre of
## its bounding box. Outlines and patrol areas turn with it; props and doors / windows also turn
## their own facing.
func _rotate_selected(angle: float) -> void:
	var list := _sel_list()
	if list.is_empty() or drawing_patrol or drag != "":
		return
	var items: Array = []
	for e in list:
		items.append([e[0], data[KIND_KEYS[e[0]]][e[1]]])
	var c := _items_bounds(items).get_center()
	if list.size() == 1 and (list[0][0] == "prop" or list[0][0] == "opening" or list[0][0] == "light" or list[0][0] == "npc"):
		c = data[KIND_KEYS[list[0][0]]][list[0][1]]["pos"]  # a single object turns on the spot
	push_undo("rotate")  # holding Q / E (key repeat) makes one undo step, not dozens
	for e in list:
		var key: String = KIND_KEYS[e[0]]
		data[key][e[1]] = _rotated_item(e[0], data[key][e[1]], c, angle)
	_refresh_items(list)
	if sel_kind == "prop":
		rot_spin.set_value_no_signal(rad_to_deg(float(data["props"][sel_idx]["rot"])))  # keep the Rotate field in step
	overlay.queue_redraw()


## Rotates by ROTATE_STEP_DEG: `dir` -1 = left (anticlockwise), +1 = right (clockwise).
func _rotate_by_field(dir: float) -> void:
	_rotate_selected(deg_to_rad(ROTATE_STEP_DEG) * dir)


func _rotated_item(kind: String, item: Dictionary, c: Vector2, angle: float) -> Dictionary:
	var out := item.duplicate(true)
	match kind:
		"polygon", "roof", "wall":
			out["points"] = _rotated_pts(item["points"], c, angle)
		"npc":
			out["pos"] = c + (item["pos"] - c).rotated(angle)
			out["patrol"] = _rotated_pts(item["patrol"], c, angle)
		"prop", "opening":
			out["pos"] = c + (item["pos"] - c).rotated(angle)
			out["rot"] = wrapf(float(item["rot"]) + angle, -PI, PI)
		_:
			out["pos"] = c + (item["pos"] - c).rotated(angle)
	return out


func _rotated_pts(pts: PackedVector2Array, c: Vector2, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c).rotated(angle))
	return out


## Shows moved / rotated objects ([[kind, idx], ...]). Props, lights, NPCs and floor polygons
## update just their own node; walls, doors / windows and roofs rebuild their (small) layers once.
func _refresh_items(list: Array) -> void:
	var rebuild := {}
	for e in list:
		match e[0]:
			"prop":
				renderer.update_prop(e[1])
			"light":
				renderer.update_light(e[1])
			"npc":
				renderer.update_npc(e[1])
			"polygon":
				renderer.update_polygon(e[1])
			_:
				rebuild[e[0]] = true
	_rebuild_kinds(rebuild)


## Rebuilds the renderer layers for the given kinds ({kind: true}); walls and openings together.
func _rebuild_kinds(kinds: Dictionary) -> void:
	if kinds.has("wall") or kinds.has("opening"):
		renderer.rebuild_openings()  # also rebuilds the walls
	for k in kinds:
		if k != "wall" and k != "opening":
			_rebuild_kind(k)


func _multi_snapshot() -> Array:
	var out: Array = []
	for e in multi:
		out.append(data[KIND_KEYS[e[0]]][e[1]].duplicate(true))
	return out


## Moves every object in a multi-selection by `delta` from where the drag started.
func _move_multi(delta: Vector2) -> void:
	for i in multi.size():
		var e: Array = multi[i]
		data[KIND_KEYS[e[0]]][e[1]] = _translated(e[0], drag_multi_orig[i], delta)
	_refresh_items(multi)


## Reference point of an object: its position, or the centre of its outline.
func _item_anchor(kind: String, item: Dictionary) -> Vector2:
	if kind == "polygon" or kind == "roof" or kind == "wall":
		var pts: PackedVector2Array = item["points"]
		if pts.is_empty():
			return Vector2.ZERO
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		return r.get_center()
	return item["pos"]


func _moved(pts: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + delta)
	return out


## Copy is only available with something selected; Paste once something has been copied.
func _update_clip_buttons() -> void:
	if copy_btn != null:
		copy_btn.disabled = _sel_list().is_empty() or drawing_patrol
		copy_btn.get_child(0).queue_redraw()
	if paste_btn != null:
		paste_btn.disabled = clipboard.is_empty()
		paste_btn.get_child(0).queue_redraw()


func _delete_selected() -> void:
	var list := _sel_list()
	if list.is_empty() or drawing_patrol:
		return
	push_undo()
	# Remove from the end of each array first so the remaining indices stay valid.
	var sorted: Array = list.duplicate()
	sorted.sort_custom(func(a, b) -> bool: return a[1] > b[1])
	var kinds := {}
	for e in sorted:
		data[KIND_KEYS[e[0]]].remove_at(e[1])
		kinds[e[0]] = true
	_select("", -1)
	for k in kinds:
		_rebuild_kind(k)


func _reorder(dir: int) -> void:
	if sel_kind == "" or sel_kind == "multi" or sel_kind == "light" or sel_kind == "npc" or sel_kind == "opening":
		return
	var key := {"polygon": "polygons", "roof": "roofs", "wall": "walls", "prop": "props"}[sel_kind] as String
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
	# NPC patrol areas
	for n in data["npcs"]:
		var patrol: PackedVector2Array = n["patrol"]
		if patrol.size() < 3:
			continue
		var pcol := Color(0.9, 0.3, 0.3) if n["disposition"] == "hostile" else Color(0.3, 0.85, 0.4)
		if not Geometry2D.triangulate_polygon(patrol).is_empty():
			o.draw_colored_polygon(patrol, Color(pcol, 0.14))
		o.draw_polyline(patrol + PackedVector2Array([patrol[0]]), Color(pcol, 0.8), lw)
		o.draw_dashed_line(n["pos"], patrol[0], Color(pcol, 0.4), lw, 6.0 / z)
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
	if drag == "marquee":
		# Selection box (not snapped, so it follows the mouse exactly).
		var mr := Rect2(marquee_start, _mw() - marquee_start).abs()
		var mc := Color(0.4, 0.85, 1.0)
		o.draw_rect(mr, Color(mc, 0.12))
		o.draw_rect(mr, mc, false, 1.5 / z)
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
		Tool.POLYGON, Tool.WALL, Tool.RECT, Tool.ROOF:
			o.draw_circle(mouse, 3.0 / z, sel_col)
		Tool.OPENING:
			# Preview where the opening will land (snapped onto the nearest wall).
			var raw := _mw()
			var sn := _wall_snap(raw)
			var ghost := MapData.new_opening(_opening_kind(), sn.get("pos", raw), sn.get("rot", 0.0), opening_width.value, sn.get("thick", 12.0))
			var gc := _opening_corners(ghost)
			gc.append(gc[0])
			var gcol := Color(0.4, 1.0, 0.5, 0.9) if not sn.is_empty() else Color(1, 1, 1, 0.5)
			o.draw_polyline(gc, gcol, 2.0 / z)
		Tool.NPC:
			if drawing_patrol:
				o.draw_circle(mouse, 3.0 / z, sel_col)
			else:
				o.draw_arc(mouse, 12.0, 0.0, TAU, 20, Color(1, 1, 1, 0.6), lw)


func _handle(o: Node2D, p: Vector2, z: float) -> void:
	var h := HANDLE_PX / z
	var r := Rect2(p - Vector2(h, h) * 0.5, Vector2(h, h))
	o.draw_rect(r, Color.WHITE)
	o.draw_rect(r, Color.BLACK, false, 1.0 / z)


func _draw_selection(o: Node2D, z: float, lw: float) -> void:
	var col := Color(1.0, 0.85, 0.2)
	if sel_kind == "multi":
		# Outline every selected object (no point handles), plus a dashed box around them all.
		var keep_kind := sel_kind
		var items: Array = []
		for e in multi:
			sel_kind = e[0]
			sel_idx = e[1]
			_draw_selection_outline(o, z, lw)
			items.append([e[0], data[KIND_KEYS[e[0]]][e[1]]])
		sel_kind = keep_kind
		sel_idx = -1
		var box := _items_bounds(items).grow(10.0 / z)
		var dash := 6.0 / z
		var c := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y), box.position])
		for i in 4:
			o.draw_dashed_line(c[i], c[i + 1], Color(col, 0.7), 1.5 / z, dash)
		return
	_draw_selection_outline(o, z, lw, true)


## Bounding box of [[kind, item], ...] (outlines and positions, plus a little for point objects).
func _items_bounds(items: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for e in items:
		var pts := PackedVector2Array()
		if e[0] == "polygon" or e[0] == "roof" or e[0] == "wall":
			pts = e[1]["points"]
		else:
			var at: Vector2 = e[1]["pos"]
			pts = PackedVector2Array([at - Vector2(12, 12), at + Vector2(12, 12)])
		for p in pts:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


## Outline of the object in sel_kind / sel_idx; `handles` adds the white point handles.
func _draw_selection_outline(o: Node2D, z: float, lw: float, handles: bool = false) -> void:
	var col := Color(1.0, 0.85, 0.2)
	match sel_kind:
		"polygon", "roof", "wall":
			if sel_idx < 0 or sel_idx >= data[{"polygon": "polygons", "roof": "roofs", "wall": "walls"}[sel_kind]].size():
				return
			var pts := PackedVector2Array(_sel_points())
			if pts.size() < 2:
				return
			if _sel_closed():
				pts.append(pts[0])
			o.draw_polyline(pts, col, 2.0 / z)
			if handles:
				for p in _sel_points():
					_handle(o, p, z)
		"prop":
			if sel_idx >= data["props"].size():
				return
			var pr: Dictionary = data["props"][sel_idx]
			var rad: float = MapData.PROPS.get(pr["type"], MapData.PROPS["tree"])["radius"] * float(pr["scale"])
			o.draw_arc(pr["pos"], rad + 4.0, 0.0, TAU, 32, col, 2.0 / z)
		"opening":
			if sel_idx >= data["openings"].size():
				return
			var oc := _opening_corners(data["openings"][sel_idx], 3.0)
			oc.append(oc[0])
			o.draw_polyline(oc, col, 2.0 / z)
		"npc":
			if sel_idx >= data["npcs"].size():
				return
			var n: Dictionary = data["npcs"][sel_idx]
			o.draw_arc(n["pos"], 16.0, 0.0, TAU, 24, col, 2.0 / z)
			var patrol := PackedVector2Array(n["patrol"])
			if patrol.size() >= 2:
				patrol.append(patrol[0])
				o.draw_polyline(patrol, col, 2.0 / z)
				if handles:
					for p in n["patrol"]:
						_handle(o, p, z)
		"light":
			if sel_idx >= data["lights"].size():
				return
			var l: Dictionary = data["lights"][sel_idx]
			o.draw_arc(l["pos"], float(l["radius"]), 0.0, TAU, 48, col, lw)
			o.draw_arc(l["pos"], 12.0 / z, 0.0, TAU, 16, col, 2.0 / z)
