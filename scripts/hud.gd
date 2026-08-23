## Score, best, combo and the fuel bar, kept inside the safe area so notches
## and Dynamic Island never clip it (spec sections 12 and 13).
class_name Hud
extends CanvasLayer

## Emitted by the back key, which only exists before the first pipe.
signal back_pressed
## A power-up button was tapped. Main decides whether it can actually fire.
signal power_used(id: StringName)

const BAR_RADIUS := 7

@onready var _safe: MarginContainer = $Safe
@onready var _score_label: Label = %ScoreLabel
@onready var _best_label: Label = %BestLabel
@onready var _daily_label: Label = %DailyLabel
@onready var _objective: Label = %ObjectiveLabel
@onready var _combo_label: Label = %ComboLabel
@onready var _fuel_track: Panel = %FuelTrack
@onready var _fuel_bar: Panel = %FuelBar

## Size of a power-up key and how far it sits off the edge.
const POWER_SIZE := 66.0
const POWER_MARGIN := 16.0

var _power_bar: VBoxContainer
var _power_keys: Dictionary = {}
## True while the brake read-out has the combo label.
var _braking: bool = false

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
	%BackButton.pressed.connect(func() -> void: back_pressed.emit())
	_build_powers()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _process(delta: float) -> void:
	if _combo_fade > 0.0:
		_combo_fade -= delta
		if _combo_fade <= 0.0:
			_combo_label.modulate.a = 0.0


# --- power-ups ----------------------------------------------------------

## The power-up keys, down the right-hand edge where a thumb already is and
## nothing else lives. Built once; only their counts change after that.
func _build_powers() -> void:
	_power_bar = VBoxContainer.new()
	_power_bar.name = "Powers"
	_power_bar.add_theme_constant_override("separation", 10)
	_power_bar.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_power_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_power_bar.grow_vertical = Control.GROW_DIRECTION_BOTH
	_power_bar.offset_right = -POWER_MARGIN
	add_child(_power_bar)

	for power in PowerUps.catalogue():
		var key := Button.new()
		key.custom_minimum_size = Vector2(POWER_SIZE, POWER_SIZE)
		key.focus_mode = Control.FOCUS_NONE
		key.add_theme_font_size_override("font_size", 15)
		key.pressed.connect(func() -> void: power_used.emit(power.id))
		_power_bar.add_child(key)

		var count := Label.new()
		count.name = "Count"
		count.add_theme_font_size_override("font_size", 15)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		count.offset_top = -20.0
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.add_child(count)
		_power_keys[String(power.id)] = key


## Repaints the keys from what the player owns. A power-up with nothing left is
## dimmed and refuses the tap rather than vanishing — a key that disappears
## takes the knowledge that it exists with it.
func set_powers(state: Node) -> void:
	for power in PowerUps.catalogue():
		var key: Button = _power_keys.get(String(power.id))
		if key == null:
			continue
		var held := PowerUps.charges(power.id, state)
		key.text = power.short_name
		key.disabled = held <= 0
		key.modulate.a = 1.0 if held > 0 else 0.4
		var count: Label = key.get_node("Count")
		count.text = "x%d" % held
		count.add_theme_color_override("font_color",
			_skin.accent if held > 0 else Color(1, 1, 1, 0.5))

		var box := StyleBoxFlat.new()
		box.bg_color = Color(_skin.bg_top, 0.85)
		box.border_color = Color(_skin.accent if held > 0 else _skin.pipe_shell,
			0.7)
		box.set_border_width_all(2)
		box.set_corner_radius_all(14)
		for what in ["normal", "hover", "pressed", "disabled"]:
			key.add_theme_stylebox_override(what, box)


## Seconds left on the brake, shown where the combo is: both are things that
## are true for a moment and then are not.
func set_brake(seconds: float) -> void:
	if seconds <= 0.0:
		if _braking:
			_braking = false
			_combo_label.modulate.a = 0.0
		return
	_braking = true
	_combo_label.text = "HELD  %.1f" % seconds
	_combo_label.modulate.a = 1.0
	_combo_label.add_theme_color_override("font_color", _skin.accent)


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
	box.bg_color = Color(skin.bg_top, 0.72)
	box.border_color = Color(skin.accent, 0.28)
	box.set_border_width_all(1)
	box.set_corner_radius_all(26)
	for state in ["normal", "hover", "pressed"]:
		%BackButton.add_theme_stylebox_override(state, box)
	(%BackButton.get_node("Icon") as TabIcon).color = Color(skin.accent, 0.8)
	set_fuel(_fuel_ratio)


## The station's goal and how far along it is. Null hides the line, which is
## what an endless run wants.
func set_objective(level: Level, progress: int) -> void:
	_objective.visible = level != null
	if level == null:
		return
	_objective.text = "%s  ·  %d/%d" % [level.goal_short(),
		mini(progress, level.goal_target), level.goal_target]
	var done: bool = progress >= level.goal_target
	_objective.add_theme_color_override("font_color",
		_skin.accent if done else Color(_skin.pipe_core, 0.95))


## Shows the back key again for a fresh run.
func reset_back_key() -> void:
	%BackButton.visible = true
	%BackButton.modulate.a = 1.0
	%BackButton.disabled = false


## Retires it once the run commits: from here the way out is to finish. Fading
## rather than vanishing, so the eye is not pulled to the corner mid-run.
func fade_out_back_key() -> void:
	%BackButton.disabled = true
	var tween := create_tween()
	tween.tween_property(%BackButton, "modulate:a", 0.0, 0.35)
	tween.tween_callback(func() -> void: %BackButton.visible = false)


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
