class_name Combat
extends Node
## Turn-based combat for play-test.
##
## Starts when a hostile NPC can see the player, or when the player targets a hostile NPC.
## Everyone involved (the player and every hostile NPC that can see them) rolls 1d20 for
## initiative; the highest roll goes first. While combat is on, the world waits between turns:
##  - Player turn: move up to Player.COMBAT_MOVE pixels, then take one action (one shot, or a reload).
##    The turn ends by itself right after the action, once the full movement has been walked,
##    or with the End turn button.
##  - NPC turn: shoots if it has a gun and a clear shot in range (reloads when empty), otherwise
##    steps closer; unarmed NPCs punch when next to the player.
## New hostiles that spot the player join at the start of the next round. Combat ends when every
## enemy is down, when none of them can see the player any more, or when the player is knocked out.

signal changed            ## order, current turn or round changed (refresh the GUI list)
signal message(text: String)

const JOIN_RANGE := 6 * Weapons.TILE  # hostile NPCs within 6 tiles that can see the player join the fight
const NPC_TURN_TIME := 1.0      # seconds an NPC turn takes (lets shots fly and moves play out)
const PLAYER_END_DELAY := 0.6   # pause after the player's last move / action before the next turn

var player: Player
var active := false
## Initiative order: [{"node": Node2D, "name": String, "roll": int, "tie": float}], highest first.
var order: Array = []
var turn := 0
var round_num := 0

var _ambush_round := false  # the player's first turn gets the surprise bonus action
var _ambush_grace := false
var _wait := 0.0
var _end_delay := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if player != null:
		player.respawned.connect(func() -> void:
			if active:
				end_combat("You were knocked out"))


func _exit_tree() -> void:
	NpcNode.combat_mode = false  # static: don't leave NPCs frozen in the next play-test


func is_player_turn() -> bool:
	return active and not order.is_empty() and order[turn]["node"] == player


func current_name() -> String:
	return str(order[turn]["name"]) if active and not order.is_empty() else ""


func _process(delta: float) -> void:
	if player == null:
		return
	if not active:
		var trigger := _trigger()
		if trigger != null:
			start(trigger)
		return
	if _prune():
		return
	if is_player_turn():
		# Ends by itself once the shot / reload is used (any movement left is given up),
		# or once the full movement range has been walked (the action is then given up).
		if not player.action_left or player.move_left < 1.0:
			if _end_delay < 0.0:
				_end_delay = PLAYER_END_DELAY
			_end_delay -= delta
			if _end_delay <= 0.0:
				next_turn()
	else:
		_wait -= delta
		if _wait <= 0.0:
			next_turn()


## End turn button.
func end_player_turn() -> void:
	if is_player_turn():
		next_turn()


# ---------------------------------------------------------------- start / end

## A hostile NPC that should start combat: it can see the player, or the player has targeted it.
func _trigger() -> NpcNode:
	# Targeting a hostile starts the fight when the two of you are in sight of each other
	# (otherwise it would end straight away with "You slipped away").
	var t: NpcNode = player.target as NpcNode if is_instance_valid(player.target) else null
	if t != null and _is_enemy(t) and t.can_see(player, JOIN_RANGE):
		return t
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NpcNode
		if npc != null and _is_enemy(npc) and npc.can_see(player, JOIN_RANGE):
			return npc
	return null


func _is_enemy(npc: NpcNode) -> bool:
	return is_instance_valid(npc) and not npc.is_queued_for_deletion() and npc.hp > 0 and npc.disposition == "hostile"


## Kicking a door in: every hostile NPC inside that building is caught off guard. Combat starts
## at once with their initiative at 0, and the player gets 2 actions in the first round.
func start_ambush(surprised: Array) -> void:
	if active or surprised.is_empty():
		return
	_ambush_round = true
	_ambush_grace = true
	start(surprised[0], surprised)


func start(trigger: NpcNode, surprised: Array = []) -> void:
	active = true
	round_num = 1
	turn = 0
	order.clear()
	NpcNode.combat_mode = true  # NPCs stop wandering and shooting on their own
	player.enter_combat()
	_add(player, "You")
	_add(trigger, trigger.npc_name)
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NpcNode
		if npc != trigger and _is_enemy(npc) and npc.can_see(player, JOIN_RANGE):
			_add(npc, npc.npc_name)
	for s in surprised:  # surprised NPCs not already in the order still join, with a 0 roll
		if is_instance_valid(s) and not _has(s):
			_add(s, (s as NpcNode).npc_name)
	for e in order:
		if surprised.has(e["node"]):
			e["roll"] = 0
	_sort()
	var parts: Array = []
	for e in order:
		parts.append("%s %d" % [e["name"], e["roll"]])
	if surprised.is_empty():
		message.emit("Combat! Initiative (d20): " + ", ".join(parts))
	else:
		message.emit("Ambush! Caught by surprise. Initiative: " + ", ".join(parts) + ". You get 2 actions.")
	_start_turn()


