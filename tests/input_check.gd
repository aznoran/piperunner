## Clicks the menu buttons with real input events, to catch the case where a
## button draws fine but nothing can reach it.
##
##   godot --path . --resolution 450x800 --script res://tests/input_check.gd
extends SceneTree

var main: Node
var menu: Node
var frames: int = 0
var step: int = 0
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_stand_up_autoloads()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 4:
		return false
	if menu == null:
		menu = main._menu

	# One action every few frames, so the UI settles between them. The gap has
	# to outlast the longest transition — the curtain out and back in — or a
	# click lands while the menu is still behind it.
	if frames % 22 != 0:
		return false
	step += 1

	match step:
		1:
			_click(menu.get_node("%UpgradesButton"))
		2:
			_ok(menu.get_node("%UpgradesPanel").visible, "UPGRADES opens the shop")
			_click(menu.get_node("%CloseUpgrades"))
		3:
			_ok(not menu.get_node("%UpgradesPanel").visible, "Close shuts the shop")
			_click(menu.get_node("%SettingsButton"))
		4:
			_ok(menu.get_node("%SettingsPanel").visible, "SETTINGS opens settings")
			_click(menu.get_node("%CloseSettings"))
		5:
			_click(menu.get_node("%ModesButton"))
		6:
			_ok(menu.get_node("%ModesPanel").visible, "MODES opens the carousel")
			# Second card is today's map.
			var cards: Node = menu.get_node("%Cards")
			_ok(cards.get_child_count() == 2, "both modes are offered")
			_click(cards.get_child(1))
		7:
			_ok(not menu.get_node("%ModesPanel").visible,
				"picking a mode drops back to the menu")
			_ok(main.selected_daily, "and today's map is the one selected")
			_click(menu.get_node("%StartButton"))
		8:
			_ok(main.state == 1, "the run key launches the chosen mode")
			_ok(main.daily_mode, "...as the daily")
			_eq(main._board.rng.seed, root.get_node("GameState").daily_seed(),
				"...seeded from today's date")
			main._show_menu()
			menu.get_node("%ModesButton").pressed.emit()
		9:
			_click(menu.get_node("%Cards").get_child(0))
		10:
			_ok(not main.selected_daily, "classic can be chosen back")
		11:
			_click(menu.get_node("%StartButton"))
		12:
			_ok(main.state == 1, "START starts a run")
			_ok(not main.daily_mode, "...and it is a normal one")
			# Back out again, then check the menu still takes input — a layer
			# left over from the run would swallow every tap silently.
			_click(main._hud.get_node("%BackButton"))
		13:
			_ok(main.state == 0, "the back key returns to the menu")
		14:
			_click(menu.get_node("%UpgradesButton"))
		15:
			_ok(menu.get_node("%UpgradesPanel").visible,
				"menu buttons still respond after returning from a run")
			_click(menu.get_node("%CloseUpgrades"))
		16:
			_click(menu.get_node("%StartButton"))
		17:
			_ok(main.state == 1, "and a run can be started again")
			# Play it out: commit a pipe, crash, then leave through the
			# game-over card — the path a real player takes every run.
			main._try_place(Vector2i(3, 4))
			main._die("Derailed")
		18:
			main._death_pause = 0.0
			main._overlay.show_game_over("Derailed", 12, 4, false, false)
		19:
			_click(main._overlay.get_node("%MenuButton"))
		20:
			_ok(main.state == 0, "the game-over card returns to the menu")
		21:
			_click(menu.get_node("%SettingsButton"))
		22:
			_ok(menu.get_node("%SettingsPanel").visible,
				"the menu still responds after a finished run")
			_click(menu.get_node("%CloseSettings"))
		23:
			# Second lap, entirely through real clicks: retry from the card,
			# crash again, then back to the menu.
			_click(menu.get_node("%StartButton"))
		24:
			main._try_place(Vector2i(3, 4))
			main._die("Derailed")
		25:
			main._death_pause = 0.0
			main._overlay.show_game_over("Derailed", 7, 3, false, false)
		26:
			_click(main._overlay.get_node("%RetryButton"))
		27:
			_ok(main.state == 1, "retry starts another run")
			main._try_place(Vector2i(3, 4))
			main._die("Derailed")
		28:
			main._death_pause = 0.0
			main._overlay.show_game_over("Derailed", 9, 3, false, false)
		29:
			_click(main._overlay.get_node("%MenuButton"))
		30:
			_click(menu.get_node("%UpgradesButton"))
		31:
			_ok(menu.get_node("%UpgradesPanel").visible,
				"the menu still responds after two runs and a retry")
			print("--- %d checks, %d failed ---" % [checks, failures])
			quit(1 if failures > 0 else 0)
			return true
	return false


## Presses and releases in the middle of `control`, through the viewport, so
## the hit test is the real one. Touch events, since the project emulates touch
## from mouse — this is what a finger actually delivers.
func _click(control: Control) -> void:
	var centre := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.pressed = pressed
		event.position = centre
		# in_local_coords: the rect is in viewport space, and the window is
		# a different size because of the canvas_items stretch.
		root.push_input(event, true)


func _ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: %s" % label)


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		print("FAIL: %s — got %s, expected %s" % [label, actual, expected])


## --script skips project autoloads, so stand them up by hand.
func _stand_up_autoloads() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"]]:
		if root.has_node(entry[0]):
			continue
		var node: Node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
