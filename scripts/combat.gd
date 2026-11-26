class_name Combat
extends Node
## Turn-based combat for play-test.
##
## Starts when a hostile NPC can see the player, or when the player targets a hostile NPC.
## Everyone involved (the player and every hostile NPC that can see them) rolls 1d20 for
## initiative; the highest roll goes first. While combat is on, the world waits between turns:
##  - Player turn: either take one action (one shot, or a reload), or run to one of the highlighted
##    cover spots within Player.COMBAT_MOVE pixels (running uses the whole turn). The turn ends by
##    itself right after the action or the run, or with the End turn button.
##  - NPC turn: shoots if it has a gun and a clear shot in range (reloads when empty), otherwise
##    steps closer; unarmed NPCs punch when next to the player. An NPC that has noticed the player
##    may instead YELL FOR HELP (once per fight) when other hostiles are within twice its hearing
##    range: they all join the fight (see _try_yell).
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

var _sneaking := false  # player-initiated fight where nobody has noticed the player yet
var _idle_phase := false  # unaware NPCs are taking their small move between the player's turns
var _idle_time := 0.0
var _reacting = null      # NPC taking its instant "spotted you" attack (untyped: may be freed)
var _react_queue: Array = []
var _ambush_round := false  # the player's first turn gets the surprise bonus action
var _ambush_grace := false
var _wait := 0.0
var _end_delay := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("combat")  # Projectile.fire tells us about gunshots (hearing)
	_rng.randomize()
	if player != null:
		player.respawned.connect(func() -> void:
			if active:
				end_combat("You were knocked out"))


func _exit_tree() -> void:
	NpcNode.combat_mode = false  # static: don't leave NPCs frozen in the next play-test


func is_player_turn() -> bool:
	return active and not _idle_phase and _reacting == null and not order.is_empty() and order[turn]["node"] == player


func current_name() -> String:
	if _idle_phase:
		return "The enemy"
	if is_instance_valid(_reacting):
		return (_reacting as NpcNode).npc_name
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
	if _idle_phase:
		_idle_time -= delta
		if _idle_time <= 0.0:
			_end_idle_phase()
		return
	if _reacting != null:
		_wait -= delta
		if _wait <= 0.0:
			_next_reaction()
		return
	if is_player_turn():
		# Ends by itself once the shot / reload is used (any movement left is given up),
		# or once the full movement range has been walked (the action is then given up).
		if player.is_running():
			_end_delay = -1.0  # still running to cover: the turn ends once you get there
		elif not player.action_left or player.move_left < 1.0:
			if _end_delay < 0.0:
				_end_delay = PLAYER_END_DELAY
			_end_delay -= delta
			if _end_delay <= 0.0:
				next_turn()
	else:
		_wait -= delta
		if _wait <= 0.0:
			if not _npc_extra_action():
				next_turn()


## The player may call the fight off only while no enemy is attacking: none of the enemies in the
## fight has noticed the player (alerted) or can spot them right now.
func can_player_end() -> bool:
	if not active or _idle_phase or player.is_running():
		return false
	for e in order:
		var npc := _npc_of(e)
		if npc != null and _is_enemy(npc) and (npc.alerted or npc.can_spot(player, JOIN_RANGE)):
			return false
	return true


## End combat button.
func player_end_combat() -> void:
	if can_player_end():
		# Drop the target too: a targeted hostile in sight would start the fight again next frame.
		player.set_target(null)
		end_combat("You back off - combat over")


## End turn button.
func end_player_turn() -> void:
	if is_player_turn() and not _idle_phase:
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
		if npc != null and _is_enemy(npc) and npc.can_spot(player, JOIN_RANGE):
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


## The player starts the fight (Attack button). They always act first. Hostile NPCs that have not
## noticed them (not shot at, not looking their way) don't get to act: the player keeps taking
## turns, e.g. to sneak up behind one, until someone notices them.
func start_player_initiated() -> void:
	if active or player == null or player.hp <= 0:
		return
	var foes: Array = []
	var t: NpcNode = player.target as NpcNode if is_instance_valid(player.target) else null
	# The player can shoot over crates and barrels, so a fight can be started from behind one.
	if t != null and _is_enemy(t) and t.can_see(player, JOIN_RANGE, true):
		foes.append(t)
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NpcNode
		if npc != null and not foes.has(npc) and _is_enemy(npc) and npc.can_see(player, JOIN_RANGE, true):
			foes.append(npc)
	if foes.is_empty():
		message.emit("No hostile NPC in sight")
		return
	_sneaking = true
	start(foes[0], [], true, foes)


