## Score, best, combo and the fuel bar, kept inside the safe area so notches
## and Dynamic Island never clip it (spec sections 12 and 13).
class_name Hud
extends CanvasLayer

## Emitted by the back button: leave the run and return to the menu.
signal exit_pressed

const BAR_RADIUS := 7

@onready var _safe: MarginContainer = $Safe
@onready var _score_label: Label = %ScoreLabel
@onready var _best_label: Label = %BestLabel
@onready var _daily_label: Label = %DailyLabel
@onready var _combo_label: Label = %ComboLabel
@onready var _fuel_track: Panel = %FuelTrack
@onready var _fuel_bar: Panel = %FuelBar

var _skin: LocationSkin
var _track_box := StyleBoxFlat.new()
var _bar_box := StyleBoxFlat.new()
var _combo_fade: float = 0.0
var _fuel_ratio: float = 1.0


func _ready() -> void:
	set_skin(Skins.current())
	_track_box.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	_track_box.set_corner_radius_all(BAR_RADIUS)
	_fuel_track.add_theme_stylebox_override("panel", _track_box)

	_bar_box.bg_color = _skin.accent
	_bar_box.set_corner_radius_all(BAR_RADIUS)
	_fuel_bar.add_theme_stylebox_override("panel", _bar_box)

	_combo_label.modulate.a = 0.0
	%ExitButton.pressed.connect(func() -> void: exit_pressed.emit())
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _process(delta: float) -> void:
	if _combo_fade > 0.0:
		_combo_fade -= delta
		if _combo_fade <= 0.0:
			_combo_label.modulate.a = 0.0


func set_score(value: int) -> void:
	_score_label.text = "Score: %d" % value


func set_best(value: int) -> void:
	_best_label.text = "Best: %d" % value


## Marks the run as today's fixed-seed challenge, which otherwise looks
## exactly like an ordinary one.
## Restyles the back button for the location.
func set_skin(skin: LocationSkin) -> void:
	_skin = skin
	var box := StyleBoxFlat.new()
	box.bg_color = Color(skin.bg_top, 0.7)
	box.border_color = Color(skin.accent, 0.3)
	box.set_border_width_all(1)
	box.set_corner_radius_all(23)
	for state in ["normal", "hover", "pressed"]:
		%ExitButton.add_theme_stylebox_override(state, box)
	%ExitButton.add_theme_color_override("font_color", Color(skin.accent, 0.85))
	set_fuel(_fuel_ratio)


func set_daily(is_daily: bool, date: String = "") -> void:
	_daily_label.visible = is_daily
	_daily_label.text = "DAILY  ·  %s" % date if not date.is_empty() else "DAILY"


func set_combo(value: int) -> void:
	if value <= 0:
		_combo_label.modulate.a = 0.0
		_combo_fade = 0.0
		return
	_combo_label.text = "CHAIN x%d" % value
	_combo_label.modulate.a = 1.0
	_combo_fade = 2.5


## `ratio` is 0..1 of a full tank.
func set_fuel(ratio: float) -> void:
	_fuel_ratio = ratio
	var clamped := clampf(ratio, 0.0, 1.0)
	_fuel_bar.anchor_right = clamped
	_bar_box.bg_color = (_skin.accent if clamped > 0.5
		else _skin.warn if clamped > 0.25
		else _skin.danger)


## Pads the HUD by the OS safe area so notches never clip it.
func _apply_safe_area() -> void:
	var insets := SafeArea.insets(get_viewport().get_visible_rect().size)
	_safe.add_theme_constant_override("margin_left", int(insets.x) + 24)
	_safe.add_theme_constant_override("margin_top", int(insets.y) + 18)
	_safe.add_theme_constant_override("margin_right", int(insets.z) + 24)
