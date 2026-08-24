## Plays one variant, at one standard of play, many times, and reports how it
## went. The point is to compare mechanics rather than boards, so every variant
## is handed the same list of seeds and the same bot.
##
## Nobody is given upgrades: the shop is not part of what is being compared,
## and handing the planning bot a bigger tank would make its numbers
## incomparable with the casual one's.
##
##   VARIANT=0 SKILL=0.2 RUNS=8 godot --headless --path . \
##     --script res://tests/variant_bench.gd
extends SceneTree

## Fixed boards. Every variant and every skill sees this same list, so a
## difference in the numbers is a difference in the mechanic.
const SEEDS := [11, 202, 3003, 40004, 55, 606, 7007, 808,
	9009, 1212, 1313, 1414]
## Nothing should take this long. A run that does is stopped and counted at
## the distance it reached, so one lucky run cannot stall the sweep.
const RUN_LIMIT := 240.0

var main: Node
var experiment: Node
var variant := 0
var persona: Persona
var wanted := 6

var run := 0
var frames := 0
var elapsed := 0.0
var starting := true
var distances: Array[int] = []
var deaths: Array[String] = []


func _initialize() -> void:
	variant = int(OS.get_environment("VARIANT"))
	var who := OS.get_environment("PERSONA")
	persona = Persona.by_name(who if not who.is_empty() else "Optimiser")
	var skill := OS.get_environment("SKILL")
	if not skill.is_empty():
		# A bare skill overrides the persona's own, for sweeping competence
		# with the style held still.
		persona.proficiency = float(skill)
	var asked := int(OS.get_environment("RUNS"))
	wanted = clampi(asked if asked > 0 else 6, 1, SEEDS.size())

	for entry in [["GameState", "res://scripts/game_state.gd"],
			["Analytics", "res://scripts/analytics.gd"],
			["Experiment", "res://scripts/experiment.gd"]]:
		if not root.has_node(entry[0]):
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	experiment = root.get_node("Experiment")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _begin() -> void:
	main._show_menu()
	experiment.override(variant)
	# GATES=0 turns the speed gates off, so the sweep can measure what they are
	# actually worth rather than assuming it.
	if OS.get_environment("GATES") == "0":
		main.base_balance.checkpoints_on = false
	main.forced_seed = SEEDS[run]
	main.start_run(0)
	# Straight to the autoplayer rather than through _launch_autoplay, which
	# would equip the planning bot with a full shop and make the standards of
	# play incomparable.
	var grade: int = Autoplayer.Skill.EXPERT \
		if persona.proficiency >= Autoplayer.PLANS_FROM \
		else Autoplayer.Skill.SHOWCASE
	main._autoplayer.start(grade, 5000 + run, -1.0, persona)
	elapsed = 0.0


func _finish() -> void:
	distances.append(main.distance)
	deaths.append(main._death_reason if not main._death_reason.is_empty()
		else "Stopped")
	run += 1
	starting = true


func _process(delta: float) -> bool:
	frames += 1
	if frames < 12:
		return false
	if starting:
		if run >= wanted:
			_report()
			return true
		_begin()
		starting = false
		return false

	elapsed += delta
	if main.state == 2:  # DEAD
		_finish()
		return false
	if elapsed > RUN_LIMIT:
		_finish()
		return false
	return false


func _report() -> void:
	var sorted := distances.duplicate()
	sorted.sort()
	var total := 0
	for d in sorted:
		total += d
	var median: float = float(sorted[sorted.size() / 2]) if sorted.size() % 2 == 1 \
		else (float(sorted[sorted.size() / 2 - 1]) + float(sorted[sorted.size() / 2])) * 0.5

	var reasons := {}
	for r in deaths:
		reasons[r] = int(reasons.get(r, 0)) + 1

	print("RESULT variant=%s persona=%-9s n=%d mean=%.1f median=%.1f min=%d max=%d %s %s"
		% [BlockSource.NAMES[variant], persona.name, sorted.size(),
			float(total) / sorted.size(), median, sorted[0],
			sorted[sorted.size() - 1], str(sorted), str(reasons)])
