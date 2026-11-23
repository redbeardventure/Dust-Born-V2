class_name YellEffect
extends Node2D
## "YELL FOR HELP" effect (see Combat._try_yell): a shout ring sweeps out from the yelling NPC to
## the edge of its yell circle, a "HELP!" bubble pops up over it, and every NPC that answers gets a
## line from the yeller and a "!" over its head as the ring reaches it. Frees itself when done.

const RING_TIME := 0.9   # seconds for the ring to reach the edge of the yell circle
const LIFE := 2.2        # total seconds on screen
const COL := Color(1.0, 0.8, 0.2)

var radius := 600.0
var yeller: Node2D                  # follows the NPC while it is alive
var responders: Array = []          # Node2D (may be freed while the effect plays)
var _origin := Vector2.ZERO
var _resp_pos: Array = []           # where each responder stood when the yell went out
var _t := 0.0


static func spawn(parent: Node, from: Node2D, yell_radius: float, answering: Array) -> void:
	var fx := YellEffect.new()
	fx.radius = yell_radius
	fx.yeller = from
	fx.responders = answering.duplicate()
	fx._origin = from.global_position
	for r in answering:
		fx._resp_pos.append((r as Node2D).global_position)
	parent.add_child(fx)


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO  # drawn in world coordinates
	z_index = 25
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED  # stays readable on night maps
	material = mat


func _process(delta: float) -> void:
	_t += delta
	if is_instance_valid(yeller):
		_origin = yeller.global_position
	for i in responders.size():
		if is_instance_valid(responders[i]):
			_resp_pos[i] = (responders[i] as Node2D).global_position
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := clampf((LIFE - _t) / 0.5, 0.0, 1.0)  # everything fades over the last half second
	var ring_k := clampf(_t / RING_TIME, 0.0, 1.0)
	var r := radius * (1.0 - pow(1.0 - ring_k, 2.0))  # ease out
	# Shout rings: a bright leading ring and two trailing echoes, plus the full yell circle.
	draw_arc(_origin, radius, 0.0, TAU, 96, Color(COL, 0.35 * fade), 2.0)
	draw_circle(_origin, r, Color(COL, 0.08 * fade * (1.0 - ring_k * 0.5)))
	for k in 3:
		var rr := r - float(k) * 28.0
		if rr > 4.0:
			draw_arc(_origin, rr, 0.0, TAU, 96, Color(COL, (0.9 - 0.28 * k) * fade), 4.0 - k)

	# Answering NPCs: a line from the yeller and a "!" once the ring has reached them.
	var font := ThemeDB.fallback_font
	for i in _resp_pos.size():
		var p: Vector2 = _resp_pos[i]
		if r < _origin.distance_to(p):
			continue
		draw_dashed_line(_origin, p, Color(COL, 0.7 * fade), 2.0, 10.0)
		var pop := clampf((_t - RING_TIME * _origin.distance_to(p) / radius) / 0.2, 0.0, 1.0)
		var top := p + Vector2(0, -34.0 - 6.0 * pop)
		draw_circle(top, 11.0 * pop, Color(0.1, 0.07, 0.02, 0.85 * fade))
		draw_arc(top, 11.0 * pop, 0.0, TAU, 20, Color(COL, fade), 2.0)
		draw_string(font, top + Vector2(-20, 6), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, int(16 * pop) + 1, Color(1, 0.95, 0.6, fade))

	# "HELP!" speech bubble over the yeller, with a little bounce.
	var bounce := sin(minf(_t * 10.0, PI)) * 6.0
	var text := "HELP!"
	var fs := 18
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var box := Rect2(_origin + Vector2(-size.x * 0.5 - 8.0, -62.0 - bounce), Vector2(size.x + 16.0, size.y + 6.0))
	draw_rect(box, Color(0.12, 0.05, 0.02, 0.9 * fade))
	draw_rect(box, Color(COL, fade), false, 2.0)
	var tail := PackedVector2Array([box.position + Vector2(box.size.x * 0.5 - 6.0, box.size.y),
			box.position + Vector2(box.size.x * 0.5 + 6.0, box.size.y), _origin + Vector2(0, -22)])
	draw_colored_polygon(tail, Color(COL, fade))
	draw_string(font, box.position + Vector2(8.0, size.y - 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.7, fade))
