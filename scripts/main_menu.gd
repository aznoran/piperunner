## Title screen. Sits over a live but empty board — the cart and its runway are
## visible, nothing else — and replaces the offer strip with three buttons:
## upgrades on the left, start in the middle, settings on the right.
class_name MainMenu
extends CanvasLayer

signal start_pressed
## Emitted when the player picks a different cart look.
signal cart_chosen(variant: int)
## Emitted when a mode is picked in the carousel, as one of MODE_*.
signal mode_chosen(mode: int)
## Debug only: hand a classic run to the autoplayer, at this standard of play.
signal autoplay_requested(level: float, persona: Persona)
## Emitted when a station is picked on the story map.
signal level_chosen(number: int)


## Style for the buy buttons, built once rather than per row.
const BUY_RADIUS := 20
## Mode ids, matching Main.Mode so the signal needs no translation. The gap at
## one is where the daily was; Main's enum keeps it so a saved mode from an
## older build does not come back as the wrong game.
const MODE_CLASSIC := 0
const MODE_STORY := 2
## Bar tabs: corner radius and the depth of the bottom lip that gives them
## their pressable look.
const TAB_RADIUS := 16
## The baked button face and the 9-patch inset that keeps its corners crisp.
const TAB_FACE := "res://art/ui/tab_face.png"
const TAB_MARGIN := 18
const TAB_LIP := 6
## Seconds the whole menu takes to fade in or out.
const FADE_TIME := 0.24

@onready var _bar: Control = $Bar
@onready var _how_panel: Control = %HowPanel
@onready var _settings_panel: Control = %SettingsPanel
@onready var _upgrades_panel: Control = %UpgradesPanel
@onready var _quests_panel: Control = %QuestsPanel
@onready var _modes_panel: Control = %ModesPanel
@onready var _levels_panel: Control = %LevelsPanel
@onready var _quest_rows: VBoxContainer = %QuestRows
@onready var _shop_rows: VBoxContainer = %ShopRows
@onready var _wallet: Label = %Wallet
@onready var _best_label: Label = %BestLabel
@onready var _haptics_toggle: CheckButton = %HapticsToggle

## The keyboard layout picker. Built in code and null on the phone builds,
## where there is no keyboard to lay out.
var _keys_picker: OptionButton

## Buy button per upgrade id, so a purchase refreshes without rebuilding rows.
var _rows: Dictionary = {}
var _face: Texture2D
## The fade in flight, if any. Kept so a new one can cancel it.
var _fade_tween: Tween
## Kept so a repaint can put the mode name back in the right colour.
var _mode_kind: int = MODE_CLASSIC
## The tuning bench and the corner button that opens it. Debug builds only;
## null everywhere else.
var _bench: DebugPanel
var _bench_button: Button
## The story map. Built on first use — the panel is not opened on most runs,
## and a control that draws every frame should not exist until it is looked at.
var _map: StoryMap


func _ready() -> void:
	%StartButton.pressed.connect(func() -> void: start_pressed.emit())
	%UpgradesButton.pressed.connect(_toggle.bind(_upgrades_panel))
	%SettingsButton.pressed.connect(_toggle.bind(_settings_panel))
	%QuestsButton.pressed.connect(_toggle.bind(_quests_panel))
	%ModesButton.pressed.connect(_open_modes)
	%CloseModes.pressed.connect(_close_panels)
	%CloseLevels.pressed.connect(_open_modes)
	%CloseQuests.pressed.connect(_close_panels)
	%HowToButton.pressed.connect(_toggle.bind(_how_panel))
	# Settings holds the handful of switches that are not about the game. The
	# cart is worn in the depot beside the other things you own, the location
	# follows the station you are on, and the debug tools live on their own
	# bench behind a corner key. A reset button among them was a loaded gun
	# with no safety besides — a mis-tap cost a player everything they had.
	if OS.is_debug_build():
		_build_bench()
	%CloseHow.pressed.connect(_close_panels)
	%CloseSettings.pressed.connect(_close_panels)
	%CloseUpgrades.pressed.connect(_close_panels)
	_haptics_toggle.toggled.connect(_set_haptics)
	_hide_haptics_off_phone()
	_build_controls_row()
	_build_how_to()
	# Cloud progress can land after the menu is already up, and every number on
	# it belongs to the player.
	GameState.progress_reloaded.connect(_refresh)

	_build_shop()
	paint(Skins.current())
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_close_panels()


