## The tuning bench. Never ships: it is built only in a debug build, and the
## button that opens it is hidden everywhere else.
##
## Every number the game's feel rests on — how wide the offer is, how fast
## fuel drains, when praise fires, how well the bot plays — is a slider here,
## live, without a rebuild. Changes land on the baseline balance, so they apply
## from the next run and survive a retry, and they are gone when the app
## restarts: this is for trying things, not for saving them.
class_name DebugPanel
extends Control

## Runs a classic run under the autoplayer at the given standard of play.
signal autoplay_requested(level: float)
## Debug conveniences that used to live in Settings.
signal unlock_requested
signal reset_requested

## One row per number. `step` also decides how it is displayed: whole numbers
## for whole steps, two decimals otherwise.
const KNOBS := [
	{"group": "Bot"},
	{"id": "bot_level", "name": "Proficiency", "min": 0.0, "max": 1.0, "step": 0.05},

	{"group": "Offer"},
	{"id": "offer_size", "name": "Shapes on offer", "min": 1, "max": 7, "step": 1},

	{"group": "Fuel"},
	{"id": "fuel_max", "name": "Tank", "min": 40.0, "max": 240.0, "step": 5.0},
	{"id": "fuel_per_cell", "name": "Burn per cell", "min": 0.0, "max": 8.0, "step": 0.2},
	{"id": "fuel_per_second", "name": "Burn per second", "min": 0.0, "max": 3.0, "step": 0.1},
	{"id": "fuel_crystal", "name": "Crystal worth", "min": 5.0, "max": 80.0, "step": 1.0},
	{"id": "grace_cells", "name": "Grace cells", "min": 0, "max": 40, "step": 1},

	{"group": "Speed"},
	{"id": "start_speed", "name": "Start speed", "min": 0.2, "max": 2.0, "step": 0.02},
	{"id": "speed_gain", "name": "Speed per point", "min": 0.0, "max": 0.02, "step": 0.0002},
	{"id": "speed_cap", "name": "Top speed", "min": 0.6, "max": 5.0, "step": 0.1},

	{"group": "Praise"},
	{"id": "praise_cooldown", "name": "Cooldown, s", "min": 0.0, "max": 5.0, "step": 0.1},
	{"id": "praise_run_cap", "name": "Most per run", "min": 0, "max": 40, "step": 1},
	{"id": "praise_combo_base", "name": "Chain to praise", "min": 1, "max": 8, "step": 1},
	{"id": "praise_combo_step", "name": "Bar rises every", "min": 5, "max": 80, "step": 5},

	{"group": "Continue"},
	{"id": "continue_record_ratio", "name": "Near record from", "min": 0.0, "max": 1.0, "step": 0.05},
	{"id": "continue_min_distance", "name": "Min distance", "min": 0, "max": 60, "step": 1},
	{"id": "continue_cooldown", "name": "Cooldown, s", "min": 0.0, "max": 600.0, "step": 10.0},
	{"id": "continue_fuel_ratio", "name": "Fuel restored", "min": 0.1, "max": 1.0, "step": 0.05},
]

const PAD := 22

var _balance: GameBalance
## Value labels by knob id, so a slider can repaint its own row.
var _readouts: Dictionary = {}
## Standard of play for the bot buttons. Not part of the balance sheet — it
## belongs to the bot, so it lives here.
var _bot_level: float = Autoplayer.EXPERT_LEVEL


func setup(balance: GameBalance) -> void:
	_balance = balance
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 12)
	page.offset_left = PAD
	page.offset_right = -PAD
	var insets := SafeArea.insets(get_viewport().get_visible_rect().size)
	page.offset_top = insets.x + PAD
	page.offset_bottom = -(insets.w + PAD)
	add_child(page)

	var head := HBoxContainer.new()
	page.add_child(head)

	var title := Label.new()
	title.text = "DEBUG"
	title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(64, 64)
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)

	_add_actions(rows)
	for knob: Dictionary in KNOBS:
		if knob.has("group"):
			_add_heading(rows, String(knob["group"]))
		else:
			_add_knob(rows, knob)


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	parent.add_child(pad)
	parent.add_child(label)


func _add_actions(parent: Control) -> void:
	_add_heading(parent, "Run")
	for spec in [
		{"text": "Play as bot", "call": func() -> void: autoplay_requested.emit(_bot_level)},
		{"text": "Grant all upgrades", "call": func() -> void: unlock_requested.emit()},
		{"text": "Reset progress", "call": func() -> void: reset_requested.emit()},
	]:
		var button := Button.new()
		button.text = String(spec["text"])
		button.custom_minimum_size = Vector2(0, 62)
		button.add_theme_font_size_override("font_size", 22)
		var action: Callable = spec["call"]
		button.pressed.connect(func() -> void:
			visible = false
			action.call())
		parent.add_child(button)


func _add_knob(parent: Control, knob: Dictionary) -> void:
	var id: String = String(knob["id"])
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var head := HBoxContainer.new()
	row.add_child(head)

	var name_label := Label.new()
	name_label.text = String(knob["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 19)
	head.add_child(name_label)

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 19)
	value_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.75))
	head.add_child(value_label)
	_readouts[id] = value_label

	var slider := HSlider.new()
	slider.min_value = float(knob["min"])
	slider.max_value = float(knob["max"])
	slider.step = float(knob["step"])
	slider.value = _read(id)
	slider.custom_minimum_size = Vector2(0, 40)
	slider.value_changed.connect(_write.bind(id, knob))
	row.add_child(slider)

	_show(id, knob, slider.value)


func _read(id: String) -> float:
	if id == "bot_level":
		return _bot_level
	if _balance == null:
		return 0.0
	return float(_balance.get(id))


func _write(value: float, id: String, knob: Dictionary) -> void:
	if id == "bot_level":
		_bot_level = value
	elif _balance != null:
		# Ints have to go back as ints or the resource quietly keeps a float
		# and comparisons against them start behaving oddly.
		if float(knob["step"]) >= 1.0 and typeof(_balance.get(id)) == TYPE_INT:
			_balance.set(id, int(round(value)))
		else:
			_balance.set(id, value)
	_show(id, knob, value)


func _show(id: String, knob: Dictionary, value: float) -> void:
	var label: Label = _readouts.get(id)
	if label == null:
		return
	var step: float = float(knob["step"])
	if step >= 1.0:
		label.text = str(int(round(value)))
	elif step >= 0.01:
		label.text = "%.2f" % value
	else:
		label.text = "%.4f" % value
