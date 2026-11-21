class_name LootDrop
extends Node2D
## Loot left on the ground where a defeated NPC fell: a small bobbing icon with a glow ring.
## The loot's name shows when the player is close. Kinds match MapData.NPC_LOOT.

const LABEL_RANGE := 70.0
const PICKUP_RANGE := 16.0  # gold is collected automatically when the player walks this close
const COLLECT_TIME := 0.8  # "+12" floats up and fades for this long after pickup

var kind := "gold"
var amount := 0  # coins in a gold drop
var _t := 0.0
var _collected := -1.0  # seconds since pickup (-1 = still on the ground)


## `coins` < 0 picks a random amount for gold drops.
static func spawn(parent: Node, loot_kind: String, pos: Vector2, coins: int = -1) -> LootDrop:
	var d := LootDrop.new()
	d.kind = loot_kind
	d.amount = (coins if coins >= 0 else randi_range(5, 25)) if loot_kind == "gold" else 0
	d.position = pos
	d.z_index = 12
	d.add_to_group("loot")
	parent.add_child(d)
	return d


func _ready() -> void:
	# Small light so the drop stays visible on dark maps.
	var glow := PointLight2D.new()
	glow.texture = MapRenderer.light_texture()
	glow.texture_scale = 0.25
	glow.color = Color(1.0, 0.9, 0.55)
	glow.energy = 0.8
	add_child(glow)


func _process(delta: float) -> void:
	_t += delta
	if _collected >= 0.0:
		_collected += delta
		if _collected >= COLLECT_TIME:
			queue_free()
	elif kind == "gold":
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null and p.has_method("add_gold") and p.global_position.distance_to(global_position) < PICKUP_RANGE:
			p.call("add_gold", amount)
			_collected = 0.0
			remove_from_group("loot")
			for ch in get_children():
				if ch is PointLight2D:
					(ch as PointLight2D).visible = false  # the glow goes with the coins
	queue_redraw()


func _draw() -> void:
	if _collected >= 0.0:
		# Picked up: "+12" rises and fades, with a little coin beside it.
		var k := _collected / COLLECT_TIME
		var a := 1.0 - k
		var up := Vector2(0, -10.0 - 22.0 * k)
		var font := ThemeDB.fallback_font
		draw_string(font, up + Vector2(-60, 0), "+%d" % amount, HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1.0, 0.86, 0.3, a))
		draw_circle(up + Vector2(-18, -5), 4.0 * a, Color(0.91, 0.72, 0.19, a))
		return
	var bob := Vector2(0, sin(_t * 3.0) * 2.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_circle(Vector2(0, 7), 7.0, Color(0, 0, 0, 0.3))  # ground shadow
	draw_arc(Vector2.ZERO, 11.0 + pulse * 2.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, 0.35 + pulse * 0.35), 1.5)
	draw_icon(self, kind, bob, 1.0)
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null and p.global_position.distance_to(global_position) < LABEL_RANGE:
		var font := ThemeDB.fallback_font
		var name_txt := str(MapData.NPC_LOOT.get(kind, kind))
		if kind == "gold":
			name_txt += " (%d)" % amount
		draw_string(font, Vector2(-60, -16), name_txt, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(1.0, 0.92, 0.6))


