## Deals for the path the cart is actually on: what carries it onward, and what
## strands it.
##
## Two rules, answering two different complaints, and both working the same
## way — the offer is drawn evenly, and then a rule may claim **one cell of
## it**, picked at random. The other cells keep whatever the even draw gave
## them.
##
## That shape is deliberate, and it is the second attempt. Choosing every cell
## from a pool saturates: for a sideways cart exactly three shapes carry the
## path on, which is exactly the size of the strip, so a high chance stopped
## dealing an offer at all and started dealing that same fixed set every turn —
## two thirds of which carry the cart further sideways. Claiming one cell keeps
## the other two an honest draw however hard the knob is turned.
##
## ## The turn rule
##
## A corner leaves the cart crossing the board instead of climbing it, and only
## some of the shapes that fit will carry it on from there. Arriving from the
## left, four shapes fit — H, UL, DL and X — but DL turns the cart straight
## back down, which is the one outcome a player who has just turned cannot
## afford. So with probability `path_turn_chance` one cell of the offer is
## drawn from the shapes that carry the path on, and within that draw the shape
## that puts the cart back on its climb — UL here, UR coming the other way —
## takes `path_straight_share` of it.
##
## Which shapes those are is worked out from the geometry rather than listed,
## so it follows the corner the player actually turned:
##
##     placed DR -> cart leaves right -> joint needs L -> H, UL, X   (UL climbs)
##     placed DL -> cart leaves left  -> joint needs R -> H, UR, X   (UR climbs)
##
## Zero is off and means the plain even draw. There is no floor: missing the
## roll now costs the player nothing, where the first version dealt a miss out
## of the shapes that *do not* carry on, and so needed one.
##
## The rule says nothing while the cart is climbing. Arriving from below, every
## shape that fits carries on — none of V, DR, DL or X points the cart down —
## so there is no split to weight, and biasing the draw would only be the old
## availability lever wearing a new name.
##
## ## The pity rule
##
## The turn rule is one roll, so a whole offer can still arrive with nothing on
## it worth having, and doing that twice running reads as the game being broken
## rather than hard. This rule watches the offer as a whole: every deal that
## lands without a way on raises the odds the next one is given one, and any
## deal that carries resets it. When it fires it claims one random cell,
## exactly as the turn rule does.
##
## The curve is a sigmoid rescaled to start at zero — 2·σ(2kn) − 1, which is
## exactly tanh(kn). Zero on a strip that has just served the player, and
## within a percent of certain after a few barren deals, with `k` deciding how
## few. Deliberately not a counter with a threshold: a hard "every fifth deal"
## is learnable, and a player who can count to the rescue has stopped playing
## the game in front of them.
##
## What it holds out for is the *scarce* continuation rather than any of them.
## Climbing is the score, so the shape worth waiting for is the one that keeps
## the cart on its climb or puts it back there — V and X while climbing, the
## one elbow that turns up after a corner. Only where no shape can climb at
## all, which is a cart already heading down, does it settle for anything that
## does not make the descent worse. Watching for merely-carrying shapes would
## leave the rule idle: a sideways cart is handed one of those 89% of the time
## by luck alone, so a streak long enough to matter would never form.
##
## Unlike the turn rule this one works whether or not the cart has turned,
## because being handed nothing usable is the same complaint either way.
##
## The two compose in one direction only: the turn rule may claim a cell, then
## the pity rule looks at what is on the strip and may claim another. Neither
## removes the misfits, and a comfortable player still gets awkward offers —
## that is the game, and it is where the choosing is.
class_name PathDealer
extends OfferDealer

## Deals in a row that offered nothing worth waiting for. The dealer lives for
## one run, so this resets with it.
var _barren: int = 0


