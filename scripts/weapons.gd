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
