## The shipped rule: a weighted roll with a thumb on the scale when the player
## is in trouble. Spec section 04, plus the assistance designed in
## docs/feel-and-dealer.md.
##
## The plain weighted roll is the floor: about 45% of pieces do not fit the
## current joint, and that is the game. What this adds only presses when the
## player is genuinely in trouble, and lifts off entirely when they are not.
##
## Two things make it honest. It never touches a piece the player has already
## seen — only the one being appended to the back of the queue. And it never
## removes the misfits: at full assistance a fitting piece is roughly four
## times likelier, not certain.
class_name AssistDealer
extends PipeDealer


## Rolls `count` shapes for the back of the queue. Repeats are allowed here, on
## purpose — this rule hands out one piece at a time and a run of three
## crossroads is a thing that happens.
func fill(rng: RandomNumberGenerator, count: int,
		context: Dictionary) -> Array[int]:
	var need: int = int(context.get("need", PipeDefs.NO_EXIT))
	var assist_now := _assist(context)

	var dealt: Array[int] = []
	for _i in maxi(count, 1):
		dealt.append(_deal(rng, need, assist_now))

	# If nothing the player can see serves the joint, make the piece at the
	# back — the one still unseen — the way out. Anything nearer has already
	# been read and planned against.
	if assist_now > 0.0 and not dealt.is_empty():
		var visible: Array = context.get("visible", [])
		if _window_is_dead(visible + dealt, need):
			dealt[dealt.size() - 1] = _rescue(rng, need)
	return dealt


## How hard the thumb presses, 0..1, given everything the run knows.
func _assist(context: Dictionary) -> float:
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


## How much trouble the player will be in when this piece reaches their hand —
## not how much they are in now. The piece is `horizon` moves away, so reading
## the present would arrive that many moves late.
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


## Rolls a shape. `need` is the side the cart will arrive from at the joint, or
## PipeDefs.NO_EXIT when there is no joint to serve.
func _deal(rng: RandomNumberGenerator, need: int, assist_now: float) -> int:
	var total := 0.0
	var weights := {}
	for type: int in PipeDefs.WEIGHTS:
		var weight: float = float(PipeDefs.WEIGHTS[type])
		if need != PipeDefs.NO_EXIT:
			if PipeDefs.SIDES[type].has(need):
				weight *= 1.0 + _balance.assist_fit_gain * assist_now
			else:
				weight *= maxf(
					1.0 - _balance.assist_miss_penalty * assist_now, 0.05)
		weights[type] = weight
		total += weight

	var roll := rng.randf() * total
	for type: int in weights:
		roll -= weights[type]
		if roll <= 0.0:
			return type
	return PipeDefs.Type.V


## True when nothing on screen can serve the joint. The check is on the visible
## pieces rather than on a run of past misses, because the player reads what is
## in front of them, not the history: five pieces on screen with no way out
## feels like a sentence even when the next one would have saved them.
func _window_is_dead(visible: Array, need: int) -> bool:
	if need == PipeDefs.NO_EXIT:
		return false
	for type: int in visible:
		if PipeDefs.SIDES[type].has(need):
			return false
	return true


## A shape that serves the joint, for when the window has gone dead.
func _rescue(rng: RandomNumberGenerator, need: int) -> int:
	var fitting: Array[int] = []
	for type: int in PipeDefs.WEIGHTS:
		if PipeDefs.SIDES[type].has(need):
			fitting.append(type)
	if fitting.is_empty():
		return PipeDefs.Type.V
	return fitting[rng.randi_range(0, fitting.size() - 1)]