## Draws the icon for a loot kind centred on `c`, roughly 16px across at s = 1.
static func draw_icon(ci: CanvasItem, loot_kind: String, c: Vector2, s: float) -> void:
	var outline := Color(0.1, 0.08, 0.05, 0.9)
	match loot_kind:
		"gold":  # small stack of coins
			for i in 3:
				var o := c + Vector2(-3.0 + i * 3.0, 2.0 - i * 2.5) * s
				ci.draw_circle(o, 4.0 * s, Color("e8b830"))
				ci.draw_arc(o, 4.0 * s, 0.0, TAU, 12, Color("8a6510"), 1.0 * s)
		"potion":  # round flask with a cork
			ci.draw_circle(c + Vector2(0, 2) * s, 5.0 * s, Color("d04060"))
			ci.draw_rect(Rect2(c + Vector2(-1.5, -6) * s, Vector2(3, 4) * s), Color("c8d4dc"))
			ci.draw_rect(Rect2(c + Vector2(-2, -8) * s, Vector2(4, 2.5) * s), Color("8a6034"))
			ci.draw_circle(c + Vector2(-1.5, 0.5) * s, 1.4 * s, Color(1, 1, 1, 0.6))
			ci.draw_arc(c + Vector2(0, 2) * s, 5.0 * s, 0.0, TAU, 14, outline, 1.0 * s)
		"food":  # bread loaf
			ci.draw_circle(c + Vector2(-2.5, 0) * s, 4.0 * s, Color("c88a40"))
			ci.draw_circle(c + Vector2(2.5, 0) * s, 4.0 * s, Color("c88a40"))
			ci.draw_rect(Rect2(c + Vector2(-2.5, -4) * s, Vector2(5, 8) * s), Color("c88a40"))
			for x in [-2.5, 0.5, 3.5]:
				ci.draw_line(c + Vector2(x - 1, -2) * s, c + Vector2(x + 1, 2) * s, Color("8a5a22"), 1.0 * s)
		"ammo":  # three cartridges
			for i in 3:
				var x := -4.0 + i * 4.0
				ci.draw_rect(Rect2(c + Vector2(x - 1.3, -2) * s, Vector2(2.6, 7) * s), Color("c8a040"))
				ci.draw_circle(c + Vector2(x, -2.5) * s, 1.3 * s, Color("8a7a70"))
		"gems":  # cut gem
			var g := PackedVector2Array([c + Vector2(-5, -1) * s, c + Vector2(-2.5, -5) * s, c + Vector2(2.5, -5) * s, c + Vector2(5, -1) * s, c + Vector2(0, 6) * s])
			ci.draw_colored_polygon(g, Color("40c8d8"))
			ci.draw_line(c + Vector2(-5, -1) * s, c + Vector2(5, -1) * s, Color(1, 1, 1, 0.6), 1.0 * s)
			ci.draw_polyline(g + PackedVector2Array([g[0]]), outline, 1.0 * s)
		"key":
			ci.draw_arc(c + Vector2(-3.5, 0) * s, 3.0 * s, 0.0, TAU, 12, Color("e0b840"), 2.0 * s)
			ci.draw_line(c + Vector2(-0.5, 0) * s, c + Vector2(6, 0) * s, Color("e0b840"), 2.0 * s)
			ci.draw_line(c + Vector2(4, 0) * s, c + Vector2(4, 3) * s, Color("e0b840"), 1.8 * s)
			ci.draw_line(c + Vector2(6, 0) * s, c + Vector2(6, 2.5) * s, Color("e0b840"), 1.8 * s)
		"scroll":  # rolled parchment with a red seal
			ci.draw_rect(Rect2(c + Vector2(-5, -3.5) * s, Vector2(10, 7) * s), Color("e8dcb0"))
			ci.draw_circle(c + Vector2(-5, 0) * s, 3.5 * s, Color("d4c690"))
			ci.draw_circle(c + Vector2(5, 0) * s, 3.5 * s, Color("d4c690"))
			ci.draw_circle(c + Vector2(0, 0) * s, 1.8 * s, Color("b03030"))
		"weapon":  # crossed sword
			ci.draw_line(c + Vector2(-5, 5) * s, c + Vector2(5, -5) * s, Color("d0d4d8"), 2.0 * s)
			ci.draw_line(c + Vector2(-5, 1) * s, c + Vector2(-1, 5) * s, Color("8a6034"), 2.0 * s)
			ci.draw_line(c + Vector2(-6, 6) * s, c + Vector2(-4, 4) * s, Color("8a6034"), 2.5 * s)
		_:  # unknown kind: plain sack
			ci.draw_circle(c + Vector2(0, 1) * s, 5.5 * s, Color("9a7a4a"))
			ci.draw_line(c + Vector2(-2, -4) * s, c + Vector2(2, -4) * s, Color("5a4428"), 1.5 * s)
