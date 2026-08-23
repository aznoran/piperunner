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
signal autoplay_requested(level: float, persona: Persona)
## Debug conveniences that used to live in Settings.
signal unlock_requested
signal reset_requested

## One row per number. `step` also decides how it is displayed: whole numbers
## for whole steps, two decimals otherwise.
const KNOBS := [
	{"group": "Bot"},
	{"id": "bot_level", "name": "Proficiency", "min": 0.0, "max": 1.0, "step": 0.05},

	{"group": "Strip"},
	{"id": "offer_size", "name": "Shapes on offer", "min": 1, "max": 7, "step": 1},

	{"group": "Dealer"},
	{"id": "turn_relief", "name": "Turn relief", "min": 0.0, "max": 1.0, "step": 0.05},
	{"id": "assist_max_new", "name": "Assist: new player", "min": 0.0, "max": 1.0, "step": 0.05},
	{"id": "assist_max_early", "name": "Assist: early", "min": 0.0, "max": 1.0, "step": 0.05},
	{"id": "assist_max_veteran", "name": "Assist: veteran", "min": 0.0, "max": 1.0, "step": 0.05},
	{"id": "assist_slump_bonus", "name": "Assist: slump bonus", "min": 0.0, "max": 0.6, "step": 0.05},
	{"id": "assist_fit_gain", "name": "Fitting shape weight", "min": 1.0, "max": 8.0, "step": 0.25},
	{"id": "assist_miss_penalty", "name": "Wrong shape weight", "min": 0.1, "max": 1.0, "step": 0.05},
	{"id": "assist_fuel_floor", "name": "Pressure: fuel below", "min": 0.0, "max": 0.8, "step": 0.05},
	{"id": "assist_buffer_floor", "name": "Pressure: track below", "min": 0, "max": 8, "step": 1},

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
## The A/B/C buttons, kept so picking one can clear the other two.
var _variant_buttons: Array[Button] = []
## Sliders and the values they started at, so a knob can be put back without
## reloading the balance sheet and losing every other change with it.
var _sliders: Dictionary = {}
## The archetype the bot plays as, and the buttons that pick it.
var _persona: Persona = Persona.by_name("Optimiser")
var _persona_buttons: Array[Button] = []
var _playlog_label: Label
var _defaults: Dictionary = {}
var _assignment: Label


func setup(balance: GameBalance) -> void:
	_balance = balance
	_build()


func _build() -> void:
	# Sized outright rather than by anchors: this Control's parent is a
	# CanvasLayer, not another Control, so there is no rect for anchors to
	# resolve against and the panel would sit at zero by zero — drawing its
	# title and close button over the menu and nothing else.
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_fit)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.06, 1.0)
	add_child(dim)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", 12)
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

	_add_variants(rows)
	_add_personas(rows)
	_add_actions(rows)
	_add_playlog(rows)
	_fit()
	for knob: Dictionary in KNOBS:
		if knob.has("group"):
			_add_heading(rows, String(knob["group"]))
		else:
			_add_knob(rows, knob)


## Fills the screen, inside the safe area. Called once the panel is built and
## again whenever the viewport changes — rotating a phone, or the editor window
## being dragged.
func _fit() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport().get_visible_rect().size
	position = Vector2.ZERO
	size = viewport

	var dim: ColorRect = get_node_or_null("Dim")
	if dim != null:
		dim.position = Vector2.ZERO
		dim.size = viewport

	var page: Control = get_node_or_null("Page")
	if page == null:
		return
	var insets := SafeArea.insets(viewport)
	page.position = Vector2(PAD, insets.y + PAD)
	page.size = Vector2(
		maxf(viewport.x - PAD * 2.0, 1.0),
		maxf(viewport.y - insets.y - insets.w - PAD * 2.0, 1.0))


func _add_heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	parent.add_child(pad)
	parent.add_child(label)


## The A/B/C switcher.
##
## Forcing a variant here is for looking at the other two, not for joining
## their groups: it does not touch the group on disk, and everything it
## produces is stamped `debug_override` so the experiment's numbers stay clean.
## Switching only takes effect between runs, for the same reason.
func _add_variants(parent: Control) -> void:
	_add_heading(parent, "Gameplay variant")

	var caption := Label.new()
	caption.text = "B offer of 3 · C offer of 3, untaken windows held"
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	for index in BlockSource.NAMES.size():
		var button := Button.new()
		button.text = String(BlockSource.NAMES[index])
		button.custom_minimum_size = Vector2(0, 62)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 24)
		button.toggle_mode = true
		button.button_pressed = index == Experiment.variant
		button.pressed.connect(_pick_variant.bind(index))
		_variant_buttons.append(button)
		row.add_child(button)

	_assignment = Label.new()
	_assignment.add_theme_font_size_override("font_size", 15)
	_assignment.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_assignment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_assignment)
	_show_assignment()