## Builds the tuning bench and the small corner key that opens it. Top left,
## clear of the title, where nothing else on the menu wants to be.
func _build_bench() -> void:
	_bench = DebugPanel.new()
	_bench.name = "DebugPanel"
	_bench.visible = false
	_bench.autoplay_requested.connect(func(level: float, style: Persona) -> void:
		_close_panels()
		autoplay_requested.emit(level, style))
	_bench.unlock_requested.connect(_debug_unlock)
	_bench.reset_requested.connect(_reset_progress)
	# Into the tree first: the panel measures the viewport as it builds, and
	# there is no viewport to measure until it is in there.
	add_child(_bench)
	_bench.setup(_balance_sheet())

	_bench_button = Button.new()
	_bench_button.name = "BenchButton"
	_bench_button.text = "DEV"
	_bench_button.custom_minimum_size = Vector2(96, 56)
	_bench_button.add_theme_font_size_override("font_size", 20)
	_bench_button.position = Vector2(20,
		SafeArea.insets(get_viewport().get_visible_rect().size).y + 20)
	_bench_button.pressed.connect(func() -> void:
		_close_panels()
		_bench.visible = true
		# The key sits where the bench draws its heading, so it stands down
		# while the bench is up rather than overlapping it.
		_bench_button.visible = false)
	_bench.visibility_changed.connect(func() -> void:
		_bench_button.visible = not _bench.visible)
	add_child(_bench_button)


## The baseline the bench edits: changes have to land on the sheet a run is
## built from, not on the copy the current run is already using.
func _balance_sheet() -> GameBalance:
	var main := get_parent()
	if main != null and "base_balance" in main:
		return main.base_balance
	return null


func open() -> void:
	visible = true
	_close_panels()
	_refresh()
	# Snap to fully visible before fading in. A transition left half-finished
	# — an interrupted fade, a callback that fired late — could otherwise leave
	# the menu drawn but transparent, or hidden underneath itself: it looks
	# open and swallows every tap.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	for child in get_children():
		if child is CanvasItem:
			(child as CanvasItem).modulate.a = 1.0
	_fade(1.0, FADE_TIME)


## Fades the menu away and hides it once it is gone, so the board underneath is
## uncovered rather than uncovered-and-flashed.
func fade_out(duration: float = FADE_TIME) -> void:
	var tween := _fade(0.0, duration)
	tween.chain().tween_callback(close)


## Cancels any fade already running. Without this, backing out of a run while
## the start fade is still in flight lets the old tween finish and hide the
## menu underneath the new one — it looks open but swallows every tap.
func _fade(alpha: float, duration: float) -> Tween:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	var tween := create_tween().set_parallel(true)
	_fade_tween = tween
	for child in get_children():
		if child is CanvasItem:
			if alpha > 0.0 and not (child as CanvasItem).visible:
				continue  # closed panels stay closed
			tween.tween_property(child, "modulate:a", alpha, duration)
	return tween


func close() -> void:
	visible = false
	_close_panels()
	if _bench != null:
		_bench.visible = false


## Lays the lower half out: mode label, run key, then a loose row of icons.
## There is no panel behind them on purpose — the board is the backdrop, the
## way the play object is the backdrop on a Knife Hit style menu.
func _relayout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var bottom_inset := SafeArea.insets(viewport).w
	var icons_height := 178.0
	var height: float = icons_height + 270.0
	_bar.size = Vector2(viewport.x, height)
	# Clear of the home gesture and of the screen edge: captions sitting on the
	# bezel read as clipped even when they are not.
	_bar.position = Vector2(0.0, viewport.y - height - bottom_inset - 52.0)
	(%Column as Control).offset_bottom = -icons_height


## Repaints the chrome in the location's colours. The scene file carries one
## palette; everything that varies by location is set here.
func paint(skin: LocationSkin) -> void:
	_face = load(TAB_FACE)

	_paint_key(%StartButton, skin, skin.accent, true)
	_paint_key(%UpgradesButton, skin, skin.accent, false)
	_paint_key(%ModesButton, skin, skin.warn, false)
	_paint_key(%QuestsButton, skin, skin.accent, false)
	_paint_key(%SettingsButton, skin, skin.pipe_core, false)
	%ModeLabel.add_theme_color_override("font_color",
		Color(_mode_tint(skin, _mode_kind), 0.9))
	(_modes_panel.get_node("Heading") as Label).add_theme_color_override(
		"font_color", skin.accent)
	(_levels_panel.get_node("Heading") as Label).add_theme_color_override(
		"font_color", _mode_tint(skin, MODE_STORY))

	for path in ["%CloseHow", "%CloseSettings", "%CloseUpgrades", "%CloseQuests",
			"%CloseModes", "%CloseLevels",
			"%HowToButton"]:
		var button: Button = get_node_or_null(path)
		if button != null:
			_paint_ghost(button, skin, skin.accent)
	if _bench_button != null:
		_paint_ghost(_bench_button, skin, skin.warn)


	for path in ["%HowPanel", "%SettingsPanel", "%UpgradesPanel", "%QuestsPanel"]:
		var panel: Control = get_node_or_null(path)
		if panel == null:
			continue
		var box: PanelContainer = panel.get_node_or_null("Box")
		if box == null:
			continue
		var style := StyleBoxFlat.new()
		style.bg_color = Color(skin.bg_mid, 0.97)
		style.border_color = Color(skin.accent, 0.35)
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		style.content_margin_left = 24.0
		style.content_margin_right = 24.0
		style.content_margin_top = 22.0
		style.content_margin_bottom = 22.0
		box.add_theme_stylebox_override("panel", style)

	%Wallet.add_theme_color_override("font_color", skin.accent)


