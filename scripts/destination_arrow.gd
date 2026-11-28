class_name DestinationArrow
extends Control
## HUD arrow that slides around the screen border and points at the nearest map destination.
## Hidden while the destination itself is on screen.

const MARGIN := 34.0        # distance from the screen edge to the arrow's centre
const ON_SCREEN_PAD := 24.0 # the destination counts as visible when this far inside the edge

var player: Node2D
var targets: Array = []     # world-space centres of the destination areas

var _pos := Vector2.ZERO
var _angle := 0.0
var _show := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var was := _show
	_show = _update()
	if _show or was:
		queue_redraw()


## Works out where the arrow sits and which way it points. False when there is nothing to show.
func _update() -> bool:
	if player == null or not is_instance_valid(player) or targets.is_empty():
		return false
	var from := player.global_position
	var best: Vector2 = targets[0]
	for t in targets:
		if from.distance_to(t) < from.distance_to(best):
			best = t
	var screen: Vector2 = get_viewport().get_canvas_transform() * best
	var size_px := get_viewport_rect().size
	var centre := size_px * 0.5
	if Rect2(Vector2.ONE * ON_SCREEN_PAD, size_px - Vector2.ONE * ON_SCREEN_PAD * 2.0).has_point(screen):
		return false
	var v := screen - centre
	if v.length() < 1.0:
		return false
	var half := centre - Vector2.ONE * MARGIN
	var tx := half.x / absf(v.x) if absf(v.x) > 0.001 else INF
	var ty := half.y / absf(v.y) if absf(v.y) > 0.001 else INF
	_pos = centre + v * minf(tx, ty)
	_angle = v.angle()
	return true


func _draw() -> void:
	if not _show:
		return
	var pts := PackedVector2Array([Vector2(20, 0), Vector2(-12, -15), Vector2(-4, 0), Vector2(-12, 15)])
	draw_set_transform(_pos, _angle)
	var outline := PackedVector2Array([Vector2(24, 0), Vector2(-16, -19), Vector2(-7, 0), Vector2(-16, 19)])
	draw_colored_polygon(outline, Color(0, 0, 0, 0.7))
	draw_colored_polygon(pts, Color(1.0, 0.82, 0.2, 0.95))
	draw_set_transform(Vector2.ZERO)
