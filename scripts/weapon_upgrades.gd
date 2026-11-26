class_name WeaponUpgrades
extends RefCounted
## Weapon upgrades the player buys with XP (the [+] buttons on the weapon specs card). Levels live
## on the Player (`upgrades`: weapon key -> {stat -> level}), so they reset with XP at the start of a game.

const MAX_LEVEL := 5
const BASE_COST := 10  # XP for level 1; each further level costs another BASE_COST more

## stat -> label and the change per level (a multiplier step).
const STATS := {
	"damage": {"label": "Damage", "step": 0.10},   # +10% damage per level
	"reload": {"label": "Reload speed", "step": 0.10},  # -10% reload time per level
	"delay": {"label": "Shot delay", "step": 0.10},     # -10% time between shots per level
}


static func level(upgrades: Dictionary, weapon: String, stat: String) -> int:
	return int((upgrades.get(weapon, {}) as Dictionary).get(stat, 0))


## XP price of the next level of `stat` (0 when already maxed).
static func cost(upgrades: Dictionary, weapon: String, stat: String) -> int:
	var lv := level(upgrades, weapon, stat)
	return 0 if lv >= MAX_LEVEL else BASE_COST * (lv + 1)


static func damage_mul(upgrades: Dictionary, weapon: String) -> float:
	return 1.0 + level(upgrades, weapon, "damage") * float(STATS["damage"]["step"])


## Multiplier on the reload time (smaller = faster).
static func reload_mul(upgrades: Dictionary, weapon: String) -> float:
	return 1.0 - level(upgrades, weapon, "reload") * float(STATS["reload"]["step"])


## Multiplier on the time between shots (smaller = faster).
static func delay_mul(upgrades: Dictionary, weapon: String) -> float:
	return 1.0 - level(upgrades, weapon, "delay") * float(STATS["delay"]["step"])