## A key: the baked gradient face, tinted per state. `primary` is the run key —
## filled with the accent, everything else washed with a hint of its own colour
## so the row is not four grey squares.
func _paint_key(button: Button, skin: LocationSkin, tint: Color, primary: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxTexture.new()
		box.texture = _face
		box.set_texture_margin_all(TAB_MARGIN)
		box.modulate_color = _key_tint(skin, tint, primary, state)
		box.content_margin_top = float(TAB_LIP if state == "pressed" else 0)
		button.add_theme_stylebox_override(state, box)

	if primary:
		for key in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(key, skin.bg_bottom.darkened(0.25))
		return

	(button.get_node("Icon") as TabIcon).color = tint
	var caption: Label = button.get_parent().get_node("Caption")
	caption.add_theme_color_override("font_color", Color(tint, 0.72))

	var badge: Label = button.get_node_or_null("Badge")
	if badge != null:
		var pill := StyleBoxFlat.new()
		pill.bg_color = skin.danger
		pill.set_corner_radius_all(20)
		pill.border_color = Color(skin.bg_bottom, 0.85)
		pill.set_border_width_all(3)
		badge.add_theme_stylebox_override("normal", pill)
		badge.add_theme_color_override("font_color", Color.WHITE)


## Outlined button, used inside the panels where a filled key would shout.
func _ghost_style(skin: LocationSkin, tint: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(skin.bg_mid, 0.85)
	box.border_color = Color(tint, 0.45)
	box.set_border_width_all(2)
	box.set_corner_radius_all(28)
	box.content_margin_left = 26.0
	box.content_margin_right = 26.0
	box.content_margin_top = 20.0
	box.content_margin_bottom = 20.0
	return box


func _paint_ghost(button: Button, skin: LocationSkin, tint: Color) -> void:
	button.add_theme_color_override("font_color", tint)
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, _ghost_style(skin, tint))


func _key_tint(skin: LocationSkin, tint: Color, primary: bool, state: String) -> Color:
	if primary:
		return tint.darkened(0.16) if state == "pressed" else tint
	var base := skin.bg_top.lightened(0.18).lerp(tint, 0.14)
	if state == "pressed":
		return base.darkened(0.12)
	if state == "hover":
		return base.lightened(0.06)
	return base


func _toggle(panel: Control) -> void:
	var opening := not panel.visible
	_close_panels()
	panel.visible = opening
	if opening:
		_refresh()


func _close_panels() -> void:
	_set_menu_chrome(true)
	_how_panel.visible = false
	_settings_panel.visible = false
	_upgrades_panel.visible = false
	_quests_panel.visible = false
	_modes_panel.visible = false
	_levels_panel.visible = false


## Title, mode name and the bar — everything the mode picker replaces.
func _set_menu_chrome(shown: bool) -> void:
	for path in ["Title", "ModeLabel", "ModeGoal", "Bar"]:
		var node: CanvasItem = get_node_or_null(path)
		if node == null:
			continue
		# The goal line only exists on a station, so it stays hidden unless one
		# is selected.
		if path == "ModeGoal" and (node as Label).text.is_empty():
			continue
		node.visible = shown


func _refresh() -> void:
	_set_badge(%ModesButton, 0)

	_best_label.text = tr("Best run: %d") % GameState.best
	if _haptics_toggle != null:
		_haptics_toggle.set_pressed_no_signal(GameState.haptics_enabled)
	if _keys_picker != null:
		_keys_picker.select(KeyScheme.clamp_id(GameState.key_scheme))
	_refresh_shop()
	_build_quests()


# --- shop ---------------------------------------------------------------

## One row per upgrade: what it does, how far it is bought, and the price of
## the next level.
## The depot: power-ups to stock and strengthen, and carts to wear.
##
## It used to sell upgrades — a bigger tank, a longer preview — and they were
## quietly the wrong thing. An upgrade is a number that goes up once and then
## sits there: it makes every run a little longer and no run more interesting,
## and by the third attempt nobody notices it. What is sold here now is either
## a decision the player makes during a run, or something they can see.
##
## One row a power-up, with both purchases on it. Charges are what runs out and
## the level is what is kept — separate buttons, because they are separate
## things and a single one would mean guessing which was meant.
func _build_shop() -> void:
	for child in _shop_rows.get_children():
		child.queue_free()
	_rows.clear()

	_shop_heading(tr("POWER-UPS"))
	for power in PowerUps.catalogue():
		_power_row(power)

	var carts := Skins.current().cart_variant_count()
	if carts > 1:
		_shop_heading(tr("CARTS"))
		for variant in carts:
			_cart_row(variant)

	_refresh_shop()


func _shop_heading(text: String) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 2)
	_shop_rows.add_child(pad)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color",
		Color(Skins.current().accent, 0.7))
	_shop_rows.add_child(label)