func start(trigger: NpcNode, surprised: Array = [], player_first := false, extra_foes: Array = []) -> void:
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
		if npc != trigger and _is_enemy(npc) and npc.can_spot(player, JOIN_RANGE):
			_add(npc, npc.npc_name)
	for f in extra_foes:
		if is_instance_valid(f) and not _has(f):
			_add(f, (f as NpcNode).npc_name)
	if not player_first:
		for e in order:  # everyone who joined on their own has noticed the player
			var npc := _npc_of(e)
			if npc != null:
				npc.alerted = true
	for s in surprised:  # surprised NPCs not already in the order still join, with a 0 roll
		if is_instance_valid(s) and not _has(s):
			_add(s, (s as NpcNode).npc_name)
	for e in order:
		if surprised.has(e["node"]):
			e["roll"] = 0
	_sort()
	if player_first:
		for i in order.size():
			if order[i]["node"] == player:
				order.insert(0, order.pop_at(i))
				break
	var parts: Array = []
	for e in order:
		parts.append("%s %d" % [e["name"], e["roll"]])
	if player_first:
		message.emit("You strike first! Hostiles that haven't noticed you can't act yet.")
	elif surprised.is_empty():
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
			npc.alerted = false  # survivors lose track of the player
			npc.yelled = false   # may yell for help again in the next fight
	active = false
	_sneaking = false
	_idle_phase = false
	_reacting = null
	_react_queue.clear()
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
		if _try_yell(npc):
			_wait = YELL_TURN_TIME  # the yell is this NPC's whole turn
		else:
			npc.combat_walk_time = 0.0
			npc.take_combat_turn(player)
			_wait = maxf(NPC_TURN_TIME, npc.combat_walk_time + 0.3)
			_extra_actions = npc.actions_per_turn - 1  # more actions follow, one after another
	changed.emit()


## Actions an NPC / animal still has to take in its current turn after the first one.
var _extra_actions := 0


## Takes the current NPC's next action of this turn, if it has one left. Returns true if it acted.
func _npc_extra_action() -> bool:
	if _extra_actions <= 0:
		return false
	_extra_actions -= 1
	var npc := _npc_of(order[turn])
	if npc == null or npc.hp <= 0 or not is_instance_valid(player):
		_extra_actions = 0
		return false
	npc.combat_walk_time = 0.0
	npc.take_combat_turn(player)
	_wait = maxf(NPC_TURN_TIME, npc.combat_walk_time + 0.3)
	changed.emit()
	return true


func next_turn() -> void:
	if not active:
		return
	_extra_actions = 0
	if order[turn]["node"] == player:
		player.end_turn()
		if _sneaking:
			var spotters := _spotters()
			if _anyone_noticed():
				_sneaking = false
				message.emit("You've been noticed!")
				if _react(spotters):
					return  # whoever spotted you shoots first, then the order carries on
			else:
				# Nobody noticed: the unaware NPCs carry on a little (walk on / keep turning),
				# then the player acts again. The round doesn't advance.
				_idle_time = 0.5
				for e in order:
					var npc := _npc_of(e)
					if npc != null and _is_enemy(npc):
						_idle_time = maxf(_idle_time, npc.idle_step() + 0.3)
				_idle_phase = true
				changed.emit()
				return
	_advance()


## Moves on to the next entry in the initiative order (a new round after the last one).
func _advance() -> void:
	turn += 1
	if turn >= order.size():
		turn = 0
		round_num += 1
		if not _new_round():
			return
	_start_turn()


## The unaware NPCs have finished their small move: if one now sees the player the fight goes on
## normally, otherwise the player takes another turn.
func _end_idle_phase() -> void:
	_idle_phase = false
	var spotters := _spotters()
	if _anyone_noticed():
		_sneaking = false
		message.emit("You've been noticed!")
		if not _react(spotters):
			_advance()
	else:
		message.emit("Unnoticed - take another turn")
		_start_turn()


## Enemies in the fight that have the player in their view arc with a clear line right now.
func _spotters() -> Array:
	var out: Array = []
	for e in order:
		var npc := _npc_of(e)
		if npc != null and _is_enemy(npc) and npc.can_spot(player, JOIN_RANGE):
			out.append(npc)
	return out


## The enemies that just spotted the player react at once with an attack (one each, in turn),
## before the initiative order continues. Returns false when there is nobody to react.
func _react(spotters: Array) -> bool:
	_react_queue = spotters.duplicate()
	if _react_queue.is_empty():
		return false
	_next_reaction()
	return true


func _next_reaction() -> void:
	while not _react_queue.is_empty():
		var npc = _react_queue.pop_front()  # untyped: may have been freed
		if not is_instance_valid(npc) or not _is_enemy(npc):
			continue
		_reacting = npc
		for e in order:
			var other := _npc_of(e)
			if other != null:
				other.set_turn_marker(other == npc)
		message.emit("%s spots you and attacks!" % (npc as NpcNode).npc_name)
		(npc as NpcNode).combat_walk_time = 0.0
		(npc as NpcNode).take_combat_turn(player)
		_wait = maxf(NPC_TURN_TIME, (npc as NpcNode).combat_walk_time + 0.3)
		changed.emit()
		return
	# Everyone has reacted: carry on from the player's place in the order.
	_reacting = null
	_advance()


