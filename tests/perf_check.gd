## Frame-cost check against the acceptance target: 60 FPS with 300+ pipes on
## the board (spec section 14).
##
## Wall-clock frame time on a desktop is pinned by vsync and says nothing about
## the budget, so this measures the two things that do transfer: how long our
## own per-frame logic takes, and how many draw calls a full board produces.
## The FPS number itself still has to be confirmed on a real Android handset.
##
##   godot --path . --resolution 720x1280 --script res://tests/perf_check.gd
extends SceneTree

const TARGET_PIPES := 400
const WARMUP := 30
const SAMPLES := 600
const STEP := 1.0 / 60.0
## Rough ceiling for a 2D mobile frame; well under it means headroom.
const DRAW_CALL_CEILING := 1000

var main: Node
var frames: int = 0
var draw_calls: int = 0
var logic_us: Array[float] = []


func _initialize() -> void:
	if not root.has_node("GameState"):
		var state: Node = load("res://scripts/game_state.gd").new()
		state.name = "GameState"
		root.add_child(state)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		_fill_board()
		main.set_process(false)  # tick the run loop by hand, and time it
		return false
	if frames < 3:
		return false

	_revive_if_needed()
	var started := Time.get_ticks_usec()
	main._run_frame(STEP)
	var elapsed := float(Time.get_ticks_usec() - started)

	if frames > WARMUP:
		logic_us.append(elapsed)
		draw_calls = maxi(draw_calls,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	if logic_us.size() < SAMPLES:
		return false

	_report()
	return true


## Carpets the placement window with pipes and sends the cart up through them.
func _fill_board() -> void:
	main.start_run()
	var board: Board = main._board
	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	var row: int = -main.balance.place_below
	while board.pipes.size() < TARGET_PIPES:
		for col in main.balance.cols:
			var cell := Vector2i(col, row)
			if board.pipes.has(cell):
				continue
			var pipe := Board.PipeCell.new(PipeDefs.random_type(rng))
			pipe.flooded = rng.randf() < 0.4
			board.pipes[cell] = pipe
		row += 1
		board.max_row = maxi(board.max_row, row)
		board.ensure_rows(row + 20)
	main.started = true


## The cart will derail on this random junk almost immediately; put it back so
## the measurement keeps running under load.
func _revive_if_needed() -> void:
	if main.state == 1 and main._cart.alive:
		return
	var board: Board = main._board
	var col: int = main.balance.cols / 2
	board.pipes[Vector2i(col, 0)] = Board.PipeCell.new(PipeDefs.Type.V)
	main.state = 1
	main._death_pause = 0.0
	main._cart.place_at(col, 0, PipeDefs.Side.D)
	main.fuel = main.balance.fuel_max


func _report() -> void:
	logic_us.sort()
	var sum := 0.0
	for value in logic_us:
		sum += value
	var average: float = sum / logic_us.size()
	var p95: float = logic_us[int(logic_us.size() * 0.95)]
	var board: Board = main._board

	print("pipes on board  : %d" % board.pipes.size())
	print("logic per frame : %.3f ms average, %.3f ms p95, %.3f ms worst"
		% [average / 1000.0, p95 / 1000.0, logic_us[-1] / 1000.0])
	print("share of budget : %.1f%% of 16.67 ms (p95)" % [p95 / 16670.0 * 100.0])
	print("draw calls peak : %d (ceiling %d)" % [draw_calls, DRAW_CALL_CEILING])
	var pass_logic: bool = p95 < 16670.0 * 0.25
	var pass_draw: bool = draw_calls < DRAW_CALL_CEILING
	print("verdict         : %s" % ("PASS" if pass_logic and pass_draw else "FAIL"))
	print("note            : confirm the actual frame rate on a real Android device")
