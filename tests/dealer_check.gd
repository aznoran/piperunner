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

	_check_path(balance, rng)

	print("--- %d checks, %d failed ---" % [checks, failures])
	quit()


## Whether this shape takes the cart on from `need` without pointing it down.
func _carries(type: int, need: int) -> bool:
	var exit: int = PipeDefs.exit_side(type, need)
	return exit != PipeDefs.NO_EXIT and exit != PipeDefs.Side.D


## What the pity rule holds out for: a shape that keeps the cart climbing, or
## anything that carries on where no shape can climb.
func _sought(need: int) -> Array[int]:
	var climbing: Array[int] = []
	var carrying: Array[int] = []
	for type: int in PipeDefs.ALL:
		if PipeDefs.exit_side(type, need) == PipeDefs.Side.U:
			climbing.append(type)
		if _carries(type, need):
			carrying.append(type)
	return climbing if not climbing.is_empty() else carrying


## Deals `DEALS` offers and reports [share that held one of `shapes`, longest
## run of offers in a row that did not].
func _profile(dealer: PathDealer, rng: RandomNumberGenerator, need: int,
		shapes: Array[int]) -> Array:
	var held := 0
	var streak := 0
	var worst := 0
	for _i in DEALS:
		var offer := dealer.fill(rng, 3, _context(need, false))
		var found := false
		for type: int in offer:
			if shapes.has(type):
				found = true
				break
		if found:
			held += 1
			streak = 0
		else:
			streak += 1
			worst = maxi(worst, streak)
	return [float(held) / float(DEALS), worst]


## Shapes that carry the path on from `need`, for the turn rule's half.
func _carrying(need: int) -> Array[int]:
	var out: Array[int] = []
	for type: int in PipeDefs.ALL:
		if _carries(type, need):
			out.append(type)
	return out


## A PathDealer tuned to one set of knobs, on its own copy of the sheet.
func _tuned(sheet: GameBalance, turn: float, share: float,
		pity: float) -> PathDealer:
	var balance: GameBalance = sheet.duplicate()
	balance.path_turn_chance = turn
	balance.path_straight_share = share
	balance.path_pity_strength = pity
	var dealer := PathDealer.new()
	dealer.setup(balance)
	return dealer


