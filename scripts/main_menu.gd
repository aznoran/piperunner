## Title screen. Sits over a live but empty board — the cart and its runway are
## visible, nothing else — and replaces the queue strip with three buttons:
## how-to on the left, start in the middle, settings on the right.
class_name MainMenu
extends CanvasLayer

signal start_pressed

@onready var _bar: Control = $Bar
@onready var _how_panel: Control = %HowPanel
@onready var _settings_panel: Control = %SettingsPanel
@onready var _best_label: Label = %BestLabel
@onready var _haptics_toggle: CheckButton = %HapticsToggle


func _ready() -> void:
	%StartButton.pressed.connect(func() -> void: start_pressed.emit())
	%HowButton.pressed.connect(_toggle.bind(_how_panel))
	%SettingsButton.pressed.connect(_toggle.bind(_settings_panel))
	%CloseHow.pressed.connect(_close_panels)
	%CloseSettings.pressed.connect(_close_panels)
	%ResetBestButton.pressed.connect(_reset_best)
	_haptics_toggle.toggled.connect(_set_haptics)

	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_close_panels()


func open() -> void:
	visible = true
	_close_panels()
	_refresh_settings()


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
		_refresh_settings()


func _close_panels() -> void:
	_how_panel.visible = false
	_settings_panel.visible = false


func _refresh_settings() -> void:
	_best_label.text = "Best run: %d" % GameState.best
	_haptics_toggle.set_pressed_no_signal(GameState.haptics_enabled)


func _set_haptics(enabled: bool) -> void:
	GameState.haptics_enabled = enabled
	GameState.save_game()


func _reset_best() -> void:
	GameState.best = 0
	GameState.crystals = 0
	GameState.save_game()
	GameState.best_changed.emit(0)
	_refresh_settings()
