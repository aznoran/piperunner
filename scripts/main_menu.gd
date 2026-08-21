## Title screen. Sits over a live but empty board — the cart and its runway are
## visible, nothing else — and replaces the queue strip with three buttons:
## upgrades on the left, start in the middle, settings on the right.
class_name MainMenu
extends CanvasLayer

signal start_pressed
## Today's fixed-seed challenge (spec section 11, P1).
signal daily_pressed

## Style for the buy buttons, built once rather than per row.
const BUY_RADIUS := 20

@onready var _bar: Control = $Bar
@onready var _how_panel: Control = %HowPanel
@onready var _settings_panel: Control = %SettingsPanel
@onready var _upgrades_panel: Control = %UpgradesPanel
@onready var _shop_rows: VBoxContainer = %ShopRows
@onready var _wallet: Label = %Wallet
@onready var _best_label: Label = %BestLabel
@onready var _haptics_toggle: CheckButton = %HapticsToggle

## Buy button per upgrade id, so a purchase refreshes without rebuilding rows.
var _rows: Dictionary = {}


func _ready() -> void:
	%StartButton.pressed.connect(func() -> void: start_pressed.emit())
	%DailyButton.pressed.connect(func() -> void: daily_pressed.emit())
	%UpgradesButton.pressed.connect(_toggle.bind(_upgrades_panel))
	%SettingsButton.pressed.connect(_toggle.bind(_settings_panel))
	%HowToButton.pressed.connect(_toggle.bind(_how_panel))
	%CloseHow.pressed.connect(_close_panels)
	%CloseSettings.pressed.connect(_close_panels)
	%CloseUpgrades.pressed.connect(_close_panels)
	%ResetBestButton.pressed.connect(_reset_progress)
	_haptics_toggle.toggled.connect(_set_haptics)

	_build_shop()
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_close_panels()


func open() -> void:
	visible = true
	_close_panels()
	_refresh()


func close() -> void:
	visible = false
	_close_panels()


## Keeps the button bar where the queue strip would be, clear of the system
## home gesture.
func _relayout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var bottom_inset := SafeArea.insets(viewport).w
	var height: float = maxf(viewport.y * 0.17, 130.0)
	_bar.size = Vector2(viewport.x, height)
	_bar.position = Vector2(0.0, viewport.y - height - bottom_inset)


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


func _refresh() -> void:
	var today: int = GameState.daily_result()
	%DailyButton.text = "DAILY  ·  BEST %d" % today if today > 0 else "DAILY RUN"
	_best_label.text = "Best run: %d" % GameState.best
	_haptics_toggle.set_pressed_no_signal(GameState.haptics_enabled)
	_refresh_shop()


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


# --- settings -----------------------------------------------------------

func _set_haptics(enabled: bool) -> void:
	GameState.haptics_enabled = enabled
	GameState.save_game()


func _reset_progress() -> void:
	GameState.best = 0
	GameState.crystals = 0
	GameState.upgrades.clear()
	GameState.save_game()
	GameState.best_changed.emit(0)
	_refresh()