## One card a power-up: what it is at the top, and underneath the two things
## that can be bought for it, each on its own line with its own price.
##
## They used to be two unlabelled buttons stacked in the corner, both reading
## "+1" and a number, and there was no way to tell from looking which one
## stocked the thing and which one made it stronger. A price is only a price
## if you know what it buys.
func _power_row(power: PowerUp) -> void:
	var skin := Skins.current()

	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(skin.bg_top, 0.55)
	box.border_color = Color(skin.pipe_shell, 0.5)
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	box.content_margin_left = 13.0
	box.content_margin_right = 13.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", box)
	_shop_rows.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	card.add_child(column)

	# The icon is the one the run screen draws, so a power-up is the same
	# object in both places rather than a word here and a shape there.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 11)
	column.add_child(head)

	var mark := TabIcon.new()
	mark.kind = power.icon
	mark.color = skin.accent
	mark.custom_minimum_size = Vector2(34, 34)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(mark)

	var named := VBoxContainer.new()
	named.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	named.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	named.add_theme_constant_override("separation", 3)
	head.add_child(named)

	var title := Label.new()
	title.text = tr(power.display_name)
	title.add_theme_font_size_override("font_size", 19)
	named.add_child(title)

	var blurb := Label.new()
	blurb.text = tr(power.description)
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.modulate.a = 0.55
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(180, 0)
	named.add_child(blurb)

	# How many are in hand, where the eye lands first. This is the number the
	# player came to check.
	var held := Label.new()
	held.add_theme_font_size_override("font_size", 26)
	held.add_theme_color_override("font_color", skin.accent)
	held.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	held.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	held.custom_minimum_size = Vector2(52, 0)
	head.add_child(held)

	var stock_note := Label.new()
	var stock := _shop_key()
	stock.pressed.connect(_buy_charge.bind(power.id))
	column.add_child(_buy_line(stock_note, stock))

	var level_note := Label.new()
	var level := _shop_key()
	level.pressed.connect(_buy_level.bind(power.id))
	column.add_child(_buy_line(level_note, level))

	# Pips rather than "level 2 of 4": four dots say the same thing without
	# arithmetic, and they say it from across the room.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 5)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dots: Array[Panel] = []
	for i in power.max_level():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dots.append(dot)
		pips.add_child(dot)
	(level_note.get_parent() as HBoxContainer).add_child(pips)
	(level_note.get_parent() as HBoxContainer).move_child(pips, 1)

	_rows[String(power.id)] = {
		"id": power.id, "held": held, "dots": dots,
		"stock": stock, "stock_note": stock_note,
		"level": level, "level_note": level_note,
	}


## A purchase: what it buys on the left, what it costs on the button.
func _buy_line(note: Label, key: Button) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	note.add_theme_font_size_override("font_size", 14)
	note.modulate.a = 0.8
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(note)
	line.add_child(key)
	return line


## A cart is worn rather than bought, until there is art worth charging for.
## The swatch is the cart itself, so the row shows the thing instead of naming
## it.
func _cart_row(variant: int) -> void:
	var skin := Skins.current()

	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(skin.bg_top, 0.55)
	box.border_color = Color(skin.pipe_shell, 0.5)
	box.set_border_width_all(2)
	box.set_corner_radius_all(16)
	box.content_margin_left = 13.0
	box.content_margin_right = 13.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", box)
	_shop_rows.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 11)
	card.add_child(row)

	# The cart's own picture where there is one. A bare colour swatch was the
	# same white rectangle for every variant, which told the player nothing
	# about what they were putting on.
	var art: Array[Texture2D] = skin.cart_variants
	if variant < art.size() and art[variant] != null:
		var shown := TextureRect.new()
		shown.texture = art[variant]
		shown.custom_minimum_size = Vector2(46, 38)
		shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(shown)
	else:
		var swatch := Panel.new()
		var chip := StyleBoxFlat.new()
		chip.bg_color = skin.cart_body
		chip.border_color = Color(skin.cart_glow, 0.8)
		chip.set_border_width_all(2)
		chip.set_corner_radius_all(8)
		swatch.add_theme_stylebox_override("panel", chip)
		swatch.custom_minimum_size = Vector2(46, 32)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)

	var title := Label.new()
	title.text = tr("Cart %d") % (variant + 1)
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	var wear := _shop_key()
	wear.pressed.connect(_pick_cart.bind(variant))
	row.add_child(wear)

	_rows["cart_%d" % variant] = {
		"title": title, "wear": wear, "variant": variant,
	}


