class_name NewWeaponPopup
extends CanvasLayer
## Full-screen "new weapon" card shown (with the game paused) when the player picks up a gun:
## the weapon's picture and name, then damage range, ammo capacity, reload speed and shot delay.
## Bars compare the weapon with the best of every weapon in Weapons.RANGED.

signal closed

const ACCENT := Color(1.0, 0.82, 0.3)
const DIM := Color(0.72, 0.74, 0.78)
const BAR_BG := Color(1, 1, 1, 0.12)
const HandCards := preload("res://scripts/hand_cards.gd")


static func show_for(parent: Node, key: String, info_only: bool = false) -> NewWeaponPopup:
	var p := NewWeaponPopup.new()
	p.layer = 25
	p.process_mode = Node.PROCESS_MODE_ALWAYS  # works while the game is paused
	parent.add_child(p)
	p._build(key, info_only)
	return p


func _build(key: String, info_only: bool = false) -> void:
	var w: Dictionary = Weapons.RANGED[key]
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.25)  # light dim so the map stays visible behind the card
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	# A compact centred card instead of a full-screen page.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.09, 0.1, 0.11, 0.92)
	card_style.border_color = Color(1, 1, 1, 0.25)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(6)
	card_style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = Vector2(640, 0)
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	card.add_child(page)

	# Header: small caption, weapon name, rule.
	page.add_child(_label("WEAPON SPECS" if info_only else "NEW WEAPON", 16, Color.WHITE))
	page.add_child(_label(str(w["label"]).to_upper(), 40, ACCENT))
	page.add_child(_rule())

	# Middle: the picture on the left, the stats on the right.
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 24)
	page.add_child(mid)
	var pic := Control.new()
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic.size_flags_stretch_ratio = 1.4
	pic.custom_minimum_size = Vector2(260, 160)
	pic.draw.connect(func() -> void:
		var box := minf(pic.size.x * 0.9, pic.size.y * 1.6)
		Weapons.draw_icon_at(pic, key, pic.size * 0.5, box))
	mid.add_child(pic)

	var stats := VBoxContainer.new()
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 8)
	mid.add_child(stats)
	# The player's bought upgrades (see weapon_upgrades.gd) are included in the numbers shown.
	var player := get_tree().get_first_node_in_group("player")
	var ups: Dictionary = player.get("upgrades") if player != null and "upgrades" in player else {}
	var dmg := Weapons.damage_range(key)
	var dmul := WeaponUpgrades.damage_mul(ups, key)
	if player != null and player.has_method("card_damage_mul"):
		dmul *= float(player.call("card_damage_mul", key))  # Upgrade Revolver cards
	var mag: int = int(player.call("mag", key)) if player != null and player.has_method("mag") else int(w["mag"])
	var dmg_lo := roundi(dmg.x * dmul)
	var dmg_hi := roundi(dmg.y * dmul)
	var dmg_text := str(dmg_lo) if dmg_lo == dmg_hi else "%d - %d" % [dmg_lo, dmg_hi]
	stats.add_child(_stat("DAMAGE RANGE", dmg_text, float(dmg_hi) / _best("dmg", true)))
	stats.add_child(_stat("AMMO CAPACITY", "%d rounds" % mag, float(mag) / _best("mag", true)))

	# Upgrade cards played on this weapon: the card, and what it added.
	var card_kind := HandCards.upgrade_card_for(key)
	var card_count := HandCards.upgrade_count(player, key) if player != null and card_kind != "" else 0
	if card_count > 0:
		var cd: Dictionary = HandCards.CARDS[card_kind]
		var holder := VBoxContainer.new()
		holder.alignment = BoxContainer.ALIGNMENT_CENTER
		holder.add_theme_constant_override("separation", 4)
		var shown := ActionCard.new()
		shown.rises = false
		shown.interactive = false
		shown.kind = card_kind
		shown.title = cd["title"]
		shown.desc = cd["desc"]
		shown.accent = cd["accent"]
		holder.add_child(shown)
		var added := _label("x%d  %s" % [card_count, HandCards.upgrade_effect(key, card_count)], 13, ACCENT)
		added.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(added)
		mid.add_child(holder)
		card.custom_minimum_size = Vector2(780, 0)
	# Shorter is better for the two time stats, so their bars fill up as the time drops.
	var reload_s := float(w["reload"]) * WeaponUpgrades.reload_mul(ups, key)
	stats.add_child(_stat("RELOAD SPEED", "%.1f s" % reload_s, _best("reload", false) / reload_s))
	var delay_s := float(w["cooldown"]) * WeaponUpgrades.delay_mul(ups, key)
	stats.add_child(_stat("SHOT DELAY", "%.2f s" % delay_s, _best("cooldown", false) / delay_s))

	# Footer.
	page.add_child(_rule())
	var foot := HBoxContainer.new()
	page.add_child(foot)
	var hint := _label("" if info_only else "Now in your hands. Switch weapons any time from the weapon wheel.", 12, DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var go := Button.new()
	go.text = "Close" if info_only else "Continue"
	go.custom_minimum_size = Vector2(120, 36)
	go.pressed.connect(_close)
	foot.add_child(go)
	go.grab_focus.call_deferred()  # Space / Enter also continue


func _close() -> void:
	closed.emit()
	queue_free()


## Best value of a stat across all weapons: the largest, or the smallest when `high` is false.
func _best(stat: String, high: bool) -> float:
	var best := 0.0 if high else INF
	for k in Weapons.RANGED:
		var v := float(Weapons.damage_range(k).y) if stat == "dmg" else float(Weapons.RANGED[k][stat])
		if stat == "dmg":
			v *= 1.0 + WeaponUpgrades.MAX_LEVEL * 0.1  # leave headroom so upgraded bars don't all cap at full
		best = maxf(best, v) if high else minf(best, v)
	return maxf(best, 0.001)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.3)
	r.custom_minimum_size.y = 1
	return r


## One stat: small caption, big value, and a bar showing how it compares with the best weapon.
func _stat(caption: String, value: String, fill: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_label(caption, 12, DIM))
	var line := HBoxContainer.new()
	box.add_child(line)
	var val := _label(value, 22, Color.WHITE)
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(val)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = clampf(fill, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(0, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = BAR_BG
	var fg := StyleBoxFlat.new()
	fg.bg_color = ACCENT
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	box.add_child(bar)
	return box
