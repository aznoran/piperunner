## Variant C's rule: the same offer, but refilling one window at a time and
## having to think about the two it is not refilling.
##
## C fails in a way B cannot. In B the strip is wiped every turn, so a bad
## offer costs one turn. In C the untaken windows stay, and a player who keeps
## taking from the same window ends up with two shapes they have already
## decided against — sitting there, turn after turn, until the three-way choice
## has quietly become a one-way one. The strip goes stale, and staleness is
## self-inflicted in a way the player cannot see coming.
##
## So this rule watches what is *staying* rather than what it is dealing. The
## measure it works to is how many of the four sides the whole strip can serve:
## a strip that answers every side is a strip with a real choice on it, and a
## strip that answers one is a queue with extra steps. When the refill is the
## only slot that can move, it goes where the strip is thin.
##
## Two consequences worth stating, because they are easy to mistake for bugs:
##
##   * The refill is chosen by preference, not by roll. `PipeOffer.replace`
##     takes the first shape offered that is not already on the strip, so this
##     returns its list already sorted — best first.
##   * With no assistance owed it sorts by nothing but noise, which is an even
##     draw. A comfortable player is left to manage their own strip, and
##     letting it go stale is a mistake they are allowed to make.
class_name HeldOfferDealer
extends OfferDealer

## What one uncovered side is worth against the noise the sort starts from.
## High enough to decide a tie, low enough that two of them do not always beat
## a shape that fits.
const SIDE_WORTH := 1.0
## What being the strip's only way out is worth. Deliberately above two sides:
## a varied strip that cannot take the cart is decoration.
const RESCUE_WORTH := 4.0


func fill(rng: RandomNumberGenerator, count: int,
		context: Dictionary) -> Array[int]:
	var need: int = int(context.get("need", PipeDefs.NO_EXIT))
	var standing: Array = context.get("visible", [])

	# A whole-strip deal — the first of a run, or a resize — is B's problem,
	# not C's: there is nothing being held to reason about.
	if standing.is_empty():
		return super(rng, count, context)

	var assist_now := assistance(context)
	var covered := _sides_of(standing)
	var strip_can_take: bool = need != PipeDefs.NO_EXIT and covered.has(need)

	var ranked: Array[int] = []
	ranked.assign(PipeDefs.ALL)
	shuffle(rng, ranked)

	var worth := {}
	for type: int in ranked:
		var score := rng.randf()  # the even draw, when nothing is owed
		if assist_now > 0.0:
			var gain := 0.0
			# Sides the strip cannot answer today and would be able to
			# tomorrow. This is the anti-staleness term.
			for side: int in PipeDefs.SIDES[type]:
				if not covered.has(side):
					gain += SIDE_WORTH
			# The strip has no way out and this shape is one. Nothing else on
			# the strip can be changed, so this slot carries the whole run.
			if not strip_can_take and _serves(type, need):
				gain += RESCUE_WORTH
			score += assist_now * gain
		worth[type] = score

	ranked.sort_custom(func(a: int, b: int) -> bool:
		return float(worth[a]) > float(worth[b]))
	ranked.resize(clampi(count, 1, ranked.size()))
	return ranked


## Every side the shapes on the strip can take the cart in from.
func _sides_of(shapes: Array) -> Dictionary:
	var covered := {}
	for type: int in shapes:
		for side: int in PipeDefs.SIDES[type]:
			covered[side] = true
	return covered
