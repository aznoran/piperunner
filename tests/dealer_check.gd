## Checks each variant's dealing rule does what its mechanic needs.
##
## The three rules answer three different questions, so a shared test would
## only prove they all return shapes. What matters is that B insures the thing
## B can lose to, and C insures the thing C can lose to, and that both leave a
## comfortable player alone.
##
##   godot --headless --path . --script res://tests/dealer_check.gd
extends SceneTree

const DEALS := 400

var checks := 0
var failures := 0


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


## A run in trouble, or a run in comfort. Assistance is read off these.
func _context(need: int, desperate: bool, visible: Array = []) -> Dictionary:
	return {
		"need": need,
		"buffer": 0 if desperate else 9,
		"fuel": 4.0 if desperate else 100.0,
		"fuel_max": 100.0,
		"runs_played": 0 if desperate else 999,
		"in_slump": desperate,
		"horizon": 0,
		"visible": visible,
	}


func _serves(type: int, need: int) -> bool:
	return PipeDefs.SIDES[type].has(need)


func _initialize() -> void:
	var balance: GameBalance = load("res://resources/GameBalance.tres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260823

	var need: int = PipeDefs.Side.D

	# --- B: quality, not availability ---------------------------------
	var b := OfferDealer.new()
	b.setup(balance)

	var dead := 0
	var climbable := 0
	for _i in DEALS:
		var offer := b.fill(rng, 3, _context(need, true))
		var fits := false
		var climbs := false
		for type: int in offer:
			if _serves(type, need):
				fits = true
			if PipeDefs.exit_side(type, need) == PipeDefs.Side.U:
				climbs = true
		if not fits:
			dead += 1
		if climbs:
			climbable += 1
	_check(dead == 0, "B never deals a dead offer under pressure, got %d" % dead)
	_check(climbable > DEALS * 0.9,
		"B nearly always offers a way up under pressure, got %d/%d"
			% [climbable, DEALS])

	var calm_climb := 0
	for _i in DEALS:
		var offer := b.fill(rng, 3, _context(need, false))
		for type: int in offer:
			if PipeDefs.exit_side(type, need) == PipeDefs.Side.U:
				calm_climb += 1
				break
	# Left alone, a way up turns up on its own about three-quarters of the
	# time. Well clear of the assisted rate, which is the point.
	_check(calm_climb < DEALS * 0.88,
		"B leaves a comfortable player to it, got %d/%d" % [calm_climb, DEALS])

	# --- C: the strip, not the deal -----------------------------------
	var c := HeldOfferDealer.new()
	c.setup(balance)

	# A strip that cannot take the cart at all: both held windows are misfits
	# and only the refill can save it.
	var stuck: Array = [PipeDefs.Type.H, PipeDefs.Type.UR]  # neither takes D
	var rescued := 0
	for _i in DEALS:
		var ranked := c.fill(rng, 3, _context(need, true, stuck))
		if _serves(ranked[0], need):
			rescued += 1
	_check(rescued > DEALS * 0.95,
		"C refills a stuck strip with a way out, got %d/%d" % [rescued, DEALS])

	# A strip that already takes the cart but is narrow: two shapes covering
	# the same pair of sides. The refill should widen it rather than repeat it.
	var narrow: Array = [PipeDefs.Type.V, PipeDefs.Type.V]  # covers U and D
	var widened := 0
	for _i in DEALS:
		var ranked := c.fill(rng, 3, _context(need, true, narrow))
		var adds := false
		for side: int in PipeDefs.SIDES[ranked[0]]:
			if side == PipeDefs.Side.L or side == PipeDefs.Side.R:
				adds = true
		if adds:
			widened += 1
	_check(widened > DEALS * 0.9,
		"C widens a narrow strip, got %d/%d" % [widened, DEALS])

	var calm_widen := 0
	for _i in DEALS:
		var ranked := c.fill(rng, 3, _context(need, false, narrow))
		for side: int in PipeDefs.SIDES[ranked[0]]:
			if side == PipeDefs.Side.L or side == PipeDefs.Side.R:
				calm_widen += 1
				break
	_check(calm_widen < DEALS * 0.92,
		"C leaves a comfortable player's strip alone, got %d/%d"
			% [calm_widen, DEALS])

	# --- A: still the weighted roll -----------------------------------
	var a := AssistDealer.new()
	a.setup(balance)
	var a_fits := 0
	for _i in DEALS:
		var dealt := a.fill(rng, 1, _context(need, true))
		if _serves(dealt[0], need):
			a_fits += 1
	_check(a_fits > DEALS * 0.7,
		"A leans hard toward a fitting piece under pressure, got %d/%d"
			% [a_fits, DEALS])

	print("--- %d checks, %d failed ---" % [checks, failures])
	quit()
