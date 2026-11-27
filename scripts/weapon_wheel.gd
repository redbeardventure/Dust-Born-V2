class_name WeaponWheel
extends Control
## Radial weapon picker. Opened from the weapon HUD button; the game is paused while it is up.
## Click a weapon you own to equip it. Esc, Q, right-click or a click outside the ring closes it.

signal chosen(key: String)
signal closed
signal info_requested(key: String)

const INFO_R := 11.0  # radius of the round "i" button in each segment
var info_open := false  # a specs card is showing over the wheel: ignore keys and clicks

const R_IN := 100.0
const R_OUT := 225.0
const GAP := 0.05  # radians left empty between segments

var player: Player
var keys: Array = []
var _hover := -1


func setup(p: Player, weapon_keys: Array) -> void:
	player = p
	keys = weapon_keys
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hover = maxi(keys.find(Player.weapon), 0)


func _step() -> float:
	return TAU / float(maxi(keys.size(), 1))


## Segment i is centred at angle -90 degrees + i steps, so the first weapon sits at the top.
func _seg_angle(i: int) -> float:
	return -PI * 0.5 + float(i) * _step()


func _index_at(pos: Vector2) -> int:
	var d := pos - size * 0.5
	if d.length() < R_IN or d.length() > R_OUT:
		return -1
	var a := fposmod(d.angle() + PI * 0.5, TAU)
	return int(roundf(a / _step())) % keys.size()


## Centre of segment i's info button: towards the outer edge, to one side of the weapon icon.
func _info_pos(i: int) -> Vector2:
	var u := Vector2(cos(_seg_angle(i)), sin(_seg_angle(i)))
	return size * 0.5 + u * (R_IN + R_OUT) * 0.5 + u * 42.0 + u.orthogonal() * 34.0


## Index of the segment whose info button is at `pos`, or -1.
func _info_index_at(pos: Vector2) -> int:
	for i in keys.size():
		if Weapons.is_ranged(keys[i]) and pos.distance_to(_info_pos(i)) <= INFO_R + 3.0:
			return i
	return -1


func _owned(key: String) -> bool:
	return player.has_weapon(key)


func _ammo_text(key: String) -> String:
	if not Weapons.is_ranged(key):
		return ""
	var mag: int = player.mag(key)
	return "%d / %d" % [int(player._ammo.get(key, mag)), mag]


func _input(event: InputEvent) -> void:
	if info_open:
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_Q):
		get_viewport().set_input_as_handled()
		closed.emit()


func _gui_input(event: InputEvent) -> void:
	if info_open:
		return
	if event is InputEventMouseMotion:
		var i := _index_at(event.position)
		if i != _hover:
			_hover = i
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT:
			var info := _info_index_at(event.position)
			if info >= 0:
				info_requested.emit(keys[info])
				return
			var i := _index_at(event.position)
			if i >= 0 and _owned(keys[i]):
				chosen.emit(keys[i])
			elif i < 0:
				closed.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			closed.emit()


func _segment_polygon(i: int) -> PackedVector2Array:
	var c := size * 0.5
	var a0 := _seg_angle(i) - _step() * 0.5 + GAP
	var a1 := _seg_angle(i) + _step() * 0.5 - GAP
	var pts := PackedVector2Array()
	const N := 14
	for k in N + 1:
		var a := lerpf(a0, a1, float(k) / N)
		pts.append(c + Vector2(cos(a), sin(a)) * R_OUT)
	for k in N + 1:
		var a := lerpf(a1, a0, float(k) / N)
		pts.append(c + Vector2(cos(a), sin(a)) * R_IN)
	return pts


func _draw() -> void:
	var c := size * 0.5
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
	draw_arc(c, R_OUT + 14.0, 0.0, TAU, 96, Color(1, 1, 1, 0.8), 1.5)
	draw_arc(c, R_IN - 14.0, 0.0, TAU, 64, Color(1, 1, 1, 0.8), 1.5)
	for i in keys.size():
		var key: String = keys[i]
		var owned := _owned(key)
		var poly := _segment_polygon(i)
		var hot := i == _hover and owned
		draw_colored_polygon(poly, Color(1, 1, 1, 0.34 if hot else 0.16))
		var mid := c + Vector2(cos(_seg_angle(i)), sin(_seg_angle(i))) * (R_IN + R_OUT) * 0.5
		Weapons.draw_icon_at(self, key, mid - Vector2(0, 8), 74.0)
		if not owned:
			draw_colored_polygon(poly, Color(0.05, 0.05, 0.06, 0.62))  # dim: not found yet
		var closed_poly := PackedVector2Array(poly)
		closed_poly.append(poly[0])
		var current := key == Player.weapon
		draw_polyline(closed_poly, Color(1.0, 0.9, 0.4, 0.95) if current else Color(1, 1, 1, 0.35), 2.5 if current else 1.0)
		if Weapons.is_ranged(key):
			var ip := _info_pos(i)
			draw_circle(ip, INFO_R, Color(0.1, 0.12, 0.16, 0.9))
			draw_arc(ip, INFO_R, 0.0, TAU, 20, Color(1, 1, 1, 0.85), 1.5)
			draw_string(font, ip + Vector2(-INFO_R, 5.0), "i", HORIZONTAL_ALIGNMENT_CENTER, INFO_R * 2.0, 15, Color.WHITE)
	# Centre: the highlighted weapon's name.
	var shown: String = keys[_hover] if _hover >= 0 and _hover < keys.size() else Player.weapon
	draw_string(font, c + Vector2(-90, -2), Weapons.label(shown), HORIZONTAL_ALIGNMENT_CENTER, 180, 26, Color.WHITE)
	if not _owned(shown):
		draw_string(font, c + Vector2(-90, 26), "Not found yet", HORIZONTAL_ALIGNMENT_CENTER, 180, 16, Color(1, 1, 1, 0.75))