func _shop_key() -> Button:
	var key := Button.new()
	key.add_theme_font_size_override("font_size", 15)
	for what in ["normal", "hover", "pressed"]:
		key.add_theme_stylebox_override(what, _buy_style())
	key.custom_minimum_size = Vector2(112, 38)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return key


func _buy_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Skins.current().accent, 0.16)
	box.border_color = Color(Skins.current().accent, 0.55)
	box.set_border_width_all(2)
	box.set_corner_radius_all(BUY_RADIUS)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 9.0
	box.content_margin_bottom = 9.0
	return box


func _refresh_shop() -> void:
	var skin := Skins.current()
	_wallet.text = tr("%d crystals") % GameState.crystals

	for power in PowerUps.catalogue():
		var row: Dictionary = _rows.get(String(power.id), {})
		if row.is_empty():
			continue

		var held := PowerUps.charges(power.id, GameState)
		var strength := PowerUps.level(power.id, GameState)
		var worth := PowerUps.value(power.id, GameState)
		(row["held"] as Label).text = "×%d" % held

		var stock_cost := PowerUps.charge_cost(power.id, GameState)
		var stock: Button = row["stock"]
		# Named before it is priced: the note says what the money buys, the
		# button says what it costs.
		(row["stock_note"] as Label).text = tr("One more charge")
		stock.text = "+1   ·   %d" % stock_cost
		stock.disabled = GameState.crystals < stock_cost

		var level_key: Button = row["level"]
		var up_cost := PowerUps.upgrade_cost(power.id, GameState)
		(row["level_note"] as Label).text = tr("%s %s each") % [
			_format(worth), tr(power.unit)]
		if up_cost < 0:
			level_key.text = tr("MAXED")
			level_key.disabled = true
		else:
			level_key.text = tr("%s %s   ·   %d") % [
				_format(worth + power.step), tr(power.unit), up_cost]
			level_key.disabled = GameState.crystals < up_cost

		var dots: Array = row["dots"]
		for i in dots.size():
			var pip := StyleBoxFlat.new()
			pip.bg_color = Color(skin.accent, 0.9) if i < strength \
				else Color(1, 1, 1, 0.13)
			pip.set_corner_radius_all(5)
			(dots[i] as Panel).add_theme_stylebox_override("panel", pip)

		for key: Button in [stock, level_key]:
			key.modulate.a = 1.0 if not key.disabled else 0.4

	for variant in skin.cart_variant_count():
		var row: Dictionary = _rows.get("cart_%d" % variant, {})
		if row.is_empty():
			continue
		var wear: Button = row["wear"]
		var worn: bool = GameState.cart_variant == variant
		wear.text = tr("WORN") if worn else tr("WEAR")
		wear.disabled = worn
		wear.modulate.a = 1.0 if not worn else 0.4

