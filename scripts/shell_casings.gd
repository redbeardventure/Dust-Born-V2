class_name ShellCasings
extends Node2D
## Spent cartridges thrown out when a gun is reloaded. Each casing flies out to the shooter's
## right, tumbles, bounces on the ground (faked with a height value, since the view is top-down),
## then lies there for a while and fades. One node handles the whole batch and frees itself.

const GRAVITY := 260.0
const REST_TIME := 4.0  # seconds a casing lies on the ground before fading
const FADE_TIME := 1.0

var _casings: Array = []  # [{pos, vel, h, vh, rot, spin, delay}]
var _kind := "brass"  # brass | shell (shotgun)
var _t := 0.0


## Ejects `count` casings at `at` for a shooter facing `facing`.
static func spawn(parent: Node, at: Vector2, facing: Vector2, count: int, kind: String = "brass") -> ShellCasings:
	if count <= 0:
		return null
	var s := ShellCasings.new()
	s.position = at
	s.z_index = 11  # above the floor, below characters' heads and effects
	s._kind = kind
	var f := facing.normalized()
	var right := Vector2(-f.y, f.x)
	for i in count:
		# Mostly sideways to the right and a little backwards, with some scatter.
		var out := (right * randf_range(0.7, 1.0) - f * randf_range(0.0, 0.5)).normalized()
		out = out.rotated(randf_range(-0.5, 0.5))
		var speed := randf_range(45.0, 95.0)
		var vh := randf_range(60.0, 110.0)
		if kind == "wad":  # blown straight out of the barrel, a little flatter and faster
			out = f.rotated(randf_range(-0.15, 0.15))
			speed = randf_range(130.0, 200.0)
			vh = randf_range(25.0, 55.0)
		s._casings.append({
			"pos": Vector2.ZERO,
			"vel": out * speed,
			"h": 6.0,
			"vh": vh,
			"rot": randf() * TAU,
			"spin": randf_range(-18.0, 18.0),
			"delay": i * 0.06,  # tipped out one after another, not all in one frame
		})
	parent.add_child(s)
	return s


func _process(delta: float) -> void:
	_t += delta
	for c in _casings:
		if _t < c["delay"]:
			continue
		c["pos"] += c["vel"] * delta
		c["rot"] += c["spin"] * delta
		c["vh"] -= GRAVITY * delta
		c["h"] += c["vh"] * delta
		if c["h"] <= 0.0:
			c["h"] = 0.0
			if absf(c["vh"]) > 25.0:  # bounce, losing most of its energy
				c["vh"] = -c["vh"] * 0.35
				c["vel"] *= 0.55
				c["spin"] *= 0.5
			else:  # settled: slide to a stop
				c["vh"] = 0.0
				c["vel"] *= pow(0.02, delta)
				c["spin"] *= pow(0.02, delta)
	if _t > REST_TIME + FADE_TIME + 1.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var alpha := clampf((REST_TIME + FADE_TIME + 1.0 - _t) / FADE_TIME, 0.0, 1.0)
	var body := Color("d4a640") if _kind == "brass" else Color("b8322a")  # brass case or red plastic shell
	var cap := Color("8a6a24") if _kind == "brass" else Color("d4b050")  # rim / brass head
	var length := 5.5 if _kind == "brass" else 8.0
	var width := 2.4 if _kind == "brass" else 3.4
	for c in _casings:
		if _t < c["delay"]:
			continue
		var h: float = c["h"]
		var p: Vector2 = c["pos"]
		draw_circle(p + Vector2(0.8, 1.0), width * 0.8, Color(0, 0, 0, 0.25 * alpha))  # shadow on the ground
		if _kind == "wad":  # scorched black-powder wad: a small dark, ragged clump
			draw_circle(p - Vector2(0, h), 2.4, Color(0.95, 0.94, 0.9, alpha))
			draw_circle(p - Vector2(0, h) + Vector2(0.9, -0.6), 1.4, Color(1.0, 1.0, 1.0, alpha))
			continue
		draw_set_transform(p - Vector2(0, h), c["rot"], Vector2.ONE)  # raised by its height above ground
		draw_rect(Rect2(Vector2(-length * 0.5, -width * 0.5), Vector2(length, width)), Color(body, alpha))
		draw_rect(Rect2(Vector2(length * 0.5 - 1.6, -width * 0.5), Vector2(1.6, width)), Color(cap, alpha))
		draw_set_transform_matrix(Transform2D.IDENTITY)
