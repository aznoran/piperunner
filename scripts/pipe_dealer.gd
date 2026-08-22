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
##
## A rule must cope with an empty context: the first offer of a run is dealt
## before there is a joint to serve.
func fill(_rng: RandomNumberGenerator, _count: int,
		_context: Dictionary) -> Array[int]:
	push_error("PipeDealer.fill is abstract — subclass it")
	var nothing: Array[int] = []
	return nothing