## Trims the trailing zero off whole numbers: 15.0 -> "15".
func _format(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _buy_charge(id: StringName) -> void:
	if PowerUps.buy_charge(id, GameState):
		GameState.vibrate(20)
	_refresh_shop()


func _buy_level(id: StringName) -> void:
	if PowerUps.buy_upgrade(id, GameState):
		GameState.vibrate(20)
	_refresh_shop()


## Carts cost nothing yet — they are the skins the shop is being cleared for,
## and until there is art to sell, wearing one is free. The row is here so the
## place they will live exists rather than arriving as a surprise.
func _pick_cart(variant: int) -> void:
	GameState.cart_variant = variant
	GameState.save_game()
	cart_chosen.emit(variant)
	GameState.vibrate(20)
	_refresh_shop()


# --- modes --------------------------------------------------------------

## Darkens the screen and shows the mode cards. Picking one drops straight
## The name shown under the title, so the menu always says what the run key
## will launch. Today's map takes the warning colour it wears everywhere else,
## so the mode is recognisable before the word is read.
func set_mode_name(mode: String, kind: int = MODE_CLASSIC, goal: String = "") -> void:
	_mode_kind = kind
	var tint := _mode_tint(Skins.current(), kind)

	# The name is always repainted. Skipping it when there is no goal line left
	# the previous mode's colour on the new mode's name — classic came out in
	# the story colour after visiting a station.
	%ModeLabel.text = mode
	%ModeLabel.add_theme_color_override("font_color", Color(tint, 0.9))

	%ModeGoal.text = goal
	%ModeGoal.visible = not goal.is_empty()
	if not goal.is_empty():
		%ModeGoal.add_theme_color_override("font_color", Color(tint, 0.62))


func _mode_tint(skin: LocationSkin, kind: int) -> Color:
	match kind:
		MODE_STORY:
			return skin.shape_color(PipeDefs.Type.UL)
		_:
			return skin.accent


func _open_modes() -> void:
	_close_panels()
	_build_modes()
	_modes_panel.visible = true
	# The picker is its own screen, not an overlay on the menu: the title and
	# the bar go away rather than glowing through the shade.
	_set_menu_chrome(false)


func _build_modes() -> void:
	var cards: BoxContainer = %Cards
	for child in cards.get_children():
		child.queue_free()

	# Two modes, so they get the width three were sharing. A card wide enough
	# to read is worth more than a third mode nobody asked for: Today was one
	# map a day that shared its rules with classic and its board with nobody,
	# and it earned neither the tab nor the space.
	var skin := Skins.current()
	_add_mode_card(cards, tr("CLASSIC"), MODE_CLASSIC, skin.accent,
		tr("Endless. One life, one board, as far as you can take it."),
		tr("FURTHEST"), str(GameState.best_distance))
	_add_mode_card(cards, tr("STORY"), MODE_STORY, _mode_tint(skin, MODE_STORY),
		tr("Stations with a goal each. Fixed maps, learned one at a time."),
		tr("CLEARED"), "%d/%d" % [GameState.levels_cleared, Levels.count()])


func _add_mode_card(into: BoxContainer, title: String, kind: int,
		tint: Color, blurb: String, stat_name: String, stat: String) -> void:
	var skin := Skins.current()
	var card := Button.new()
	# Stacked, full width. Side by side the pair was clipped at the edge of a
	# portrait screen, and a mode you cannot see is a mode you do not play.
	card.custom_minimum_size = Vector2(0, 168)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.pressed.connect(_pick_mode.bind(kind))

	var current: bool = kind == _mode_kind
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = skin.bg_top.lightened(0.14).lerp(tint,
			0.18 if current else 0.08)
		box.border_color = Color(tint, 0.9 if current else 0.4)
		box.set_border_width_all(2)
		box.set_corner_radius_all(22)
		box.border_width_bottom = 7
		card.add_theme_stylebox_override(state, box)
	into.add_child(card)

	var line := HBoxContainer.new()
	line.set_anchors_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 20.0
	line.offset_right = -20.0
	line.offset_top = 18.0
	line.offset_bottom = -24.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 16)
	card.add_child(line)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 8)
	line.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	column.add_child(top)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", tint)
	top.add_child(heading)

	# Which mode the start key will actually launch. Without it the picker
	# closes and the player has to read the line under the title to find out
	# whether the tap took.
	if kind == _mode_kind:
		var here := Label.new()
		here.text = tr("PLAYING")
		here.add_theme_font_size_override("font_size", 12)
		here.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(tint, 0.22)
		pill.set_corner_radius_all(9)
		pill.content_margin_left = 9.0
		pill.content_margin_right = 9.0
		pill.content_margin_top = 3.0
		pill.content_margin_bottom = 3.0
		here.add_theme_stylebox_override("normal", pill)
		here.add_theme_color_override("font_color", tint)
		top.add_child(here)

	var text := Label.new()
	text.text = blurb
	text.add_theme_font_size_override("font_size", 15)
	text.modulate.a = 0.66
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(180, 0)
	column.add_child(text)

	# The number the mode is played for, off to the side where the eye can
	# compare the two cards down a single column.
	var figure := VBoxContainer.new()
	figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	figure.add_theme_constant_override("separation", 2)
	figure.custom_minimum_size = Vector2(96, 0)
	line.add_child(figure)

	var caption := Label.new()
	caption.text = stat_name
	caption.add_theme_font_size_override("font_size", 13)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.modulate.a = 0.45
	figure.add_child(caption)

	var value := Label.new()
	value.text = stat
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 32)
	value.add_theme_color_override("font_color", tint)
	figure.add_child(value)


func _pick_mode(kind: int) -> void:
	GameState.vibrate(20)
	if kind == MODE_STORY:
		# Story goes one level deeper: which station, not just which mode.
		_open_levels()
		return
	mode_chosen.emit(kind)
	_close_panels()
	_refresh()


## The story map: one row per station, in order, with the next one to play
## called out. A straight line rather than a branching board — the chain is
## linear, and pretending otherwise would be decoration.
func _open_levels() -> void:
	_close_panels()
	_build_levels()
	_levels_panel.visible = true
	_set_menu_chrome(false)


