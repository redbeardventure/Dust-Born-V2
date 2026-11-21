class_name Projectile
extends Node2D
## A shot fired by the player or an NPC. Flies in a straight line until it hits a wall, a closed door,
## a solid prop or a character (group "combatants"), or runs out of range.
## Characters it can hit must have `take_damage(amount: int, from: Node)`.

const HIT_RADIUS := 10.0
const WORLD_MASK := 1  # walls, props, doors. Water blockers are on layer 2 so shots fly over water.

var kind := "bullet"  # bullet | pellet
var velocity := Vector2.ZERO
var damage := 10
var max_range := 500.0
var shooter: Node = null

var _travelled := 0.0


## Fires one shot of `weapon` (a key in Weapons.RANGED) into `parent`: a single projectile,
## or `pellets` projectiles fanned out within the spread (shotgun).
static func fire(parent: Node, weapon: String, from: Vector2, dir: Vector2, by: Node) -> void:
	var w: Dictionary = Weapons.RANGED[weapon]
	var spread: float = w["spread"]
	var speed: float = w["speed"]
	for i in int(w.get("pellets", 1)):
		var p := Projectile.new()
		p.kind = w["shot"]
		# Pellets also vary a little in speed so the pattern spreads out along its path.
		var v := speed * (randf_range(0.9, 1.1) if p.kind == "pellet" else 1.0)
		p.velocity = dir.normalized().rotated(randf_range(-spread, spread)) * v
		p.damage = int(w["damage"])
		p.max_range = float(w["range"]) * (randf_range(0.85, 1.0) if p.kind == "pellet" else 1.0)
		p.shooter = by
		p.position = from + dir.normalized() * 14.0
		p.rotation = p.velocity.angle()
		p.z_index = 15
		parent.add_child(p)


func _physics_process(delta: float) -> void:
	var a := global_position
	var b := a + velocity * delta

	# Walls and other solid world geometry. Character bodies are excluded and handled below.
	var space := get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(a, b, WORLD_MASK)
	var exclude: Array[RID] = []
	for n in get_tree().get_nodes_in_group("combatants"):
		if n is CollisionObject2D:
			exclude.append(n.get_rid())
	q.exclude = exclude
	var wall := space.intersect_ray(q)
	var end: Vector2 = wall["position"] if not wall.is_empty() else b

	# Nearest character along the segment that ends at the wall (if any).
	var best: Object = null  # untyped use: take_damage() is a script method
	var best_d := INF
	for n in get_tree().get_nodes_in_group("combatants"):
		if n == shooter or not (n is Node2D) or not n.has_method("take_damage"):
			continue
		var c: Vector2 = n.global_position
		var hit := Geometry2D.get_closest_point_to_segment(c, a, end)
		if hit.distance_to(c) <= HIT_RADIUS:
			var d := a.distance_to(hit)
			if d < best_d:
				best_d = d
				best = n
	if best != null:
		best.call("take_damage", damage, shooter if is_instance_valid(shooter) else null)
		queue_free()
		return
	if not wall.is_empty():
		# Breakable props (barrels): the collision body is a child of the prop node.
		var col: Object = wall.get("collider")
		var owner_node: Node = (col as Node).get_parent() if col is Node else null
		if owner_node != null and owner_node.is_in_group("breakable"):
			owner_node.call("take_damage", damage, shooter if is_instance_valid(shooter) else null)
		queue_free()
		return

	global_position = b
	_travelled += velocity.length() * delta
	if _travelled >= max_range:
		queue_free()


func _ready() -> void:
	# Glowing look: additive blending and unshaded, so shots stay bright on dark (night) maps
	# instead of being dimmed by the ambient darkness.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	# Bullets also light the ground they pass over. Pellets skip this (7 per shot would be costly).
	if kind == "bullet":
		var glow := PointLight2D.new()
		glow.texture = MapRenderer.light_texture()
		glow.texture_scale = 0.3
		glow.color = Color(1.0, 0.8, 0.45)
		glow.energy = 0.9
		add_child(glow)


## Drawn in local space: +x is the direction of travel. Layers: soft halo, long fading tracer, bright core.
func _draw() -> void:
	var pellet := kind == "pellet"
	var tail := 14.0 if pellet else 26.0
	var w := 2.5 if pellet else 3.5
	var core := 2.2 if pellet else 3.0
	# Halo
	draw_circle(Vector2.ZERO, core * 3.0, Color(1.0, 0.6, 0.2, 0.12))
	draw_circle(Vector2.ZERO, core * 1.8, Color(1.0, 0.75, 0.3, 0.25))
	# Tracer: wide faint streak plus a thinner bright one, both fading toward the tail
	var streak := PackedVector2Array([Vector2(-tail, 0), Vector2(0, 0)])
	var fade := PackedColorArray([Color(1.0, 0.55, 0.15, 0.0), Color(1.0, 0.7, 0.25, 0.55)])
	draw_polyline_colors(streak, fade, w * 2.0)
	draw_polyline_colors(PackedVector2Array([Vector2(-tail * 0.7, 0), Vector2(0, 0)]),
			PackedColorArray([Color(1.0, 0.85, 0.5, 0.0), Color(1.0, 0.95, 0.75, 0.95)]), w)
	# Core
	draw_circle(Vector2.ZERO, core, Color(1.0, 0.97, 0.85))
