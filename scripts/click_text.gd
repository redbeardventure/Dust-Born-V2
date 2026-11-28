class_name ClickText
extends Node2D
## Small "click" that pops up above the player when the trigger is pulled on an empty gun.
## Rises a little, fades, then frees itself.

const LIFE := 0.7
const RISE := 14.0
const SIZE := 16

var _t := 0.0


## Shows "click" over `who`. Ignored while a previous one is still showing (a held button would spam it).
static func spawn(who: Node2D) -> void:
	for c in who.get_children():
		if c is ClickText:
			return
	var fx := ClickText.new()
	who.add_child(fx)


func _ready() -> void:
	z_index = 25
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED  # stays readable on night maps
	material = mat


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	# Keep upright and above the head even if the player node turns.
	global_rotation = 0.0
	queue_redraw()


func _draw() -> void:
	var k := _t / LIFE
	var a := 1.0 - maxf(0.0, (k - 0.5) / 0.5)
	var font := ThemeDB.fallback_font
	var pos := Vector2(-30, -34.0 - RISE * k)
	draw_string(font, pos + Vector2(1, 1), "click", HORIZONTAL_ALIGNMENT_CENTER, 60, SIZE, Color(0, 0, 0, 0.7 * a))
	draw_string(font, pos, "click", HORIZONTAL_ALIGNMENT_CENTER, 60, SIZE, Color(1.0, 0.95, 0.75, a))
