class_name Weapons
extends RefCounted
## Ranged weapon stats and artwork shared by the player and NPCs.
## Only weapons listed in RANGED fire projectiles; melee weapons (dagger, sword...) are drawn but don't shoot.

## key -> stats. speed px/s, damage hp, cooldown s between shots, range px, spread = max aim error (radians),
## mag = shots before a reload is needed, reload = seconds to refill the mag.
const RANGED := {
	"pistol": {"label": "Pistol", "shot": "bullet", "speed": 900.0, "damage": 14, "cooldown": 0.7, "range": 600.0, "spread": 0.05, "mag": 6, "reload": 1.8},
	"rifle": {"label": "Rifle", "shot": "bullet", "speed": 1300.0, "damage": 34, "cooldown": 2.0, "range": 900.0, "spread": 0.01, "mag": 5, "reload": 2.5},
	# Shotgun: each shot is a spread of `pellets` projectiles; damage is per pellet.
	"shotgun": {"label": "Shotgun", "shot": "pellet", "speed": 850.0, "damage": 9, "pellets": 7, "cooldown": 1.3, "range": 320.0, "spread": 0.22, "mag": 4, "reload": 2.8},
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
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Choices offered to the player, in button order.
const PLAYER_CHOICES := ["none", "pistol", "shotgun", "rifle"]


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
	return "%s\nDamage %s   Range %d   %.1f s between shots\nAmmo %d   Reload %.1f s" % [
		w["label"], dmg, w["range"], float(w["cooldown"]), w["mag"], float(w["reload"])]


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


## Icon for a GUI button: the weapon drawn diagonally, centred in `size`.
static func draw_icon(ci: CanvasItem, key: String, size: Vector2) -> void:
	var c := size * 0.5
	var s := minf(size.x, size.y) / 26.0
	if key == "none":  # open hand: palm + fingers
		var skin := Color("e8c9a0")
		ci.draw_circle(c + Vector2(0, 3) * s, 5.0 * s, skin)
		for i in 4:
			ci.draw_line(c + Vector2(-4.5 + i * 3.0, 0) * s, c + Vector2(-4.5 + i * 3.0, -7) * s, skin, 2.2 * s)
		ci.draw_line(c + Vector2(4, 3) * s, c + Vector2(8, -1) * s, skin, 2.2 * s)
		return
	var dir := Vector2(1, -1).normalized()
	draw_held(ci, key, dir, c - dir * length(key) * s * 0.5, s)
