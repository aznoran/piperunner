## Checks each variant's dealing rule does what its mechanic needs.
##
## The two rules answer different questions, so a shared test would only prove
## they both return shapes. What matters is that B insures the thing B can lose
## to, and C insures the thing C can lose to, and that both leave a comfortable
## player alone.
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

	# --- turn relief: pays for the move a turn costs -------------------
	#
	# A turn is two moves where a climb is one, and the first buys no height.
	# The relief evens that out at the moment it is owed — while the cart is
	# already sideways — and at no other time.
	var calm := _context(PipeDefs.Side.L, false)
	var relieved := 0
	for _i in DEALS:
		var offer := b.fill(rng, 3, calm)
		for type: int in offer:
			if PipeDefs.exit_side(type, PipeDefs.Side.L) == PipeDefs.Side.U:
				relieved += 1
				break
	var rate := float(relieved) / float(DEALS)
	# Left alone a sideways cart sees a way up in 43% of offers, against 71%
	# for one already climbing — a crossroads goes straight through and so
	# never rescues a turn. Relief at 0.5 puts the two on the same footing.
	_check(rate > 0.64, "a sideways cart is offered a way up, got %.0f%%" % (rate * 100.0))
	_check(rate < 0.80,
		"and only to parity, not beyond it, got %.0f%%" % (rate * 100.0))

	# Climbing straight on is untouched: the relief pays for a cost the climb
	# does not have.
	var climbing := 0
	for _i in DEALS:
		var offer := b.fill(rng, 3, _context(PipeDefs.Side.D, false))
		for type: int in offer:
			if PipeDefs.exit_side(type, PipeDefs.Side.D) == PipeDefs.Side.U:
				climbing += 1
				break
	var plain := float(climbing) / float(DEALS)
	_check(plain > 0.64 and plain < 0.80,
		"a climbing cart gets its own untouched odds, got %.0f%%"
			% (plain * 100.0))
	_check(absf(plain - rate) < 0.10,
		"and the two are now within a few points of each other: %.0f%% vs %.0f%%"
			% [plain * 100.0, rate * 100.0])

	print("--- %d checks, %d failed ---" % [checks, failures])
	quit()
