## The floor rule: `count` different shapes, drawn evenly, ignoring the run.
##
## Even rather than weighted, and distinct rather than free. An offer of three
## is not a draw — the player is not being handed a piece, they are being handed
## a decision — and both weighting the options and letting them repeat only make
## that decision quieter. Spec section 04's weights stay in PipeDefs for the
## rules that come after this one.
class_name RandomDealer
extends PipeDealer


func fill(rng: RandomNumberGenerator, count: int,
		_context: Dictionary) -> Array[int]:
	var pool: Array[int] = []
	pool.assign(PipeDefs.ALL)

	# Fisher-Yates against the run's own stream. Array.shuffle() would reach for
	# the global RNG, and spec section 11 needs a daily to deal every player the
	# same offers.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep := pool[i]
		pool[i] = pool[j]
		pool[j] = keep

	pool.resize(clampi(count, 1, pool.size()))
	return pool
