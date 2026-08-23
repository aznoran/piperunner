## Variant B's rule: three distinct shapes, with a thumb on the scale that
## presses on *quality* rather than on availability.
##
## The arithmetic is what makes this different from the queue's rule. Whatever
## side the cart arrives from, four of the seven shapes serve it, so a draw of
## three distinct shapes is dead only once in thirty-five deals. Weighting the
## draw toward a shape that fits — which is the whole of the queue's
## assistance — would therefore be answering a question the player almost never
## asks. In B they are practically always *able* to extend the track; what they
## are short of is a good way to.
##
## So assistance here works on two levels:
##
##   Coverage   the rare dead offer is quietly given a way out. Cheap, because
##              it fires on under 3% of deals, and it removes the one outcome
##              the player can do nothing about.
##
##   Quality    the real lever. An offer is spent whole, so a turn that buys
##              only a sideways shuffle costs all three shapes. Under pressure
##              the offer is guaranteed to hold something that climbs, so the
##              turn can be worth its price.
##
## Neither level removes the misfits. A comfortable player still gets offers
## that are all awkward — that is the game, and it is where the choosing is.
class_name OfferDealer
extends PipeDealer


func fill(rng: RandomNumberGenerator, count: int,
		context: Dictionary) -> Array[int]:
	var wanted: int = clampi(count, 1, PipeDefs.ALL.size())
	var pool: Array[int] = []
	pool.assign(PipeDefs.ALL)
	shuffle(rng, pool)
	pool.resize(wanted)

	var need: int = int(context.get("need", PipeDefs.NO_EXIT))
	if need == PipeDefs.NO_EXIT:
		return pool  # no joint to serve yet; an even draw is the honest one

	# Held windows count toward what the player has: variant C keeps some of
	# the strip, and a rule that ignored them would insure a cover the strip
	# already had.
	var standing: Array = context.get("visible", [])

	# Paid whether or not the player is in trouble, because it is parity rather
	# than help: a crossroads goes straight through, so two shapes keep a climb
	# going and only one gets a sideways cart back to climbing. See
	# GameBalance.turn_relief for the arithmetic.
	if _sideways(need):
		_ensure_climb(rng, pool, standing, need, _balance.turn_relief)

	var assist_now := assistance(context)
	if assist_now <= 0.0:
		return pool
	_ensure_fit(rng, pool, standing, need)
	_ensure_climb(rng, pool, standing, need, assist_now)
	return pool


## Whether the cart is crossing the board rather than climbing it.
func _sideways(need: int) -> bool:
	return need == PipeDefs.Side.L or need == PipeDefs.Side.R


## Puts a way out into an offer that has none. Not gated by how much
## assistance is owed beyond it being owed at all: an offer nothing fits is not
## a hard choice, it is no choice, and there is nothing to learn from it.
func _ensure_fit(rng: RandomNumberGenerator, pool: Array[int],
		standing: Array, need: int) -> void:
	if _any(pool, standing, func(type: int) -> bool: return _serves(type, need)):
		return
	var fitting: Array[int] = split_by_fit(need)[0]
	if fitting.is_empty():
		return
	shuffle(rng, fitting)
	_swap_in(rng, pool, fitting, standing, need)


## Puts a climbing shape into an offer that has none, as often as assistance
## says. Rolled rather than applied outright, so the help stays deniable: a
## player who was going to be handed a way up half the time cannot tell which
## half was the game.
func _ensure_climb(rng: RandomNumberGenerator, pool: Array[int],
		standing: Array, need: int, assist_now: float) -> void:
	if rng.randf() > assist_now:
		return
	if _any(pool, standing, func(type: int) -> bool: return _climbs(type, need)):
		return
	var climbing: Array[int] = []
	for type: int in PipeDefs.ALL:
		if _climbs(type, need):
			climbing.append(type)
	if climbing.is_empty():
		return
	shuffle(rng, climbing)
	_swap_in(rng, pool, climbing, standing, need)


## Drops one of `wanted` into the offer, replacing the shape the player would
## miss least: a misfit first, and only a fitting shape if every slot fits.
func _swap_in(rng: RandomNumberGenerator, pool: Array[int],
		wanted: Array[int], standing: Array, need: int) -> void:
	var chosen := -1
	for candidate: int in wanted:
		if not pool.has(candidate) and not standing.has(candidate):
			chosen = candidate
			break
	if chosen == -1:
		return

	var expendable: Array[int] = []
	for i in pool.size():
		if not _serves(pool[i], need):
			expendable.append(i)
	if expendable.is_empty():
		for i in pool.size():
			expendable.append(i)
	pool[expendable[rng.randi_range(0, expendable.size() - 1)]] = chosen


func _serves(type: int, need: int) -> bool:
	return PipeDefs.SIDES[type].has(need)


## Whether the cart leaves this shape going up. Height is the score, so a shape
## that fits but turns the cart sideways buys a turn and no ground.
func _climbs(type: int, need: int) -> bool:
	return PipeDefs.exit_side(type, need) == PipeDefs.Side.U


func _any(pool: Array[int], standing: Array, test: Callable) -> bool:
	for type: int in pool:
		if test.call(type):
			return true
	for type: int in standing:
		if test.call(type):
			return true
	return false
