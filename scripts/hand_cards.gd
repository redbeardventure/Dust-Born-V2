extends RefCounted
## Cards the player earns and keeps in their hand: one card for every XP_PER_CARD experience points
## earned (see Player.add_xp). Played from the hand strip along the bottom of the screen.
## Effects live in Player.play_hand_card(); the icons are drawn by ActionCard.
## (These are separate from the three always-available combat cards in game_view.gd.)

const XP_PER_CARD := 5

const REVOLVER_DAMAGE_STEP := 0.20  # each Upgrade Revolver card adds +20% revolver damage
const SHOTGUN_MAG_STEP := 1         # each Upgrade Shotgun card adds this much ammo capacity

## kind -> title, rules text and accent colour.
const CARDS := {
	"revolver_up": {"title": "Upgrade Revolver", "desc": "Permanently increases revolver damage by 20%.", "accent": Color(0.8, 0.25, 0.2)},
	"first_strike": {"title": "First Strike", "desc": "In every fight on this map you go first and get +1 action in your first turn.", "accent": Color(0.25, 0.55, 0.9)},
	"shotgun_up": {"title": "Upgrade Shotgun", "desc": "Permanently adds 1 to the shotgun's ammo capacity.", "accent": Color(0.8, 0.6, 0.15)},
	"fan_hammer": {"title": "Fan the Hammer", "desc": "Fire every round in your revolver in a single action. Play it on your turn.", "accent": Color(0.55, 0.3, 0.7)},
}


static func random_kind() -> String:
	var keys: Array = CARDS.keys()
	return str(keys[randi() % keys.size()])


static func title(kind: String) -> String:
	return str((CARDS.get(kind, {}) as Dictionary).get("title", kind))


## Why a card can't be played right now (shown as its tooltip).
static func hint(kind: String) -> String:
	match kind:
		"first_strike":
			return "Can't be played during a fight, or twice."
		"fan_hammer":
			return "Play on your turn, with the revolver in hand and at least 2 rounds loaded."
	return ""


## What a card just did (shown in the hand popup after it is played).
static func result_text(kind: String, player: Node) -> String:
	match kind:
		"revolver_up":
			return "revolver damage is now +%d%%." % roundi((float(player.call("card_damage_mul", "pistol")) - 1.0) * 100.0)
		"shotgun_up":
			return "the shotgun now holds %d rounds." % int(player.call("mag", "shotgun"))
		"first_strike":
			return "you will go first, with +1 action, in every fight on this map."
		"fan_hammer":
			return "close this and take your shot to empty the revolver."
	return ""


## The upgrade card that applies to weapon `key` ("" when no card upgrades it).
static func upgrade_card_for(key: String) -> String:
	match key:
		"pistol":
			return "revolver_up"
		"shotgun":
			return "shotgun_up"
	return ""


## How many of the weapon's upgrade cards the player has played.
static func upgrade_count(player: Node, key: String) -> int:
	var cards: Dictionary = {}
	match key:
		"pistol":
			cards = player.get("damage_cards")
		"shotgun":
			cards = player.get("mag_cards")
	return int(cards.get(key, 0))


## One line saying what the weapon's played cards did, e.g. "Damage +40%" or "Ammo +2".
static func upgrade_effect(key: String, count: int) -> String:
	match key:
		"pistol":
			return "Damage +%d%%" % roundi(count * REVOLVER_DAMAGE_STEP * 100.0)
		"shotgun":
			return "Ammo capacity +%d" % (count * SHOTGUN_MAG_STEP)
	return ""
