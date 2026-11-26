class_name MuzzleFlash
extends Node2D
## Gunshot effect at a muzzle: a short burst of fire (with a quick light flash) and a puff of smoke
## that drifts forward, spreads and fades. Lives in the world, so the smoke stays where the shot
## was fired while the shooter moves on. Frees itself when done.

const FLASH_TIME := 0.08
const SMOKE_TIME := 0.9
const PUFFS := 6

var dir := Vector2.RIGHT
var _t := 0.0
var _light: PointLight2D
var _light_energy := 1.6  # peak brightness of the flash light
var _puffs: Array = []  # [{pos, vel, r, grow, shade}]
var _flames := PackedVector2Array()


static func spawn(parent: Node, at: Vector2, direction: Vector2) -> MuzzleFlash:
	var m := MuzzleFlash.new()
	m.position = at
	m.dir = direction.normalized()
	m.z_index = 16
	parent.add_child(m)
	return m


## Small priming flash and smoke puff at a flintlock's lock (the pan beside the stock).
static func spawn_lock(parent: Node, at: Vector2, direction: Vector2) -> MuzzleFlash:
	var m := spawn(parent, at, direction)
	m.scale = Vector2(0.55, 0.55)
	m.add_puffs(5, 1.3)  # the priming powder throws up a good bit of smoke
	m._light_energy = 2.6  # a brighter priming flash
	m._light.texture_scale = 0.9
	return m


## Adds `count` smoke puffs; `size` scales how big they start and how fast they grow.
func add_puffs(count: int, size: float = 1.0) -> void:
	for i in count:
		_puffs.append({
			"pos": Vector2(randf_range(0.0, 6.0), randf_range(-2.0, 2.0)),
			"vel": Vector2(randf_range(18.0, 55.0), randf_range(-14.0, 14.0)),
			"r": randf_range(2.5, 4.5) * size,
			"grow": randf_range(9.0, 16.0) * size,
			"shade": randf_range(0.62, 0.82),
		})


func _ready() -> void:
	rotation = dir.angle()  # local +x = firing direction
	# Jagged flame shape, slightly different every shot.
	var spikes := 7
	for i in spikes * 2 + 1:
		var a := lerpf(-0.9, 0.9, float(i) / float(spikes * 2))
		var r := (randf_range(9.0, 14.0) if i % 2 == 0 else randf_range(3.0, 5.0)) * (1.0 - absf(a) * 0.5)
		_flames.append(Vector2(cos(a), sin(a)) * r)
	_flames.append(Vector2(-1.5, 0))
	add_puffs(PUFFS)
	_light = PointLight2D.new()
	_light.texture = MapRenderer.light_texture()
	_light.texture_scale = 0.6
	_light.color = Color(1.0, 0.75, 0.35)
	_light.energy = _light_energy
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	_light.energy = maxf(0.0, _light_energy * (1.0 - _t / (FLASH_TIME * 1.5)))
	for p in _puffs:
		p["pos"] += p["vel"] * delta
		p["vel"] *= pow(0.12, delta)  # smoke slows quickly after leaving the barrel
		p["r"] += p["grow"] * delta
	if _t >= SMOKE_TIME:
		queue_free()
	queue_redraw()


func _draw() -> void:
	# Smoke under the flame.
	var fade := 1.0 - _t / SMOKE_TIME
	for p in _puffs:
		var s: float = p["shade"]
		draw_circle(p["pos"], p["r"], Color(s, s, s, 0.45 * fade * fade))
	# Fire: outer orange flame, yellow inner, white-hot core. Only for the first few frames.
	if _t < FLASH_TIME:
		var k := 1.0 - _t / FLASH_TIME
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for v in _flames:
			outer.append(v * (0.7 + 0.3 * k))
			inner.append(v * (0.45 + 0.2 * k))
		draw_colored_polygon(outer, Color(1.0, 0.45, 0.1, 0.85 * k))
		draw_colored_polygon(inner, Color(1.0, 0.85, 0.3, 0.95 * k))
		draw_circle(Vector2(1.5, 0), 2.2, Color(1.0, 1.0, 0.85, k))
