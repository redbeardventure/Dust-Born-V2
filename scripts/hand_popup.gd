extends CanvasLayer
## The opened deck: the player's cards fanned out face up over the paused game. Click a card to pull
## it out of the fan and read it in full, then press "Play card" to use it. Click the pulled-out card
## again (or the background) to put it back. Esc, right-click or Close puts the whole hand away.

signal closed

const HandCards := preload("res://scripts/hand_cards.gd")
const ACCENT := Color(1.0, 0.82, 0.3)
const MAX_SPREAD := 1.05   # radians (about 60 degrees): total angle the fan opens to
const STEP_ANGLE := 0.157  # radians (about 9 degrees): angle between neighbouring cards until the fan is full
const MAX_SPACING := 124.0 # px between card centres
const ARC_DROP := 7.0      # px each card sits lower per step away from the middle (squared)
const LIFT := 46.0         # px a hovered card rises
const PICK_SCALE := 1.7    # size of the card pulled out of the fan
const FAN_DROP := 150.0    # px the fan moves down while a card is pulled out

var player: Player
var _stage: Control
var _status: Label
var _title: Label
var _play_btn: Button
var _cards: Array = []
var _selected: ActionCard = null
const GRACE_MS := 400  # right after opening, background taps are ignored
var _opened_at := 0
var _shade_down := false


## Call after adding the popup to the tree.
func setup(p: Player) -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused
	player = p
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_opened_at = Time.get_ticks_msec()
	# A tap on the background closes (or puts the pulled-out card back) on release, and only if the
	# press also began there, so leftovers of the tap that opened the hand can't close it again.
	shade.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_shade_down = Time.get_ticks_msec() - _opened_at > GRACE_MS
		elif _shade_down:
			_shade_down = false
			if _selected != null:
				_select(null)
			else:
				_close())
	add_child(shade)
	_stage = Control.new()  # holds the cards; clicks on empty parts fall through to the shade
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	_title = _text(26, ACCENT)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.offset_top = 40.0
	_title.offset_left = -300.0
	_title.offset_right = 300.0
	_title.offset_bottom = 80.0
	add_child(_title)

	_status = _text(15, Color(0.85, 0.87, 0.9))
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_left = -400.0
	_status.offset_right = 400.0
	_status.offset_top = -110.0
	_status.offset_bottom = -80.0
	add_child(_status)

	var go := Button.new()
	go.text = "Close"
	go.custom_minimum_size = Vector2(120, 36)
	go.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	go.offset_left = -60.0
	go.offset_right = 60.0
	go.offset_top = -66.0
	go.offset_bottom = -30.0
	go.pressed.connect(_close)
	add_child(go)

	_play_btn = Button.new()
	_play_btn.text = "Play card"
	_play_btn.add_theme_font_size_override("font_size", 20)
	_play_btn.size = Vector2(170, 48)
	_play_btn.visible = false
	_play_btn.pressed.connect(_play_selected)
	add_child(_play_btn)
	_fill(true)


