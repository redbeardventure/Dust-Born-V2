extends RefCounted
## What the player takes into the next game: the gold left over and the weapons bought on the
## purchase screen (see main_menu.gd). The Player takes it once when it spawns, then it resets,
## so a play-test started from the map editor begins with nothing.

const START_GOLD := 5

## Weapon key (see Weapons.RANGED) -> price in gold.
## The revolver is not for sale: every player starts with one.
const PRICES := {"rifle": 10, "shotgun": 10}
const NAMES := {"pistol": "Revolver", "rifle": "Rifle", "shotgun": "Shotgun"}

static var gold := 0
static var weapons: Array = []


static func reset() -> void:
	gold = 0
	weapons = []


## Hands the loadout to the player and clears it.
static func apply_to(player: Node) -> void:
	player.gold = gold
	for w in weapons:
		if not player.owned_weapons.has(w):
			player.owned_weapons.append(w)
	reset()