## PathDealer: each rule claims at most one cell of an otherwise even draw.
## Both are measured on a comfortable run, so what moves is the rule under test
## rather than the assistance underneath it.
func _check_path(sheet: GameBalance, rng: RandomNumberGenerator) -> void:
	var sideways := PipeDefs.Side.L
	var carrying := _carrying(sideways)

	# Whatever the knobs say, an offer is still three different shapes.
	var sound := true
	for _i in DEALS:
		var offer := _tuned(sheet, 1.0, 0.7, 1.2).fill(rng, 3, _context(sideways, false))
		if offer.size() != 3 or offer[0] == offer[1] or offer[1] == offer[2] \
				or offer[0] == offer[2]:
			sound = false
	_check(sound, "every offer is three distinct shapes whatever the knobs say")

	# Zero is off: the plain even draw, which misses the carrying shapes
	# C(4,3)/C(7,3) = 11% of the time.
	var off_turn: Array = _profile(_tuned(sheet, 0.0, 0.7, 0.0), rng, sideways, carrying)
	_check(float(off_turn[0]) > 0.84 and float(off_turn[0]) < 0.93,
		"zero leaves the even draw alone (89%%), got %.0f%%"
			% (float(off_turn[0]) * 100.0))

	# Wide open, one cell is always claimed, so a way on is always there.
	var wide: Array = _profile(_tuned(sheet, 1.0, 0.7, 0.0), rng, sideways, carrying)
	_check(float(wide[0]) == 1.0,
		"at 1.0 a sideways cart always has a way on, got %.1f%%"
			% (float(wide[0]) * 100.0))

	# ...and the other two cells stay an honest draw. This is the whole point
	# of claiming one cell: the first design chose every cell from the pool,
	# and since that pool is exactly three shapes for a sideways cart, a high
	# chance dealt the identical strip every single turn.
	var seen := {}
	var varied := _tuned(sheet, 1.0, 0.7, 0.0)
	for _i in DEALS:
		var offer := varied.fill(rng, 3, _context(sideways, false))
		var key := offer.duplicate()
		key.sort()
		seen[str(key)] = true
	_check(seen.size() > 10,
		"and the strip does not collapse to one fixed set: %d different offers"
			% seen.size())

	# The share, measured on the draw itself rather than through an offer,
	# where the even draw underneath would blur it.
	var shared := _tuned(sheet, 1.0, 0.7, 0.0)
	var empty: Array[int] = []
	var restoring := 0
	for _i in DEALS:
		var picked: int = shared._draw_from(rng, carrying, empty, [], sideways)
		if PipeDefs.exit_side(picked, sideways) == PipeDefs.Side.U:
			restoring += 1
	var share := float(restoring) / float(DEALS)
	_check(share > 0.63 and share < 0.77,
		"70%% of a carrying draw resumes the climb, got %.0f%%" % (share * 100.0))

	var levelled := _tuned(sheet, 1.0, 0.34, 0.0)
	var third := 0
	for _i in DEALS:
		var picked: int = levelled._draw_from(rng, carrying, empty, [], sideways)
		if PipeDefs.exit_side(picked, sideways) == PipeDefs.Side.U:
			third += 1
	_check(absf(float(third) / float(DEALS) - 0.34) < 0.07,
		"and the share is a knob, not a constant: %.0f%% at 0.34"
			% (float(third) / float(DEALS) * 100.0))

	# A climbing cart is left alone: nothing that fits from below points down,
	# so there is no split to weight and the draw stays even.
	var climb := PipeDefs.Side.D
	var fits := 0
	var wide_climb := _tuned(sheet, 1.0, 0.7, 0.0)
	for _i in DEALS:
		for type: int in wide_climb.fill(rng, 3, _context(climb, false)):
			if _serves(type, climb):
				fits += 1
	var per_offer := float(fits) / float(DEALS)
	_check(per_offer > 1.4 and per_offer < 2.0,
		"a climbing cart still gets an even draw, %.2f fitting shapes an offer"
			% per_offer)

	# --- the pity rule ---------------------------------------------------
	#
	# Measured on what it actually holds out for. After a turn that is one
	# shape in seven, so an even draw misses it C(6,3)/C(7,3) = 57% of the
	# time and streaks form readily.
	var sought := _sought(sideways)
	var off: Array = _profile(_tuned(sheet, 0.0, 0.7, 0.0), rng, sideways, sought)
	var low: Array = _profile(_tuned(sheet, 0.0, 0.7, 0.25), rng, sideways, sought)
	var high: Array = _profile(_tuned(sheet, 0.0, 0.7, 1.2), rng, sideways, sought)

	_check(float(off[0]) < 0.55,
		"without it the climb-restoring shape is genuinely scarce, %.0f%% of offers"
			% (float(off[0]) * 100.0))
	_check(float(high[0]) > float(off[0]) + 0.15,
		"the pity rule lifts that: %.0f%% -> %.0f%%"
			% [float(off[0]) * 100.0, float(high[0]) * 100.0])
	_check(int(high[1]) < int(off[1]),
		"shortening the worst run of offers without one: %d -> %d"
			% [int(off[1]), int(high[1])])
	_check(float(low[0]) >= float(off[0]) - 0.02
			and float(high[0]) >= float(low[0]) - 0.02,
		"and more of it never helps less: %.0f%% / %.0f%% / %.0f%%"
			% [float(off[0]) * 100.0, float(low[0]) * 100.0, float(high[0]) * 100.0])

	# It works with no turn in sight, which is the half the turn rule cannot
	# reach: climbing on, two shapes keep the climb and an even draw misses
	# both 29% of the time.
	var climb_off: Array = _profile(_tuned(sheet, 0.0, 0.7, 0.0), rng, climb, _sought(climb))
	var climb_on: Array = _profile(_tuned(sheet, 0.0, 0.7, 1.2), rng, climb, _sought(climb))
	# The lift is modest here and has to be: the rule rescues from the *second*
	# barren deal on, and climbing on, an even draw is barren only 29% of the
	# time, so two running is about 8% of deals. The shortened worst streak is
	# the sturdier half of this check.
	_check(float(climb_on[0]) > float(climb_off[0]),
		"and it works with no turn in sight: %.0f%% -> %.0f%%"
			% [float(climb_off[0]) * 100.0, float(climb_on[0]) * 100.0])
	_check(int(climb_on[1]) < int(climb_off[1]),
		"cutting the worst climbing streak too: %d -> %d"
			% [int(climb_off[1]), int(climb_on[1])])

	# A deal with no joint to serve cannot be judged, so it must not be counted
	# against the player either.
	var blind := _tuned(sheet, 0.0, 0.7, 1.2)
	for _i in 20:
		blind.fill(rng, 3, _context(PipeDefs.NO_EXIT, false))
	var after: Array = _profile(blind, rng, sideways, sought)
	_check(float(after[0]) > 0.0, "offers dealt before there is a joint still deal")
