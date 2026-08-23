## Decides which shapes go into the offer the player picks from.
##
## The rule is an object rather than a function because the interesting ones
## keep state between deals — a pity counter, a memory of what was handed out
## last — and because swapping one rule for another should be a single line in
## Main rather than a rewrite of the offer.
##
## To add a rule: subclass, override `fill`, and hand the instance to
## PipeOffer.start(). Nothing else has to change.
class_name PipeDealer
extends RefCounted

var _balance: GameBalance


func setup(balance: GameBalance) -> void:
	_balance = balance


## Returns exactly `count` distinct shapes for the player to choose between.
##
## `context` carries everything about the run a rule could reasonably want, so
## that a rule which starts caring about fuel, or about the joint the cart is
## heading for, changes neither this signature nor any of its call sites. The
## keys are the ones Main._deal_context() fills in:
##
##   need         side the cart will arrive from at the joint it still has to
##                reach, or PipeDefs.NO_EXIT when the track ahead is built
##   buffer       cells of built track in front of the cart
##   fuel         fuel left, and fuel_max the size of the tank
##   runs_played  runs this player has finished, ever
##   in_slump     true while they are on a run of bad games
##   visible      shapes already in front of the player that this deal is not
##                replacing — the rest of the queue, or the windows a held
##                offer is keeping. A rule that rescues a dead strip needs to
##                know what is already on it.
##
## A rule must cope with an empty context: the first offer of a run is dealt
## before there is a joint to serve.
func fill(_rng: RandomNumberGenerator, _count: int,
		_context: Dictionary) -> Array[int]:
	push_error("PipeDealer.fill is abstract — subclass it")
	var nothing: Array[int] = []
	return nothing


# --- how much help is warranted ----------------------------------------
#
# Shared by every rule, because the question is the same one whatever the
# mechanic: this player, in this much trouble, this experienced, deserves how
# heavy a thumb on the scale? What each rule *does* with the answer is where
# the variants part company.


## Assistance owed right now, 0..1.
func assistance(context: Dictionary) -> float:
	if _balance == null:
		return 0.0
	var ceiling := _ceiling(
		int(context.get("runs_played", 0)),
		bool(context.get("in_slump", false)))
	var pressure_now := _pressure(
		float(context.get("fuel", 0.0)),
		float(context.get("fuel_max", 1.0)),
		int(context.get("buffer", 0)),
		int(context.get("horizon", 0)))
	# The curve is concave: at middling pressure assistance is still almost
	# off, and it comes in sharply at the edge. The player should never feel
	# led by the hand — only that the game did not finish them off.
	return pow(clampf(pressure_now, 0.0, 1.0), 1.5) * ceiling


## How much trouble the player will be in when this shape reaches their hand —
## not how much they are in now. It is `horizon` moves away, so reading the
## present would arrive that many moves late.
func _pressure(fuel: float, fuel_max: float, buffer: int,
		horizon: int) -> float:
	# Fuel is spent deterministically, so it can be projected outright.
	var projected: float = fuel - _balance.fuel_per_cell * horizon
	var fuel_ratio: float = projected / maxf(fuel_max, 1.0)
	var floor_ratio: float = maxf(_balance.assist_fuel_floor, 0.01)
	var fuel_pressure := clampf((floor_ratio - fuel_ratio) / floor_ratio,
		0.0, 1.0)

	# Buffer cannot be projected — it depends on what the player builds — but
	# its current value says what pace they are keeping.
	var buffer_floor: float = maxf(float(_balance.assist_buffer_floor), 1.0)
	var buffer_pressure := clampf((buffer_floor - buffer) / buffer_floor,
		0.0, 1.0)

	# The larger of two dangers, not their sum: being short of both is not
	# twice as bad as being short of one.
	return maxf(fuel_pressure, buffer_pressure)


## Ceiling on assistance for a player this experienced.
func _ceiling(runs_played: int, in_slump: bool) -> float:
	var ceiling: float = _balance.assist_max_veteran
	if runs_played < _balance.assist_runs_new:
		ceiling = _balance.assist_max_new
	elif runs_played < _balance.assist_runs_early:
		ceiling = _balance.assist_max_early
	if in_slump:
		ceiling += _balance.assist_slump_bonus
	return clampf(ceiling, 0.0, 1.0)


## Shapes that take the cart in from `need`, and the rest, as [fitting, misfits].
static func split_by_fit(need: int) -> Array:
	var fitting: Array[int] = []
	var misfits: Array[int] = []
	for type: int in PipeDefs.ALL:
		if need != PipeDefs.NO_EXIT and PipeDefs.SIDES[type].has(need):
			fitting.append(type)
		else:
			misfits.append(type)
	return [fitting, misfits]


## Shuffles in place against the run's own stream. Array.shuffle() would reach
## for the global RNG, and spec section 11 needs a daily to deal every player
## the same shapes.
static func shuffle(rng: RandomNumberGenerator, pool: Array[int]) -> void:
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep := pool[i]
		pool[i] = pool[j]
		pool[j] = keep
