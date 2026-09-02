## Plays one dealing-rule group across a fixed list of boards and reports how
## it went. The mechanic is held still — every group plays variant B's offer —
## so a difference in the numbers is a difference in the dealing rule and
## nothing else.
##
## The groups sweep PathDealer's two knobs against each other, because the
## interesting question is not whether either helps but whether they overlap.
## Both aim at the same scarcity from different ends: the turn rule reshapes
## the draw the moment the cart is off its climb, the pity rule waits for the
## draw to fail and then insists. If they are redundant, D and E buy nothing
## over B and C.
##
##   GROUP=A godot --headless --path . --script res://tests/dealer_bench.gd
##
## PERSONA, SKILL and RUNS work as they do in variant_bench.
extends SceneTree

## Fixed boards. The first twelve are variant_bench's list, so numbers from the
## two sweeps line up; the rest are here for power. Twelve runs a group could
## not resolve anything smaller than about fifteen cells, which was the main
## thing the first sweep of these rules established.
const SEEDS := [11, 202, 3003, 40004, 55, 606, 7007, 808,
	9009, 1212, 1313, 1414, 1515, 1616, 1717, 1818, 1919, 2020,
	2121, 2222, 2323, 2424, 2525, 2626, 2727, 2828, 2929, 3030,
	3131, 3232]
## Nothing should take this long. A run that does is stopped and counted at the
## distance it reached, so one lucky run cannot stall the sweep.
const RUN_LIMIT := 240.0

## turn chance, pity strength.
##
## Zero is a true zero on both now. Under the first design a missed turn roll
## dealt out of the shapes that do *not* carry the path on, so 0.50 was the
## neutral setting and the floor; claiming one cell of an otherwise even draw
## removes that, and an untouched even draw is the honest control.
const GROUPS := {
	"A": [0.00, 0.00],  # control: both rules off
	"B": [0.90, 0.00],  # the turn rule alone, near its ceiling
	"C": [0.00, 1.20],  # the pity rule alone, biting after one barren deal
	"D": [0.60, 0.60],  # both, middling
	"E": [0.30, 0.25],  # both, gentle
}

var main: Node
var experiment: Node
var persona: Persona
var group := "A"
var wanted := 12

var run := 0
var frames := 0
var elapsed := 0.0
var starting := true
var distances: Array[int] = []
var deaths: Array[String] = []


func _initialize() -> void:
	var asked := OS.get_environment("GROUP").strip_edges().to_upper()
	group = asked if GROUPS.has(asked) else "A"

	var who := OS.get_environment("PERSONA")
	persona = Persona.by_name(who if not who.is_empty() else "Optimiser")
	var skill := OS.get_environment("SKILL")
	if not skill.is_empty():
		persona.proficiency = float(skill)
	var runs := int(OS.get_environment("RUNS"))
	wanted = clampi(runs if runs > 0 else SEEDS.size(), 1, SEEDS.size())

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
	# B is the mechanic PathDealer deals for. Held windows are a different
	# question and would confound this one.
	experiment.override(BlockSource.Variant.B)

	# Written to the baseline rather than to the run's copy, because Main
	# rebuilds that copy from the baseline as each run starts.
	var knobs: Array = GROUPS[group]
	main.base_balance.path_turn_chance = float(knobs[0])
	main.base_balance.path_pity_strength = float(knobs[1])

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
	var median: float = float(sorted[sorted.size() / 2]) \
		if sorted.size() % 2 == 1 \
		else (float(sorted[sorted.size() / 2 - 1])
			+ float(sorted[sorted.size() / 2])) * 0.5

	var reasons := {}
	for r in deaths:
		reasons[r] = int(reasons.get(r, 0)) + 1

	var knobs: Array = GROUPS[group]
	print("RESULT group=%s turn=%.2f pity=%.2f persona=%-9s n=%d mean=%.1f median=%.1f min=%d max=%d %s %s"
		% [group, float(knobs[0]), float(knobs[1]), persona.name, sorted.size(),
			float(total) / sorted.size(), median, sorted[0],
			sorted[sorted.size() - 1], str(sorted), str(reasons)])
