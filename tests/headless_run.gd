## Headless smoke test: drives several full runs with a greedy bot and reports
## what happened. Not a balance measurement — the bot only extends the track in
## front of it and cannot plan a route, exactly the limitation the spec warns
## about in section 10.
##
##   godot --headless --path . --script res://tests/headless_run.gd
extends SceneTree

const RUNS := 5
const MAX_FRAMES_PER_RUN := 20000
## Bot acts at most this often, so it cannot carpet the board in one second.
const ACT_INTERVAL := 8

var main: Node
var run_index: int = 0
var frames: int = 0
var placed: int = 0
var dumped: int = 0
var holds: int = 0
var cooldown: int = 0
var deaths: Dictionary = {}


func _initialize() -> void:
	# --script skips project autoloads, so stand GameState up by hand.
	if not root.has_node("GameState"):
		var state: Node = load("res://scripts/game_state.gd").new()
		state.name = "GameState"
		root.add_child(state)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_begin_run()
		return false
	if frames < 3:
		return false

	if main.state == 2:  # DEAD
		_report()
		run_index += 1
		if run_index >= RUNS:
			_summary()
			return true
		_begin_run()
		return false

	if frames > MAX_FRAMES_PER_RUN:
		print("!! run %d survived %d frames" % [run_index + 1, MAX_FRAMES_PER_RUN])
		_report()
		return true

	if cooldown > 0:
		cooldown -= 1
	else:
		_bot_step()
	return false


func _begin_run() -> void:
	frames = 4
	placed = 0
	dumped = 0
	holds = 0
	cooldown = 0
	main.start_run()


func _bot_step() -> void:
	var board: Board = main._board
	var queue: PipeQueue = main._queue
	var cart: Cart = main._cart

	var ahead := board.frontier(cart.cell(), cart.entry)
	if ahead.is_empty():
		return

	var joint: Vector2i = ahead["cell"]
	var need: int = ahead["need"]

	if (not ahead["blocked"]
			and PipeDefs.SIDES[queue.current()].has(need)
			and board.can_place(joint)):
		main._try_place(joint)
		placed += 1
		cooldown = ACT_INTERVAL
		return

	# The piece does not fit the joint. Pocket it if HOLD is free, otherwise
	# dump it strictly behind the cart — never on the joint it still needs.
	if queue.held == PipeQueue.NONE:
		main._on_hold_tapped()
		holds += 1
		cooldown = ACT_INTERVAL
		return

	for row in range(board.max_row - main.balance.place_below, cart.row):
		for col in main.balance.cols:
			var spot := Vector2i(col, row)
			if spot == joint:
				continue
			if board.get_pipe(spot) == null and board.can_place(spot):
				main._try_place(spot)
				dumped += 1
				cooldown = ACT_INTERVAL
				return


func _report() -> void:
	var board: Board = main._board
	var reason: String = main._death_reason
	deaths[reason] = int(deaths.get(reason, 0)) + 1
	print("run %d | %-13s score %4d | cells %4d | row %4d | crystals %2d"
		% [run_index + 1, reason, main.score, main.cells_run, board.max_row,
			main.crystals_collected]
		+ " | fuel %5.1f | speed %.2f | placed %3d (+%3d dumped, %2d holds)"
			% [main.fuel, main.speed, placed, dumped, holds]
		+ " | pipes %4d rocks %3d" % [board.pipes.size(), board.rocks.size()])


func _summary() -> void:
	print("--- %d runs ---" % RUNS)
	for reason: String in deaths:
		print("  %-13s x%d" % [reason, deaths[reason]])
	print("  best saved   : %d" % root.get_node("GameState").best)
