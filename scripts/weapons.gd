class_name Weapons
extends RefCounted
## Ranged weapon stats and artwork shared by the player and NPCs.
## Only weapons listed in RANGED fire projectiles; melee weapons (dagger, sword...) are drawn but don't shoot.

## One map grid tile in pixels (the editor's snap grid). Weapon ranges are given in tiles.
const TILE := 32.0

## key -> stats. speed px/s, damage hp, cooldown s between shots, range px, spread = max aim error (radians),
## mag = shots before a reload is needed, reload = seconds to refill the mag.
## Ranges: revolver 4 tiles, shotgun 3 tiles, rifle 5 tiles.
const RANGED := {
	"pistol": {"label": "Pistol", "shot": "bullet", "speed": 900.0, "damage": 14, "cooldown": 0.7, "range": 4 * TILE, "spread": 0.05, "mag": 6, "reload": 1.8},
	"rifle": {"label": "Rifle", "shot": "bullet", "speed": 1300.0, "damage": 34, "cooldown": 2.0, "range": 5 * TILE, "spread": 0.01, "mag": 5, "reload": 2.5},
	# Shotgun: each shot is a spread of `pellets` projectiles; damage is per pellet.
	"shotgun": {"label": "Shotgun", "shot": "pellet", "speed": 850.0, "damage": 9, "pellets": 7, "cooldown": 1.3, "range": 3 * TILE, "spread": 0.22, "mag": 4, "reload": 2.8},
}

## Image icons for GUI buttons (weapons not listed here use the drawn icon from draw_icon()).
const ICON_IMAGES := {
	"pistol": "res://assets/revolver_russian.svg",
}


## In-hand images drawn on the player instead of the line art. Each image is top-down with the
## barrel pointing up (-y); `grip` = pixel where the hand is, `scale` = image pixels -> world pixels.
## The grip is placed `reach` px in front of the body centre and `side` px to the character's
## right (negative = left hand).
const HELD_IMAGES := {
	"pistol": {"path": "res://assets/Hand_Revolver_Russian.png", "grip": Vector2(30, 39), "scale": 0.65, "reach": 11.0, "side": 6.0},
	# Long guns (64x128 images): hand on the rear grip at the bottom, barrel tip at y = 0.
	"rifle": {"path": "res://assets/Hand_Rifle_.png", "grip": Vector2(32, 60), "scale": 0.55, "reach": 6.0, "side": 5.0},
	"shotgun": {"path": "res://assets/Hand_Shotgun_.png", "grip": Vector2(30, 57), "scale": 0.55, "reach": 6.0, "side": 5.0},
}


## Loaded in-hand textures, kept here so they stay alive. A texture loaded into a local variable
## inside _draw() is freed when _draw() returns, and the canvas then renders it as a white box.
static var _held_cache := {}


static func _held_texture(path: String) -> Texture2D:
	if not _held_cache.has(path):
		_held_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _held_cache[path]


## Draws the in-hand image for `key` if there is one; returns false when the caller should use line art.
## `body_scale` scales the image and its position about the body centre (used for the walking step pulse).
## Leaves the canvas draw transform reset to identity.
static func draw_held_image(ci: CanvasItem, key: String, facing: Vector2, base: Vector2, body_scale: float = 1.0) -> bool:
	if not HELD_IMAGES.has(key):
		return false
	var h: Dictionary = HELD_IMAGES[key]
	var tex := _held_texture(h["path"])
	if tex == null:
		return false
	var s: float = h["scale"]
	# Character's right side, in y-down screen space: facing (1, 0) -> right hand is at (0, 1).
	var right := Vector2(-facing.y, facing.x)
	var grip_at := facing * float(h.get("reach", 0.0)) + right * float(h.get("side", 0.0))
	if not h.has("reach"):
		grip_at = base
	s *= body_scale
	grip_at *= body_scale
	ci.draw_set_transform(grip_at, facing.angle() + PI * 0.5, Vector2(s, s))  # image "up" -> facing
	ci.draw_texture(tex, -(h["grip"] as Vector2))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


## Muzzle position relative to the body centre for a weapon drawn with an in-hand image
## (the barrel tip is the top of the image, y = 0). Vector2.ZERO when there is no image.
static func muzzle_offset(key: String, facing: Vector2) -> Vector2:
	if not HELD_IMAGES.has(key) or not HELD_IMAGES[key].has("reach"):
		return Vector2.ZERO
	var h: Dictionary = HELD_IMAGES[key]
	var right := Vector2(-facing.y, facing.x)
	var grip: Vector2 = h["grip"]
	var reach := float(h["reach"]) + grip.y * float(h["scale"])
	return facing * reach + right * float(h["side"])