func _text(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Creates one face-up card per entry in the hand, then lays them out. `animate`: the cards spread
## out from a single pile in the middle.
func _fill(animate: bool) -> void:
	for c in _stage.get_children():
		_stage.remove_child(c)
		c.queue_free()
	_cards.clear()
	_selected = null
	var n := player.hand.size()
	_title.text = "YOUR HAND  (%d card%s)" % [n, "" if n == 1 else "s"]
	if n == 0:
		_status.text = "No cards left in your hand."
		_play_btn.visible = false
		return
	for i in n:
		var kind: String = player.hand[i]
		var d: Dictionary = HandCards.CARDS[kind]
		var card := ActionCard.new()
		card.rises = false
		card.kind = kind
		card.title = d["title"]
		card.desc = d["desc"]
		card.accent = d["accent"]
		card.usable = player.can_play_hand_card(kind)
		card.pivot_offset = ActionCard.SIZE * 0.5
		card.clicked.connect(func(_k: String) -> void: _select(null if _selected == card else card))
		card.mouse_entered.connect(_hover_card.bind(card, true))
		card.mouse_exited.connect(_hover_card.bind(card, false))
		_stage.add_child(card)
		_cards.append(card)
	_status.text = "Click a card to look at it."
	_layout(animate, true)


## Where the fan is centred: the middle of the screen, lower while a card is pulled out.
func _fan_base(view: Vector2) -> Vector2:
	return Vector2(view.x * 0.5, view.y * 0.5 + 10.0 + (FAN_DROP if _selected != null else 0.0))


## Sets every card's resting position / angle / size and moves them there. `from_pile`: start
## from a single pile in the middle (the opening animation).
func _layout(animate: bool, from_pile: bool = false) -> void:
	var view := get_viewport().get_visible_rect().size
	var n := _cards.size()
	var spacing := minf(MAX_SPACING, (view.x - 200.0) / maxf(n, 1.0))
	var step := minf(STEP_ANGLE, MAX_SPREAD / maxf(n - 1, 1.0))
	var base := _fan_base(view)
	for i in n:
		var card: ActionCard = _cards[i]
		var t := float(i) - float(n - 1) * 0.5
		var pos := base + Vector2(t * spacing, t * t * ARC_DROP) - ActionCard.SIZE * 0.5
		var rot := t * step
		var sc := Vector2.ONE
		var alpha := 1.0
		if _selected != null:
			if card == _selected:
				# Pulled out: centred in the upper half, upright and large.
				pos = Vector2(view.x * 0.5, view.y * 0.38) - ActionCard.SIZE * 0.5
				rot = 0.0
				sc = Vector2(PICK_SCALE, PICK_SCALE)
			else:
				alpha = 0.55
		card.set_meta("rest_pos", pos)
		card.set_meta("rest_rot", rot)
		card.z_index = 20 if card == _selected else 0
		var old: Tween = card.get_meta("tw", null)
		if old != null:
			old.kill()
		if from_pile:
			card.position = Vector2(view.x * 0.5, view.y * 0.5 + 10.0) - ActionCard.SIZE * 0.5
			card.scale = Vector2(0.5, 0.5)
			card.modulate.a = 0.0
		if animate:
			var delay := i * 0.04 if from_pile else 0.0
			var dur := 0.3 if from_pile else 0.22
			var tw := create_tween()  # bound to this always-running layer, so it plays while paused
			tw.set_parallel(true)
			tw.tween_property(card, "position", pos, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "rotation", rot, dur).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "scale", sc, dur).set_delay(delay)
			tw.tween_property(card, "modulate:a", alpha, 0.15).set_delay(delay)
			card.set_meta("tw", tw)
		else:
			card.position = pos
			card.rotation = rot
			card.scale = sc
			card.modulate.a = alpha
	# "Play card" sits under the pulled-out card.
	_play_btn.visible = _selected != null
	if _selected != null:
		_play_btn.position = Vector2(view.x * 0.5 - _play_btn.size.x * 0.5,
				view.y * 0.38 + ActionCard.SIZE.y * PICK_SCALE * 0.5 + 18.0)
		var ok := player.can_play_hand_card(_selected.kind)
		_play_btn.disabled = not ok
		_status.text = HandCards.title(_selected.kind) if ok else HandCards.hint(_selected.kind)


## Pulls `card` out of the fan (null puts it back).
func _select(card: ActionCard) -> void:
	_selected = card
	if card == null:
		_status.text = "Click a card to look at it."
	_layout(true)


func _play_selected() -> void:
	if _selected == null:
		return
	var kind := _selected.kind
	if not player.play_hand_card(kind):
		return
	var msg := HandCards.title(kind) + ": " + HandCards.result_text(kind, player)
	_fill(false)
	_status.text = msg


## Lifts and straightens a hovered card of the fan (not while one is pulled out).
func _hover_card(card: ActionCard, on: bool) -> void:
	if not is_instance_valid(card) or _selected != null:
		return
	card.z_index = 10 if on else 0
	var rest_pos: Vector2 = card.get_meta("rest_pos")
	var rest_rot: float = card.get_meta("rest_rot")
	var old: Tween = card.get_meta("tw", null)
	if old != null:
		old.kill()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "position", rest_pos - Vector2(0, LIFT) if on else rest_pos, 0.12)
	tw.tween_property(card, "rotation", 0.0 if on else rest_rot, 0.12)
	tw.tween_property(card, "scale", Vector2(1.12, 1.12) if on else Vector2.ONE, 0.12)
	card.set_meta("tw", tw)


func _input(event: InputEvent) -> void:
	var back := false
	if event is InputEventKey:
		var key := event as InputEventKey
		back = key.pressed and not key.echo and key.keycode == KEY_ESCAPE
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		back = mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT
	if not back:
		return
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() - _opened_at <= GRACE_MS:
		return
	if _selected != null:
		_select(null)
	else:
		_close()


func _close() -> void:
	closed.emit()
	queue_free()
