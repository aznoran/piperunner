## Title screen. Sits over a live but empty board — the cart and its runway are
## visible, nothing else — and replaces the queue strip with three buttons:
## upgrades on the left, start in the middle, settings on the right.
class_name MainMenu
extends CanvasLayer

signal start_pressed
## Emitted when the player picks a different location.
signal location_chosen(skin: LocationSkin)
## Emitted when the player picks a different cart look.
signal cart_chosen(variant: int)
## Today's fixed-seed challenge (spec section 11, P1).
signal daily_pressed

## Style for the buy buttons, built once rather than per row.
const BUY_RADIUS := 20
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
@onready var _quest_rows: VBoxContainer = %QuestRows
@onready var _shop_rows: VBoxContainer = %ShopRows
@onready var _wallet: Label = %Wallet
@onready var _best_label: Label = %BestLabel
@onready var _haptics_toggle: CheckButton = %HapticsToggle

## Buy button per upgrade id, so a purchase refreshes without rebuilding rows.
var _rows: Dictionary = {}
var _face: Texture2D
## The fade in flight, if any. Kept so a new one can cancel it.
var _fade_tween: Tween


func _ready() -> void:
	%StartButton.pressed.connect(func() -> void: start_pressed.emit())
	%DailyButton.pressed.connect(func() -> void: daily_pressed.emit())
	%UpgradesButton.pressed.connect(_toggle.bind(_upgrades_panel))
	%SettingsButton.pressed.connect(_toggle.bind(_settings_panel))
	%QuestsButton.pressed.connect(_toggle.bind(_quests_panel))
	%CloseQuests.pressed.connect(_close_panels)
	%HowToButton.pressed.connect(_toggle.bind(_how_panel))
	%LocationButton.pressed.connect(_cycle_location)
	%CartButton.pressed.connect(_cycle_cart)
	%DebugUnlockButton.pressed.connect(_debug_unlock)
	# Never ships: hidden outside a debug build.
	%DebugUnlockButton.visible = OS.is_debug_build()
	%CloseHow.pressed.connect(_close_panels)
	%CloseSettings.pressed.connect(_close_panels)
	%CloseUpgrades.pressed.connect(_close_panels)
	%ResetBestButton.pressed.connect(_reset_progress)
	_haptics_toggle.toggled.connect(_set_haptics)

	_build_shop()
	paint(Skins.current())
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_close_panels()


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
	_paint_key(%DailyButton, skin, skin.warn, false)
	_paint_key(%QuestsButton, skin, skin.accent, false)
	_paint_key(%SettingsButton, skin, skin.pipe_core, false)
	%ModeLabel.add_theme_color_override("font_color", Color(skin.accent, 0.85))

	for path in ["%CloseHow", "%CloseSettings", "%CloseUpgrades", "%CloseQuests",
			"%HowToButton", "%LocationButton", "%CartButton", "%DebugUnlockButton"]:
		var button: Button = get_node_or_null(path)
		if button != null:
			_paint_ghost(button, skin, skin.accent)
	var reset: Button = get_node_or_null("%ResetBestButton")
	if reset != null:
		_paint_ghost(reset, skin, skin.danger)

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
	_how_panel.visible = false
	_settings_panel.visible = false
	_upgrades_panel.visible = false
	_quests_panel.visible = false


func _refresh() -> void:
	_set_badge(%DailyButton, 1 if GameState.daily_result() <= 0 else 0)
	%LocationButton.text = "Location: %s" % Skins.current().display_name
	var carts := Skins.current().cart_variant_count()
	%CartButton.text = ("Cart: %d of %d" % [GameState.cart_variant % carts + 1, carts]
		if carts > 1 else "Cart: standard")
	%CartButton.disabled = carts <= 1
	%CartButton.modulate.a = 1.0 if carts > 1 else 0.45
	_best_label.text = "Best run: %d" % GameState.best
	_haptics_toggle.set_pressed_no_signal(GameState.haptics_enabled)
	_refresh_shop()
	_build_quests()


# --- shop ---------------------------------------------------------------

## One row per upgrade: what it does, how far it is bought, and the price of
## the next level.
func _build_shop() -> void:
	for child in _shop_rows.get_children():
		child.queue_free()
	_rows.clear()

	for upgrade in Upgrades.catalogue():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 2)

		var title := Label.new()
		title.add_theme_font_size_override("font_size", 19)
		text.add_child(title)

		var blurb := Label.new()
		blurb.add_theme_font_size_override("font_size", 14)
		blurb.modulate.a = 0.62
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(250, 0)
		blurb.text = upgrade.description
		text.add_child(blurb)

		row.add_child(text)

		var buy := Button.new()
		buy.add_theme_font_size_override("font_size", 17)
		buy.add_theme_stylebox_override("normal", _buy_style())
		buy.add_theme_stylebox_override("hover", _buy_style())
		buy.add_theme_stylebox_override("pressed", _buy_style())
		buy.custom_minimum_size = Vector2(96, 0)
		buy.pressed.connect(_buy.bind(upgrade.id))
		row.add_child(buy)

		_shop_rows.add_child(row)
		_rows[upgrade.id] = {"title": title, "buy": buy}

	_refresh_shop()


