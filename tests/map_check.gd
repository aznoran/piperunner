## Checks the story map can be dragged, and that dragging it does not open a
## level by accident.
##
## Both halves have been wrong at least once. The map first shipped with
## MOUSE_FILTER_STOP, which ate the gesture so the panel could not be moved at
## all; and a station that opened on the press rather than the release would
## fire every time somebody scrolled past it. Neither is visible in a
## screenshot, so both are asserted here.
##
##   godot --headless --path . --script res://tests/map_check.gd
extends SceneTree

var main: Node
var frames := 0
var checks := 0
var failures := 0
var scroll: ScrollContainer
var map: StoryMap
var picked: int = 0
var started_at: int = 0


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"],
			["Analytics", "res://scripts/analytics.gd"],
			["Experiment", "res://scripts/experiment.gd"],
			["PlayLog", "res://scripts/play_log.gd"]]:
		if not root.has_node(entry[0]):
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _touch(at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.pressed = pressed
	event.position = at
	# in_local_coords: the rects are in viewport space, and the window is not
	# the viewport once the stretch mode has had its say.
	root.push_input(event, true)


func _drag(from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = to
	event.relative = to - from
	root.push_input(event, true)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 20:
		return false

	if map == null:
		var menu: CanvasLayer = main.get_node("MainMenu")
		root.get_node("GameState").levels_cleared = 4
		menu._build_levels()
		menu.get_node("LevelsPanel").visible = true
		scroll = menu.get_node("LevelsPanel/Scroll")
		map = scroll.get_node("Map")
		map.station_picked.connect(func(number: int) -> void: picked = number)
		return false

	if started_at == 0:
		_check(map.mouse_filter == Control.MOUSE_FILTER_STOP,
			"the map owns the gesture rather than hoping the scroll takes it")
		_check(map.custom_minimum_size.y > scroll.size.y,
			"the line is longer than the panel, so there is something to drag")
		started_at = scroll.scroll_vertical
		return false

	# A drag straight up the middle of the panel, well clear of any station.
	var top := scroll.global_position + Vector2(scroll.size.x * 0.5,
		scroll.size.y * 0.7)
	_touch(top, true)
	for i in range(1, 7):
		_drag(top - Vector2(0, float(i - 1) * 30.0), top - Vector2(0, float(i) * 30.0))
	_touch(top - Vector2(0, 180.0), false)

	_check(scroll.scroll_vertical != started_at,
		"dragging moves the panel, was %d now %d"
			% [started_at, scroll.scroll_vertical])
	_check(picked == 0,
		"dragging past a station does not open it, opened %d" % picked)

	print("--- %d checks, %d failed ---" % [checks, failures])
	return true
