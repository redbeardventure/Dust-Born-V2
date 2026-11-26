class_name DustPuff
extends Node2D
## A puff of dust kicked up where someone falls. The cloud is thrown along `dir` (the way the
## killing shot was travelling), then slows, spreads and fades. Frees itself.

const LIFE := 1.0
const PUFFS := 12

var dir := Vector2.RIGHT
var _t := 0.0
var _puffs: Array = []  # [{pos, vel, r, grow, shade}]


static func spawn(parent: Node, at: Vector2, direction: Vector2) -> DustPuff:
	var d := DustPuff.new()
	d.position = at
	d.dir = direction.normalized() if direction.length() > 0.01 else Vector2.ZERO
	d.z_index = 14
	parent.add_child(d)
	return d


func _ready() -> void:
	for i in PUFFS:
		var side := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 18.0  # loose scatter
		var push := dir * randf_range(40.0, 110.0)  # thrown the way the bullet was going
		_puffs.append({
			"pos": Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0)),
			"vel": push + side,
			"r": randf_range(3.5, 6.5),
			"grow": randf_range(10.0, 20.0),
			"shade": randf_range(0.5, 0.62),
		})


func _process(delta: float) -> void:
	_t += delta
	for p in _puffs:
		p["pos"] += p["vel"] * delta
		p["vel"] *= pow(0.08, delta)  # drag: the cloud slows quickly
		p["r"] += p["grow"] * delta
	if _t >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - _t / LIFE
	for p in _puffs:
		var s: float = p["shade"]
		draw_circle(p["pos"], p["r"], Color(s + 0.12, s + 0.05, s - 0.06, 0.5 * fade * fade))
