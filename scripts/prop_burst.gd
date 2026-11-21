class_name PropBurst
extends Node2D
## A barrel blown apart: a bright flash, wooden staves and splinters flung outwards (bouncing on
## the ground like the shell casings), a hoop ring or two, and a cloud of dust. Frees itself.

const GRAVITY := 300.0
const FLASH_TIME := 0.12
const DUST_TIME := 1.1
const LIFE := 3.5  # staves lie on the ground, then fade

var _t := 0.0
var _scale := 1.0
var _bits: Array = []  # [{pos, vel, h, vh, rot, spin, len, w, col}]
var _dust: Array = []  # [{pos, vel, r, grow}]
var _light: PointLight2D


static func spawn(parent: Node, at: Vector2, size_scale: float = 1.0) -> PropBurst:
	var b := PropBurst.new()
	b.position = at
	b.z_index = 13
	b._scale = size_scale
	parent.add_child(b)
	return b


func _ready() -> void:
	var woods := [Color("7a5530"), Color("5a3a1e"), Color("8a6034")]
	for i in 12:
		var a := randf() * TAU
		var hoop := i < 2  # two dark iron hoop pieces
		_bits.append({
			"pos": Vector2.ZERO,
			"vel": Vector2(cos(a), sin(a)) * randf_range(70.0, 170.0) * _scale,
			"h": 4.0,
			"vh": randf_range(70.0, 150.0),
			"rot": randf() * TAU,
			"spin": randf_range(-16.0, 16.0),
			"len": (randf_range(9.0, 13.0) if i < 8 else randf_range(3.0, 5.0)) * _scale,
			"w": (1.6 if hoop else (3.0 if i < 8 else 1.5)) * _scale,
			"col": Color("2d2d2d") if hoop else woods[i % woods.size()],
		})
	for i in 8:
		var a := randf() * TAU
		_dust.append({
			"pos": Vector2(cos(a), sin(a)) * randf_range(0.0, 6.0),
			"vel": Vector2(cos(a), sin(a)) * randf_range(20.0, 50.0),
			"r": randf_range(5.0, 9.0) * _scale,
			"grow": randf_range(14.0, 24.0) * _scale,
		})
	_light = PointLight2D.new()
	_light.texture = MapRenderer.light_texture()
	_light.texture_scale = 0.9 * _scale
	_light.color = Color(1.0, 0.8, 0.45)
	_light.energy = 1.4
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	_light.energy = maxf(0.0, 1.4 * (1.0 - _t / (FLASH_TIME * 2.0)))
	for b in _bits:
		b["pos"] += b["vel"] * delta
		b["rot"] += b["spin"] * delta
		b["vh"] -= GRAVITY * delta
		b["h"] += b["vh"] * delta
		if b["h"] <= 0.0:
			b["h"] = 0.0
			if absf(b["vh"]) > 30.0:
				b["vh"] = -b["vh"] * 0.3
				b["vel"] *= 0.5
				b["spin"] *= 0.5
			else:
				b["vh"] = 0.0
				b["vel"] *= pow(0.01, delta)
				b["spin"] *= pow(0.01, delta)
	for d in _dust:
		d["pos"] += d["vel"] * delta
		d["vel"] *= pow(0.15, delta)
		d["r"] += d["grow"] * delta
	if _t > LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	# Dust cloud first (under the debris).
	if _t < DUST_TIME:
		var f := 1.0 - _t / DUST_TIME
		for d in _dust:
			draw_circle(d["pos"], d["r"], Color(0.55, 0.47, 0.38, 0.4 * f * f))
	# Flash.
	if _t < FLASH_TIME:
		var k := 1.0 - _t / FLASH_TIME
		draw_circle(Vector2.ZERO, (10.0 + 22.0 * (1.0 - k)) * _scale, Color(1.0, 0.75, 0.35, 0.55 * k))
		draw_circle(Vector2.ZERO, 8.0 * _scale * k, Color(1.0, 0.95, 0.8, k))
	# Staves and splinters.
	var alpha := clampf((LIFE - _t) / 0.8, 0.0, 1.0)
	for b in _bits:
		var p: Vector2 = b["pos"]
		var bl: float = b["len"]
		var w: float = b["w"]
		draw_circle(p + Vector2(1, 1.5), w * 0.8, Color(0, 0, 0, 0.25 * alpha))
		draw_set_transform(p - Vector2(0, b["h"]), b["rot"], Vector2.ONE)
		draw_rect(Rect2(Vector2(-bl * 0.5, -w * 0.5), Vector2(bl, w)), Color(b["col"], alpha))
		draw_set_transform_matrix(Transform2D.IDENTITY)