func _buy_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Skins.current().accent, 0.16)
	box.border_color = Color(Skins.current().accent, 0.55)
	box.set_border_width_all(2)
	box.set_corner_radius_all(BUY_RADIUS)
	box.content_margin_left = 14.0
	box.content_margin_right = 14.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	return box


func _refresh_shop() -> void:
	_wallet.text = "%d crystals" % GameState.crystals
	for upgrade in Upgrades.catalogue():
		if not _rows.has(upgrade.id):
			continue
		var level := Upgrades.level(upgrade.id, GameState)
		var title: Label = _rows[upgrade.id]["title"]
		var buy: Button = _rows[upgrade.id]["buy"]

		title.text = "%s   %d/%d" % [upgrade.display_name, level, upgrade.max_level()]
		if level > 0:
			title.text += "   (+%s %s)" % [_format(upgrade.step * level), upgrade.unit]

		var cost := Upgrades.next_cost(upgrade.id, GameState)
		if cost < 0:
			buy.text = "MAX"
			buy.disabled = true
		else:
			buy.text = str(cost)
			buy.disabled = not Upgrades.can_afford(upgrade.id, GameState)
		buy.modulate.a = 1.0 if not buy.disabled else 0.45


## Trims the trailing zero off whole numbers: 15.0 -> "15".
func _format(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


func _buy(id: StringName) -> void:
	if Upgrades.buy(id, GameState):
		GameState.vibrate(20)
	_refresh_shop()


# --- daily goals --------------------------------------------------------

## One row per goal: what it asks for, how far along it is, and the payout.
## Rebuilt rather than patched, since the set changes at midnight and rows are
## cheap at three of them.
func _build_quests() -> void:
	Quests.ensure_today(GameState)

	var tally := Quests.tally(GameState)
	_set_badge(%QuestsButton, tally.y - tally.x if tally.y > tally.x else 0)
	_set_badge(%UpgradesButton, 1 if Quests.has_claimable(GameState) else 0)

	for child in _quest_rows.get_children():
		child.queue_free()

	for entry: Dictionary in GameState.quests:
		var quest := Quests.find(StringName(entry["id"]))
		if quest == null:
			continue
		var target: int = int(entry["target"])
		var progress: int = mini(int(entry["progress"]), target)
		var done: bool = Quests.is_complete(entry)
		var claimed: bool = entry["claimed"]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 3)

		var title := Label.new()
		title.add_theme_font_size_override("font_size", 18)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size = Vector2(250, 0)
		title.text = quest.text(target)
		if claimed:
			title.modulate.a = 0.45
		text.add_child(title)

		var bar := ProgressBar.new()
		bar.max_value = target
		bar.value = progress
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(250, 10)
		text.add_child(bar)

		var count := Label.new()
		count.add_theme_font_size_override("font_size", 14)
		count.modulate.a = 0.6
		count.text = "%d / %d" % [progress, target]
		text.add_child(count)

		row.add_child(text)

		var claim := Button.new()
		claim.add_theme_font_size_override("font_size", 16)
		claim.add_theme_stylebox_override("normal", _buy_style())
		claim.add_theme_stylebox_override("hover", _buy_style())
		claim.add_theme_stylebox_override("pressed", _buy_style())
		claim.custom_minimum_size = Vector2(92, 0)
		if claimed:
			claim.text = "DONE"
			claim.disabled = true
		elif done:
			claim.text = "+%d" % quest.reward
			claim.pressed.connect(_claim.bind(String(entry["id"])))
		else:
			claim.text = "+%d" % quest.reward
			claim.disabled = true
		claim.modulate.a = 1.0 if not claim.disabled else 0.4
		row.add_child(claim)

		_quest_rows.add_child(row)


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
	for upgrade in Upgrades.catalogue():
		GameState.upgrades[String(upgrade.id)] = upgrade.max_level()
	GameState.crystals = 999
	GameState.save_game()
	GameState.vibrate(60)
	_refresh()


## Locations are looks, not rulesets, so switching is instant and harmless.
func _cycle_location() -> void:
	var skin := Skins.next()
	GameState.location = skin.display_name
	GameState.save_game()
	location_chosen.emit(skin)
	paint(skin)
	_build_shop()
	_refresh()


## Small count in the corner of a tab. Zero hides it — a badge that is always
## there stops being noticed.
func _set_badge(button: Button, count: int) -> void:
	var badge: Label = button.get_node_or_null("Badge")
	if badge == null:
		return
	badge.visible = count > 0
	badge.text = str(count)


func _cycle_cart() -> void:
	var carts := Skins.current().cart_variant_count()
	GameState.cart_variant = (GameState.cart_variant + 1) % carts
	GameState.save_game()
	cart_chosen.emit(GameState.cart_variant)
	GameState.vibrate(20)
	_refresh()


func _set_haptics(enabled: bool) -> void:
	GameState.haptics_enabled = enabled
	GameState.save_game()


func _reset_progress() -> void:
	GameState.best = 0
	GameState.crystals = 0
	GameState.upgrades.clear()
	GameState.quests.clear()
	GameState.quest_date = ""
	GameState.save_game()
	GameState.best_changed.emit(0)
	_refresh()