func fill(rng: RandomNumberGenerator, count: int,
		context: Dictionary) -> Array[int]:
	var wanted: int = clampi(count, 1, PipeDefs.ALL.size())
	var need: int = int(context.get("need", PipeDefs.NO_EXIT))
	var standing: Array = context.get("visible", [])

	# The draw underneath both rules is the even one, always. Each rule then
	# claims at most one cell of it.
	var pool: Array[int] = []
	pool.assign(PipeDefs.ALL)
	shuffle(rng, pool)
	pool.resize(wanted)

	# No joint to serve yet: nothing to judge, and a deal nobody can judge must
	# not move the pity counter either way.
	if need == PipeDefs.NO_EXIT:
		return pool

	if _turned(need) and rng.randf() < _balance.path_turn_chance:
		_claim_cell(rng, pool, standing, _carrying(need), need)

	# Nothing worth waiting for on the strip: act on the odds that the barren
	# deals before this one have already earned.
	var sought := _worth_waiting_for(need)
	if not _holds_any(pool, standing, sought) and rng.randf() < _pity():
		_claim_cell(rng, pool, standing, sought, need)

	# The offer of last resort. Cheap — three distinct shapes are dead only
	# once in thirty-five deals — and it removes the one outcome the player can
	# do nothing about at all.
	_ensure_fit(rng, pool, standing, need)

	_barren = 0 if _holds_any(pool, standing, sought) else _barren + 1
	return pool


## Puts one shape from `source` into one cell of the offer, picked at random.
## The rest of the strip keeps whatever the even draw gave it.
func _claim_cell(rng: RandomNumberGenerator, pool: Array[int],
		standing: Array, source: Array[int], need: int) -> void:
	var chosen := _draw_from(rng, source, pool, standing, need)
	if chosen == -1:
		return  # the strip already holds everything this pool could offer
	pool[rng.randi_range(0, pool.size() - 1)] = chosen


## One shape from `source` that is not on the strip already, with the shapes
## that resume the climb taking `path_straight_share` of the draw between them
## and the rest splitting what is left. -1 when the pool has nothing new.
func _draw_from(rng: RandomNumberGenerator, source: Array[int],
		taken: Array[int], standing: Array, need: int) -> int:
	var climbing: Array[int] = []
	var others: Array[int] = []
	for type: int in source:
		if taken.has(type) or standing.has(type):
			continue
		if _climbs(type, need):
			climbing.append(type)
		else:
			others.append(type)

	if climbing.is_empty() and others.is_empty():
		return -1
	if climbing.is_empty():
		return others[rng.randi_range(0, others.size() - 1)]
	if others.is_empty():
		return climbing[rng.randi_range(0, climbing.size() - 1)]
	if rng.randf() < _balance.path_straight_share:
		return climbing[rng.randi_range(0, climbing.size() - 1)]
	return others[rng.randi_range(0, others.size() - 1)]


## How hard this deal leans on the barren ones before it, 0..1.
func _pity() -> float:
	var strength: float = _balance.path_pity_strength
	if strength <= 0.0 or _barren <= 0:
		return 0.0
	return tanh(strength * float(_barren))


## Whether the path has been turned off its climb. Arriving from below there is
## nothing to recover from and every fitting shape carries on regardless.
func _turned(need: int) -> bool:
	return need != PipeDefs.NO_EXIT and need != PipeDefs.Side.D


## Shapes that take the cart in from `need` and send it anywhere but back down.
func _carrying(need: int) -> Array[int]:
	var out: Array[int] = []
	for type: int in PipeDefs.ALL:
		if _carries(type, need):
			out.append(type)
	return out


func _carries(type: int, need: int) -> bool:
	var exit: int = PipeDefs.exit_side(type, need)
	return exit != PipeDefs.NO_EXIT and exit != PipeDefs.Side.D


## The shapes the pity rule is holding out for: the ones that keep the cart on
## its climb, or put it back on one. A cart already heading down has no such
## shape, and there it settles for anything that does not dig the hole deeper.
func _worth_waiting_for(need: int) -> Array[int]:
	var climbing: Array[int] = []
	for type: int in PipeDefs.ALL:
		if _climbs(type, need):
			climbing.append(type)
	return climbing if not climbing.is_empty() else _carrying(need)


func _holds_any(pool: Array[int], standing: Array,
		shapes: Array[int]) -> bool:
	return _any(pool, standing,
		func(type: int) -> bool: return shapes.has(type))
