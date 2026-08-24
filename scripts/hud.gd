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
const POWER_SIZE := 78.0
const POWER_MARGIN := 14.0
## The bar's key face and the 9-patch inset that keeps its corners crisp — the
## same numbers the menu uses, because it is the same button.
const KEY_FACE := "res://art/ui/tab_face.png"
const KEY_MARGIN := 18
const KEY_LIP := 6.0

var _face: Texture2D
var _power_bar: VBoxContainer
var _power_keys: Dictionary = {}
## True while the brake read-out has the combo label.
var _braking: bool = false
## Seconds an announcement still has the label for.
const ANNOUNCE_TIME := 1.1
var _announcing: float = 0.0
var _speed_chip: Label
var _speed_pulse: float = 0.0

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
	_build_speed_chip()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _process(delta: float) -> void:
	_speed_pulse += delta
	# An announcement holds the label against the combo, which would otherwise
	# overwrite it the moment the next crystal came in.
	if _announcing > 0.0:
		_announcing -= delta
		if _announcing <= 0.0:
			_combo_label.modulate.a = 0.0
		return
	if _combo_fade > 0.0:
		_combo_fade -= delta
		if _combo_fade <= 0.0:
			_combo_label.modulate.a = 0.0


## The speed warning, sitting on the fuel line where the other clock is.
func _build_speed_chip() -> void:
	_speed_chip = Label.new()
	_speed_chip.name = "SpeedChip"
	_speed_chip.visible = false
	_speed_chip.add_theme_font_size_override("font_size", 17)
	_speed_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_speed_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_chip.offset_left = -180.0
	_speed_chip.offset_top = 4.0
	_speed_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(%FuelTrack as Control).get_parent().add_child(_speed_chip)


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

	_face = load(KEY_FACE)
	for power in PowerUps.catalogue():
		var key := Button.new()
		key.custom_minimum_size = Vector2(POWER_SIZE, POWER_SIZE)
		key.focus_mode = Control.FOCUS_NONE
		key.pressed.connect(func() -> void: power_used.emit(power.id))
		_power_bar.add_child(key)

		# Drawn, not written. The bar tabs already say what they are with a
		# shape, and two keys captioned LAY and STOP in the corner of a run
		# were the only place in the game asking to be read rather than seen.
		var mark := TabIcon.new()
		mark.name = "Mark"
		mark.kind = power.icon
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.offset_left = POWER_SIZE * 0.22
		mark.offset_top = POWER_SIZE * 0.18
		mark.offset_right = -POWER_SIZE * 0.22
		mark.offset_bottom = -POWER_SIZE * 0.3
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.add_child(mark)

		# The count as the same red pill the tabs wear, in the same corner.
		var badge := Label.new()
		badge.name = "Count"
		badge.add_theme_font_size_override("font_size", 16)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(26, 26)
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -18.0
		badge.offset_top = -8.0
		badge.offset_right = 8.0
		badge.offset_bottom = 18.0
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.add_child(badge)
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
		var ready: bool = held > 0
		key.disabled = not ready

		var mark: TabIcon = key.get_node("Mark")
		mark.color = _skin.accent if ready else Color(_skin.pipe_shell, 0.9)

		var badge: Label = key.get_node("Count")
		badge.text = str(held)
		badge.visible = ready
		var pill := StyleBoxFlat.new()
		pill.bg_color = _skin.danger
		pill.border_color = Color(_skin.bg_bottom, 0.85)
		pill.set_border_width_all(3)
		pill.set_corner_radius_all(20)
		badge.add_theme_stylebox_override("normal", pill)
		badge.add_theme_color_override("font_color", Color.WHITE)

		# The bar's own key face, so a power-up looks like the rest of the
		# game's furniture rather than like a debug button parked on top of it.
		for what in ["normal", "hover", "pressed", "disabled"]:
			var box := StyleBoxTexture.new()
			box.texture = _face
			box.set_texture_margin_all(KEY_MARGIN)
			var base: Color = _skin.bg_top.lightened(0.18).lerp(
				_skin.accent if ready else _skin.pipe_shell, 0.14)
			if what == "pressed":
				base = base.darkened(0.12)
				box.content_margin_top = KEY_LIP
			elif what == "hover":
				base = base.lightened(0.06)
			elif what == "disabled":
				base = base.darkened(0.22)
			box.modulate_color = base
			key.add_theme_stylebox_override(what, box)


## How fast the cart is, as a fraction of the way from its starting speed to
## the cap, and whether that is enough to be worth saying.
##
## Shown against the fuel bar rather than as another floating word: fuel and
## speed are the two clocks running a run down, and a player watching one is
## already looking at the other.
func set_speed(ratio: float, warn: bool) -> void:
	if _speed_chip == null:
		return
	_speed_chip.visible = warn
	if not warn:
		return
	_speed_chip.text = "FAST  ×%.1f" % (1.0 + ratio)
	var heat: Color = _skin.warn.lerp(_skin.danger, clampf(ratio, 0.0, 1.0))
	_speed_chip.add_theme_color_override("font_color", heat)
	# Breathing, so it reads as a state the run is in rather than as a label
	# that has always been there.
	_speed_chip.modulate.a = 0.7 + 0.3 * absf(sin(_speed_pulse * 3.0))


## A word held for a beat where the combo goes. Used for things that happen
## once and are over — the gate that slowed the cart, which otherwise announces
## itself only by a change in a speed nobody was reading.
func announce(text: String, tint: Color) -> void:
	_combo_label.text = text
	_combo_label.add_theme_color_override("font_color", tint)
	_combo_label.modulate.a = 1.0
	_announcing = ANNOUNCE_TIME


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
	if _announcing > 0.0:
		return  # an announcement has the label; the chain can wait its turn
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