## Image icon for `key`, or null when it has none (or the file is missing).
static func icon_texture(key: String) -> Texture2D:
	var path: String = ICON_IMAGES.get(key, "")
	if path == "":
		return null
	return _held_texture(path)  # cached: a texture held only by a local in _draw() renders as a white box


## Choices offered to the player, in button order.
const PLAYER_CHOICES := ["none", "pistol", "shotgun", "rifle"]


## How far off (pixels, either side) a bullet can land at the end of the weapon's range;
## close up it is only a couple of pixels. Rifles are steadier than pistols.
const MISS_PX_AT_RANGE := 24.0
const MISS_PX_CLOSE := 2.0
const STEADINESS := {"pistol": 1.0, "rifle": 0.6}


## Multiplier for the weapon's spread when shooting at something `dist` px away: the farther
## the target, the wider the shot can stray, so long shots miss more often. Shotguns keep
## their pellet pattern (it already thins out with distance).
static func spread_mul_at(key: String, dist: float) -> float:
	if not RANGED.has(key) or RANGED[key]["shot"] == "pellet":
		return 1.0
	var base: float = RANGED[key]["spread"]
	if base <= 0.0:
		return 1.0
	var t := clampf(dist / float(RANGED[key]["range"]), 0.0, 1.5)
	var miss_px := lerpf(MISS_PX_CLOSE, MISS_PX_AT_RANGE, t) * float(STEADINESS.get(key, 1.0))
	return atan(miss_px / maxf(dist, 20.0)) / base


## Reticle colour for a target `dist` px away: green when close (good odds), shading to yellow
## toward the edge of the range (fair odds), red when out of range (the shot can't reach).
static func range_color(key: String, dist: float, range_mul: float = 1.0) -> Color:
	if not RANGED.has(key):
		return Color(1.0, 0.9, 0.4)
	var t := dist / (float(RANGED[key]["range"]) * range_mul)
	if t > 1.0:
		return Color(1.0, 0.25, 0.2)
	var green := Color(0.3, 1.0, 0.35)
	var yellow := Color(1.0, 0.9, 0.2)
	return green.lerp(yellow, smoothstep(0.4, 1.0, t))


static func is_ranged(key: String) -> bool:
	return RANGED.has(key)


static func label(key: String) -> String:
	if key == "none":
		return "Unarmed"
	if RANGED.has(key):
		return str(RANGED[key]["label"])
	return str(MapData.NPC_WEAPONS.get(key, key))


static func tooltip(key: String) -> String:
	if not RANGED.has(key):
		return label(key)
	var w: Dictionary = RANGED[key]
	var pellets := int(w.get("pellets", 1))
	var dmg := ("%d x %d" % [pellets, w["damage"]]) if pellets > 1 else str(w["damage"])
	return "%s\nDamage %s   Range %d tiles   %.1f s between shots\nAmmo %d   Reload %.1f s" % [
		w["label"], dmg, roundi(float(w["range"]) / TILE), float(w["cooldown"]), w["mag"], float(w["reload"])]


static func mag_size(key: String) -> int:
	return int(RANGED[key]["mag"]) if RANGED.has(key) else 0


static func length(key: String) -> float:
	match key:
		"dagger":
			return 8.0
		"spear":
			return 22.0
		"rifle", "shotgun":
			return 16.0
	return 12.0


## Draws a held weapon pointing along `facing`, starting at `base` (local coordinates of `ci`).
static func draw_held(ci: CanvasItem, key: String, facing: Vector2, base: Vector2, s: float = 1.0) -> void:
	if key == "none":
		return
	var tip := base + facing * length(key) * s
	match key:
		"pistol", "rifle":
			ci.draw_line(base, tip, Color("2a2a2e"), 3.0 * s)
			ci.draw_line(base, base + facing * 5.0 * s, Color("6b4a2a"), 3.5 * s)  # grip / stock
		"shotgun":  # two side-by-side barrels on a wooden stock
			var side := facing.orthogonal() * 1.3 * s
			var mid := base + facing * 6.0 * s
			ci.draw_line(base, mid, Color("7a5230"), 4.5 * s)
			ci.draw_line(mid + side, tip + side, Color("2a2a2e"), 2.0 * s)
			ci.draw_line(mid - side, tip - side, Color("2a2a2e"), 2.0 * s)
		_:
			ci.draw_line(base, tip, Color("d0d4d8"), 2.5 * s)


## Draws a weapon icon (image if it has one, else the line art) centred on `center` in a `box` px square.
static func draw_icon_at(ci: CanvasItem, key: String, center: Vector2, box: float) -> void:
	var tex := icon_texture(key)
	if tex != null:
		var ts := tex.get_size()
		var k := box / maxf(ts.x, ts.y)
		ci.draw_texture_rect(tex, Rect2(center - ts * k * 0.5, ts * k), false)
		return
	ci.draw_set_transform(center - Vector2(box, box) * 0.5)
	draw_icon(ci, key, Vector2(box, box))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