## Start of a new round: hostiles that have spotted the player join (with their own roll), and the
## fight ends if no enemy can see the player any more. Returns false when combat ended.
func _new_round() -> bool:
	var joined: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NpcNode
		if npc != null and not _has(npc) and _is_enemy(npc) and npc.can_spot(player, JOIN_RANGE):
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
	if not seen:
		# Enemies that know about you keep hunting: behind a wall, or still within their hearing
		# circle (e.g. they joined because they heard a shot and haven't seen you yet).
		for e in order:
			var npc := _npc_of(e)
			if npc != null and _is_enemy(npc) and npc.alerted \
					and (player.in_wall_cover() or npc.hears(player.global_position)):
				seen = true
				break
	if _ambush_grace:
		_ambush_grace = false  # ambushed NPCs may not see you yet; give round 2 a chance
		seen = true
	if not seen:
		end_combat("You slipped away")
		return false
	return true


## A gun went off at `origin` (fired by `shooter`: the player or an NPC). Every hostile NPC whose
## hearing circle contains the shot is alerted, turns toward the player and joins the fight with
## its own initiative roll. If no fight is on yet, the shot starts one.
func on_shot_heard(origin: Vector2, shooter: Node) -> void:
	if player == null or player.hp <= 0:
		return
	var heard: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		var npc := n as NpcNode
		if npc == null or npc == shooter or not _is_enemy(npc) or not npc.hears(origin):
			continue
		npc.alerted = true
		npc.look_toward(player.global_position)
		if not _has(npc):
			heard.append(npc)
	if heard.is_empty():
		return
	if not active:
		# Started outside a fight (e.g. a shot at a barrel): begin combat once this shot is done.
		call_deferred("_start_from_noise", heard)
		return
	_join_mid_fight(heard, "Heard the shot and joins the fight (d20): ")


## Adds `npcs` to a fight that is already on (each rolls initiative) without moving the turn off
## whoever is acting now.
func _join_mid_fight(npcs: Array, text: String) -> void:
	var current = order[turn]["node"]  # keep the turn pointer on whoever is acting now
	var names: Array = []
	for npc in npcs:
		_add(npc, (npc as NpcNode).npc_name)
		names.append("%s %d" % [(npc as NpcNode).npc_name, order[order.size() - 1]["roll"]])
	_sort()
	for i in order.size():
		if order[i]["node"] == current:
			turn = i
			break
	if _sneaking:
		_sneaking = false  # the noise gave you away
	message.emit(text + ", ".join(names))
	changed.emit()


# ---------------------------------------------------------------- yell for help

const YELL_CHANCE := 0.5      # chance an engaged NPC yells (on its turn) when help is in range
const YELL_TURN_TIME := 2.0   # the yell takes the NPC's turn; this long so the effect can be seen


## Hostile NPCs not yet in the fight inside `npc`'s yell circle (twice its hearing circle).
func _yell_listeners(npc: NpcNode) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("npcs"):
		var other := n as NpcNode
		if other == null or other == npc or not _is_enemy(other) or _has(other):
			continue
		if other.global_position.distance_to(npc.global_position) <= NpcNode.YELL_RANGE:
			out.append(other)
	return out


## On its turn an NPC that is engaged with the player (alerted) may YELL FOR HELP instead of
## attacking, once per fight, when other hostiles are within yelling distance. Everyone inside the
## yell circle is alerted, turns toward the player and joins the fight. Returns true if it yelled.
func _try_yell(npc: NpcNode) -> bool:
	if not npc.call_help or npc.yelled or not npc.alerted:
		return false
	var listeners := _yell_listeners(npc)
	if listeners.is_empty() or _rng.randf() > YELL_CHANCE:
		return false
	npc.yelled = true
	npc.look_toward(player.global_position)
	for l in listeners:
		(l as NpcNode).alerted = true
		(l as NpcNode).look_toward(player.global_position)
	YellEffect.spawn(get_tree().current_scene, npc, NpcNode.YELL_RANGE, listeners)
	_join_mid_fight(listeners, "%s YELLS FOR HELP! Joining the fight (d20): " % npc.npc_name)
	return true


func _start_from_noise(heard: Array) -> void:
	if active:
		return
	var alive: Array = []
	for h in heard:
		if is_instance_valid(h) and _is_enemy(h):
			alive.append(h)
	if alive.is_empty():
		return
	start(alive[0], [], false, alive)


## True when an enemy in the fight has noticed the player: it was shot at / hit, or the player is
## now in its view arc with a clear line. Noticing sticks (NpcNode.alerted).
func _anyone_noticed() -> bool:
	var noticed := false
	for e in order:
		var npc := _npc_of(e)
		if npc != null and _is_enemy(npc) and (npc.alerted or npc.can_spot(player, JOIN_RANGE)):
			npc.alerted = true
			noticed = true
	return noticed


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