## Lays the story map out for the progress as it now stands. Rebuilt on every
## open rather than patched, because the only thing that can have changed is a
## station being cleared, and redrawing twelve circles is free.
func _build_levels() -> void:
	var skin := Skins.current()
	# Progress and the next station's terms share this line, so the field below
	# stays a field — captions on it were a list again by another name.
	var next := Levels.current(GameState)
	%Progress.text = tr("%d of %d cleared") % [GameState.levels_cleared, Levels.count()]
	if next != null:
		%Progress.text += "   ·   %d  %s — %s" \
			% [next.number, tr(next.title), next.goal_short()]

	if _map == null:
		_map = StoryMap.new()
		_map.name = "Map"
		_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_map.station_picked.connect(_pick_level)
		# Straight into the scroll rather than into the box that used to hold
		# the rows: a box hugs its contents, so the map could never learn how
		# much height it had been given.
		var scroll: Control = _levels_panel.get_node("Scroll")
		(%Stations as Control).visible = false
		scroll.add_child(_map)
	_map.refresh(skin, _mode_tint(skin, MODE_STORY), GameState)
	# Deferred, because the scroll cannot be moved to a place its content does
	# not have yet: the map only learns its own height when the layout settles.
	_scroll_to_cart.call_deferred()


## Puts the panel where the cart is. The line runs off the top of the screen,
## and a story map that opens at the finish is a spoiler and a nuisance.
func _scroll_to_cart() -> void:
	var scroll: ScrollContainer = _levels_panel.get_node("Scroll")
	if scroll == null or _map == null:
		return
	scroll.scroll_vertical = int(_map.focus_offset(scroll.size.y))


func _pick_level(number: int) -> void:
	level_chosen.emit(number)
	GameState.vibrate(20)
	_close_panels()
	_refresh()


# --- daily goals --------------------------------------------------------

## One row per goal: what it asks for, how far along it is, and the payout.
## Rebuilt rather than patched, since the set changes at midnight and rows are
## cheap at three of them.
## The day's goals: what each asks for, how far along it is, and what it pays.
##
## Three states and they have to be told apart at a glance, because only one of
## them wants anything from the player. A goal in progress is quiet. A goal
## that is done and unpaid is the whole point of opening this panel and is lit
## accordingly. A goal already paid is out of the way but not deleted — seeing
## what you finished is part of what makes finishing worth it.
func _build_quests() -> void:
	Quests.ensure_today(GameState)

	var tally := Quests.tally(GameState)
	_set_badge(%QuestsButton, tally.y - tally.x if tally.y > tally.x else 0)
	_set_badge(%UpgradesButton, 1 if Quests.has_claimable(GameState) else 0)

	for child in _quest_rows.get_children():
		child.queue_free()

	var skin := Skins.current()
	for entry: Dictionary in GameState.quests:
		var quest := Quests.find(StringName(entry["id"]))
		if quest == null:
			continue
		_quest_row(quest, entry, skin)


func _quest_row(quest: Quest, entry: Dictionary, skin: LocationSkin) -> void:
	var target: int = int(entry["target"])
	var progress: int = mini(int(entry["progress"]), target)
	var done: bool = Quests.is_complete(entry)
	var claimed: bool = entry["claimed"]
	var ready: bool = done and not claimed

	# The row itself is a card, so a finished goal can light up as one object
	# rather than as a button that happens to be brighter.
	var card := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(skin.accent, 0.14) if ready else Color(skin.bg_top, 0.5)
	box.border_color = Color(skin.accent, 0.75) if ready \
		else Color(skin.pipe_shell, 0.4)
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 11.0
	box.content_margin_bottom = 11.0
	card.add_theme_stylebox_override("panel", box)
	_quest_rows.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 6)
	row.add_child(text)

	var head := HBoxContainer.new()
	text.add_child(head)

	var title := Label.new()
	title.text = quest.text(target)
	title.add_theme_font_size_override("font_size", 17)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.modulate.a = 0.45 if claimed else 1.0
	head.add_child(title)

	var count := Label.new()
	count.text = "%d/%d" % [progress, target]
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_color",
		skin.accent if done else Color(1, 1, 1, 0.55))
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(count)

	# A bar the skin can be seen in. The stock one is invisible on this
	# background, which made every goal look untouched however far along it
	# actually was.
	var bar := ProgressBar.new()
	bar.max_value = target
	bar.value = progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.09)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(skin.accent, 0.9 if done else 0.6)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", track)
	bar.add_theme_stylebox_override("fill", fill)
	bar.modulate.a = 0.45 if claimed else 1.0
	text.add_child(bar)

	var claim := Button.new()
	claim.add_theme_font_size_override("font_size", 16)
	claim.custom_minimum_size = Vector2(88, 46)
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed"]:
		claim.add_theme_stylebox_override(state,
			_claim_style(skin, ready))
	if claimed:
		# Not a tick: neither the game's face nor the bundled fallback has one,
		# so U+2713 drew as an empty box in every language. The radical sign is
		# the closest mark both fonts actually carry.
		claim.text = "√"
		claim.disabled = true
	elif ready:
		# The one thing on this panel worth tapping says what it pays.
		claim.text = "+%d" % quest.reward
		claim.pressed.connect(_claim.bind(String(entry["id"])))
	else:
		claim.text = "+%d" % quest.reward
		claim.disabled = true
	claim.modulate.a = 1.0 if ready else (0.35 if claimed else 0.5)
	row.add_child(claim)