func _pick_variant(index: int) -> void:
	Experiment.override(index)
	for i in _variant_buttons.size():
		_variant_buttons[i].button_pressed = i == index
	_show_assignment()


func _show_assignment() -> void:
	if _assignment == null:
		return
	# The switch is the thing worth reading first: C is built but not served,
	# and a tester who does not know that will report the wrong bug.
	var gate := "C is open" if Experiment.held_windows_enabled \
		else "C is switched off — players all get B"
	var source := "Remote Config" if Experiment.assigned else "fallback"
	var forced := " · forced from here" if Experiment.debug_override else ""
	_assignment.text = "%s. Group %s from %s%s" \
		% [gate, Experiment.name_of(), source, forced]


## The archetype the bot plays as. Style rather than strength: the proficiency
## slider below still sets how well it plays, and a persona sets what it plays
## for. See Persona.
func _add_personas(parent: Control) -> void:
	_add_heading(parent, "Bot persona")

	var caption := Label.new()
	caption.text = "Dabbler casual · Rusher height · Scavenger fuel · Hoarder keeps windows · Optimiser balanced"
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	for candidate in Persona.catalogue():
		var button := Button.new()
		button.text = candidate.name.substr(0, 4)
		button.tooltip_text = candidate.name
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 16)
		button.toggle_mode = true
		button.button_pressed = candidate.name == _persona.name
		button.pressed.connect(_pick_persona.bind(candidate))
		_persona_buttons.append(button)
		row.add_child(button)


func _pick_persona(chosen: Persona) -> void:
	_persona = chosen
	_bot_level = chosen.proficiency
	var slider: TuningSlider = _sliders.get("bot_level")
	if slider != null:
		slider.set_value_silently(chosen.proficiency)
		_show("bot_level", {"step": 0.05}, chosen.proficiency)
	for i in _persona_buttons.size():
		_persona_buttons[i].button_pressed = \
			_persona_buttons[i].tooltip_text == chosen.name


## What the behaviour store is holding, and the two things worth doing to it.
## Shown as a count rather than left invisible: a store nobody can see the size
## of is a store nobody trusts.
func _add_playlog(parent: Control) -> void:
	_add_heading(parent, "Behaviour log")

	_playlog_label = Label.new()
	_playlog_label.add_theme_font_size_override("font_size", 15)
	_playlog_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_playlog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_playlog_label)
	_show_playlog()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	for spec in [
		{"text": "Export", "call": func() -> void:
			var path: String = PlayLog.export_all()
			_playlog_label.text = "Written to %s" % path},
		{"text": "Clear", "call": func() -> void:
			PlayLog.clear()
			_show_playlog()},
	]:
		var button := Button.new()
		button.text = String(spec["text"])
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 18)
		var action: Callable = spec["call"]
		button.pressed.connect(func() -> void: action.call())
		row.add_child(button)


func _show_playlog() -> void:
	if _playlog_label == null:
		return
	var held := PlayLog.stats()
	_playlog_label.text = "%d runs, %d KB on this device. Nothing is sent anywhere." \
		% [int(held["runs"]), int(held["bytes"]) / 1024]


func _add_actions(parent: Control) -> void:
	_add_heading(parent, "Run")
	for spec in [
		{"text": "Play as bot", "call": func() -> void:
			autoplay_requested.emit(_bot_level, _persona)},
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

	# Slider and its reset key share a line, so the key is always in reach of
	# the thumb that just moved the thing it undoes.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)

	var start := _read(id)
	# The pristine value, taken before anything on this panel can touch it.
	# Read from the live sheet rather than reloading the resource, because the
	# sheet is what a reset has to put back.
	_defaults[id] = start

	var slider := TuningSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.setup(float(knob["min"]), float(knob["max"]),
		float(knob["step"]), start)
	slider.value_changed.connect(_write.bind(id, knob))
	line.add_child(slider)
	_sliders[id] = slider

	var reset := Button.new()
	reset.text = "⟲"
	reset.tooltip_text = "Back to default"
	reset.custom_minimum_size = Vector2(46, 40)
	reset.add_theme_font_size_override("font_size", 20)
	reset.pressed.connect(_reset_knob.bind(id, knob))
	line.add_child(reset)

	_show(id, knob, start)


## Puts one knob back where it started, leaving the rest of the panel alone.
func _reset_knob(id: String, knob: Dictionary) -> void:
	if not _defaults.has(id):
		return
	var original: float = float(_defaults[id])
	var slider: TuningSlider = _sliders.get(id)
	if slider != null:
		slider.set_value_silently(original)
	_write(original, id, knob)


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