## Cartoon clenched fist (fists / "none" icon): forearm rising from the bottom, four knuckles
## along the top, thumb folded across the front, warm skin tones with a thick dark ink outline.
## Drawn in a 26 x 26 unit box centred on `c`, `s` px per unit.
static func _draw_fist(ci: CanvasItem, c: Vector2, s: float) -> void:
	var skin := Color("dca46a")
	var shade := Color("b47a44")
	var hi := Color("f4cd98")
	var ink := Color("3d2312")
	var o := 1.4 * s  # outline thickness
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in pts:
			out.append(c + (v as Vector2) * s)
		return out
	var arm: PackedVector2Array = P.call([Vector2(-6, 13), Vector2(3, 13), Vector2(5.5, 3), Vector2(-5.5, 2)])
	var palm: PackedVector2Array = P.call([Vector2(-8.5, -5.5), Vector2(8, -4.5), Vector2(8.5, 3.5), Vector2(5, 7), Vector2(-6, 7), Vector2(-9, 2.5)])
	var knuckles := [Vector2(-5.6, -6.2), Vector2(-2, -7.4), Vector2(1.7, -7.1), Vector2(5.2, -5.6)]
	var thumb_a := c + Vector2(-7.5, 0.8) * s
	var thumb_b := c + Vector2(3.2, 1.8) * s
	# Ink pass: every shape drawn a little larger in the outline colour, so only the silhouette shows.
	for poly in [arm, palm]:
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		ci.draw_polyline(closed, ink, o * 2.0, true)
		ci.draw_colored_polygon(poly, ink)
	for k in knuckles:
		ci.draw_circle(c + (k as Vector2) * s, 3.5 * s + o, ink)
	ci.draw_line(thumb_a, thumb_b, ink, 4.6 * s + o * 2.0)
	ci.draw_circle(thumb_b, 2.3 * s + o, ink)
	# Fill pass.
	ci.draw_colored_polygon(arm, skin)
	ci.draw_colored_polygon(P.call([Vector2(0.5, 13), Vector2(3, 13), Vector2(5.5, 3), Vector2(2.5, 2.6)]), shade)  # far side of the arm
	ci.draw_line(c + Vector2(-4.5, 9) * s, c + Vector2(1.5, 9.4) * s, Color(ink, 0.5), 0.9 * s)  # wrist crease
	ci.draw_colored_polygon(palm, skin)
	ci.draw_colored_polygon(P.call([Vector2(5, -4.6), Vector2(8, -4.5), Vector2(8.5, 3.5), Vector2(5, 7), Vector2(3, 7)]), shade)
	for i in knuckles.size():
		var k: Vector2 = c + (knuckles[i] as Vector2) * s
		ci.draw_circle(k, 3.5 * s, shade if i == knuckles.size() - 1 else skin)
		ci.draw_circle(k + Vector2(-1.0, -1.2) * s, 1.3 * s, hi)  # light on each knuckle
	# Gaps between the curled fingers.
	for x in [-3.8, -0.1, 3.5]:
		ci.draw_line(c + Vector2(x, -8.5) * s, c + Vector2(x + 0.3, -1.5) * s, ink, 1.0 * s)
	# Finger tips tucked under, just above the thumb.
	for x in [-5.2, -1.6, 2.0]:
		ci.draw_arc(c + Vector2(x, -1.6) * s, 1.6 * s, 0.2, PI - 0.2, 6, Color(ink, 0.6), 0.8 * s)
	# Thumb folded across the front.
	ci.draw_line(thumb_a, thumb_b, skin, 4.6 * s)
	ci.draw_circle(thumb_b, 2.3 * s, skin)
	ci.draw_line(thumb_a + Vector2(1, -1.2) * s, thumb_b + Vector2(-0.5, -1.4) * s, hi, 1.1 * s)  # top highlight
	ci.draw_circle(thumb_b + Vector2(0.6, -0.2) * s, 1.1 * s, hi)  # nail
	ci.draw_line(c + Vector2(-1, 0.3) * s, c + Vector2(-0.6, 3.2) * s, Color(ink, 0.7), 0.9 * s)  # thumb knuckle crease


## Icon for a GUI button: the weapon drawn diagonally, centred in `size`.
static func draw_icon(ci: CanvasItem, key: String, size: Vector2) -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y) / 26.0
	if key == "none":
		_draw_fist(ci, c, s)
		return
	var dir := Vector2(1, -1).normalized()
	draw_held(ci, key, dir, c - dir * length(key) * s * 0.5, s)