## A filled key for the goal that is owed, an outlined one for the rest.
func _claim_style(skin: LocationSkin, ready: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(skin.accent, 0.9 if ready else 0.1)
	box.border_color = Color(skin.accent, 1.0 if ready else 0.4)
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	return box


func _claim(id: String) -> void:
	if Quests.claim(GameState, id) > 0:
		GameState.vibrate(30)
	_refresh()


# --- settings -----------------------------------------------------------

## Maxes out every upgrade and tops up the wallet, for testing the late-game
## feel without grinding to it. Debug builds only.
func _debug_unlock() -> void:
	if not OS.is_debug_build():
		return
	for power in PowerUps.catalogue():
		GameState.power_levels[String(power.id)] = power.max_level()
		GameState.power_charges[String(power.id)] = 99
	GameState.crystals = 9999
	GameState.save_game()
	GameState.vibrate(60)
	_refresh()


## Small count in the corner of a tab. Zero hides it — a badge that is always
## there stops being noticed.
func _set_badge(button: Button, count: int) -> void:
	var badge: Label = button.get_node_or_null("Badge")
	if badge == null:
		return
	badge.visible = count > 0
	badge.text = str(count)


## Takes the vibration switch out of Settings where there is nothing to
## vibrate. A browser is played on a desk as often as in a hand, and a switch
## that does nothing is worse than a missing one — it reads as broken.
##
## GameState.vibrate stops asking on the same platforms, so this hides a
## setting that is off rather than one that is on and unreachable.
func _hide_haptics_off_phone() -> void:
	if OS.has_feature("mobile"):
		return
	var row: Control = _haptics_toggle.get_parent()
	row.visible = false
	# Out of the column as well as out of sight: a VBoxContainer still spends
	# its separation on a hidden child, which left a gap where the row was.
	row.get_parent().remove_child(row)
	row.queue_free()
	# The refresh reads this every time the panel opens, and the node it points
	# at is on its way out.
	_haptics_toggle = null


## The rules card. Assembled here rather than held in the scene because its
## last line depends on what the player is holding: a phone is told about
## tapping and a browser about the keyboard, and neither wants to read the
## other's instructions.
func _build_how_to() -> void:
	var rules: RichTextLabel = _how_panel.get_node_or_null("Box/Column/Rules")
	if rules == null:
		return
	var text := tr("HOW_TO_RULES")
	if not OS.has_feature("mobile"):
		text += "\n" + tr("HOW_TO_KEYS")
	rules.text = text


## The keyboard row in Settings, in the place the vibration switch just left.
##
## In code rather than in the scene because it does not exist on every build:
## the phone exports have no keyboard, and a dead setting is worse than a
## missing one. Which is the same reason the switch it replaces is gone here —
## the two swap over on exactly the same platforms, so Settings ends up with
## one row either way rather than two on one platform and none on the other.
func _build_controls_row() -> void:
	if OS.has_feature("mobile"):
		return
	# Reached through the panel rather than through the vibration switch, which
	# by this point has been taken out of the tree.
	var column: VBoxContainer = _settings_panel.get_node("Box/Column")

	var row := HBoxContainer.new()
	row.name = "KeysRow"

	var label := Label.new()
	label.text = tr("Pick shape with")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)

	_keys_picker = OptionButton.new()
	_keys_picker.name = "KeysPicker"
	for name in KeyScheme.NAMES:
		_keys_picker.add_item(name)
	_keys_picker.select(KeyScheme.clamp_id(GameState.key_scheme))
	_keys_picker.item_selected.connect(_set_key_scheme)
	row.add_child(_keys_picker)

	column.add_child(row)
	column.move_child(row, _best_label.get_index() + 1)

	# One line under the picker, because the split between choosing and placing
	# is the only thing about the desktop controls that is not obvious, and the
	# strip itself only ever teaches half of it.
	var note := Label.new()
	note.name = "KeysNote"
	note.text = tr("Keys choose the shape · the mouse places it")
	note.modulate = Color(1.0, 1.0, 1.0, 0.55)
	note.add_theme_font_size_override("font_size", 14)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	column.move_child(note, row.get_index() + 1)


func _set_key_scheme(index: int) -> void:
	GameState.key_scheme = KeyScheme.clamp_id(index)
	GameState.save_game()


func _set_haptics(enabled: bool) -> void:
	GameState.haptics_enabled = enabled
	GameState.save_game()


func _reset_progress() -> void:
	GameState.best = 0
	GameState.crystals = 0
	GameState.upgrades.clear()
	GameState.quests.clear()
	GameState.levels_cleared = 0
	GameState.quest_date = ""
	GameState.save_game()
	GameState.best_changed.emit(0)
	_refresh()
