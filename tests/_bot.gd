extends SceneTree
var main: Node
var elapsed: float = 0.0
var started := false
var runs := 0
var results: Array[int] = []
var deaths: Array[String] = []
var _last_beat: int = 0
## Fixed boards: comparing two versions of the bot on different maps measures
## the dice, not the change.
const SEEDS := [11, 202, 3003, 40004, 55, 606]

func _initialize() -> void:
	Engine.time_scale = 1.0  # real time: speeding the world up outruns the lookahead
	for entry in [["GameState", "res://scripts/game_state.gd"]]:
		if not root.has_node(entry[0]):
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)

func _process(delta: float) -> bool:
	elapsed += delta
	if not started and elapsed > 0.5:
		main.forced_seed = SEEDS[0]
		main._start_expert_autoplay()
		main._autoplayer.start(1, 1000)
		started = true
		return false
	if not started:
		return false
	if int(elapsed) / 20 > _last_beat:
		_last_beat = int(elapsed) / 20
		print("    ... t=%ds distance=%d fuel=%.0f" % [int(elapsed), main.distance, main.fuel])
	if main.state == 2:
		results.append(main.distance)
		deaths.append(main._death_reason)
		print("  run %d: %d cells, %s, fuel %.0f, %s"
			% [runs + 1, main.distance, main._death_reason, main.fuel,
				str(main._autoplayer.tally)])
		runs += 1
		if runs >= SEEDS.size():
			var total := 0
			var reached := 0
			for r in results:
				total += r
				if r >= 100:
					reached += 1
			print("expert: %s  average %.1f  reached100 %d/%d"
				% [str(results), float(total) / results.size(), reached, results.size()])
			print("deaths: %s" % str(deaths))
			return true
		main.forced_seed = SEEDS[runs % SEEDS.size()]
		main._start_expert_autoplay()
		main._autoplayer.start(1, 1000 + runs)
	return elapsed > 2400.0