func end_combat(text: String) -> void:
	if not active:
		return
	for e in order:
		var npc := _npc_of(e)
		if npc != null:
			npc.set_turn_marker(false)
	active = false
	order.clear()
	NpcNode.combat_mode = false
	player.leave_combat()
	if text != "":
		message.emit(text)
	changed.emit()


## Rolls 1d20 for `node` and adds it to the order (not re-sorted).
func _add(node: Node2D, label: String) -> void:
	# Defeated NPCs are dropped by _prune() each frame, so the turn index is fixed in one place.
	order.append({"node": node, "name": label, "roll": _rng.randi_range(1, 20), "tie": _rng.randf()})


func _sort() -> void:
	order.sort_custom(func(a, b) -> bool:
		if a["roll"] != b["roll"]:
			return a["roll"] > b["roll"]
		return a["tie"] > b["tie"])  # equal rolls: a hidden tie-breaker roll


## The NPC in an order entry, or null for the player or an NPC that has already been freed.
## Always check validity before `is` / `as`: both error on a freed instance.
func _npc_of(e: Dictionary) -> NpcNode:
	var node = e["node"]
	if not is_instance_valid(node):
		return null
	return node as NpcNode


func _has(node: Node) -> bool:
	for e in order:
		if e["node"] == node:
			return true
	return false


# ---------------------------------------------------------------- turns

func _start_turn() -> void:
	_end_delay = -1.0
	var node = order[turn]["node"]  # untyped: checked for a freed NPC just below
	if not is_instance_valid(node):
		return  # died this frame; _prune() drops it and starts the next turn
	for e in order:
		var npc := _npc_of(e)
		if npc != null:
			npc.set_turn_marker(npc == node)
	if node == player:
		player.begin_turn()
		if _ambush_round:
			_ambush_round = false
			player.extra_actions = 1  # surprise bonus: 2 actions this first turn
	else:
		var npc := node as NpcNode
		npc.take_combat_turn(player)
		_wait = NPC_TURN_TIME
	changed.emit()


func next_turn() -> void:
	if not active:
		return
	if order[turn]["node"] == player:
		player.end_turn()
	turn += 1
	if turn >= order.size():
		turn = 0
		round_num += 1
		if not _new_round():
			return
	_start_turn()


## Start of a new round: hostiles that have spotted the player join (with their own roll), and the
## fight ends if no enemy can see the player any more. Returns false when combat ended.
func _new_round() -> bool:
	var joined: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NpcNode
		if npc != null and not _has(npc) and _is_enemy(npc) and npc.can_see(player, JOIN_RANGE):
			_add(npc, npc.npc_name)
			joined.append("%s %d" % [npc.npc_name, order[order.size() - 1]["roll"]])
	if not joined.is_empty():
		_sort()
		message.emit("Joins the fight (d20): " + ", ".join(joined))
	var seen := false
	for e in order:
		var npc := _npc_of(e)
		if npc != null and _is_enemy(npc) and npc.can_see(player, JOIN_RANGE):
			seen = true
			break
	if _ambush_grace:
		_ambush_grace = false  # ambushed NPCs may not see you yet; give round 2 a chance
		seen = true
	if not seen:
		end_combat("You slipped away")
		return false
	return true


## Drops dead NPCs from the order, keeping the current turn pointing at the right entry.
## Returns true when that ended (or restarted) the turn handling for this frame.
func _prune() -> bool:
	var removed_current := false
	var any_removed := false
	for i in range(order.size() - 1, -1, -1):
		var node = order[i]["node"]  # untyped: may already be freed (killed NPC)
		var gone: bool = not is_instance_valid(node) or (node as Node).is_queued_for_deletion()
		if not gone and node is NpcNode and (node as NpcNode).hp <= 0:
			gone = true
		if gone:
			any_removed = true
			order.remove_at(i)
			if i < turn:
				turn -= 1
			elif i == turn:
				removed_current = true
	var enemies := 0
	for e in order:
		if e["node"] != player:
			enemies += 1
	if enemies == 0:
		end_combat("All enemies defeated")
		return true
	if removed_current:
		if turn >= order.size():
			turn = 0
			round_num += 1
			if not _new_round():
				return true
		_start_turn()
		return true
	if any_removed:
		changed.emit()
	return false
