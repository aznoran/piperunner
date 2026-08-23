## The offer: the shapes on the strip, one of which the player takes.
##
## This replaces the forced queue. What the queue traded on was that you do not
## choose the piece, only the cell; the offer trades on the opposite, and pays
## for it by being spent whole. Three shapes, one placement, three new shapes —
## the two not taken do not carry over, or the strip would slowly become a hand
## the player accumulates rather than a decision they make.
##
## There is no preview here on purpose. Nothing on screen belongs to a future
## turn, so nothing can be planned around beyond the turn being played.
class_name PipeOffer
extends RefCounted

## The shapes on offer, all distinct.
var choices: Array[int] = []
## Which of them the next placement spends.
var selected: int = 0

var _rng: RandomNumberGenerator
var _size: int = 3
var _dealer: PipeDealer


func start(rng: RandomNumberGenerator, size: int, dealer: PipeDealer = null,
		context: Dictionary = {}) -> void:
	_rng = rng
	_size = maxi(1, size)
	_dealer = dealer if dealer != null else RandomDealer.new()
	_deal(context)


## The shape a placement will spend.
func current() -> int:
	if selected < 0 or selected >= choices.size():
		return PipeDefs.Type.V
	return choices[selected]


## Points at one of the shapes on offer. Free and reversible as often as the
## player likes: choosing is not committing, only placing is.
func select(index: int) -> bool:
	if index < 0 or index >= choices.size() or index == selected:
		return false
	selected = index
	return true


## Called once the chosen shape has been placed, to deal the next offer.
func take(context: Dictionary = {}) -> void:
	_deal(context)


## Replaces a single window and leaves the rest exactly as they are — the
## refill variant C is built on.
##
## The new shape avoids the ones still on the strip. Letting it repeat them
## would let the strip collapse to three of the same shape, and three identical
## windows is not a choice at all; keeping them distinct is the same rule the
## whole-offer deal already follows.
func replace(index: int, context: Dictionary = {}) -> void:
	if index < 0 or index >= choices.size():
		return
	var kept: Array[int] = choices.duplicate()
	kept.remove_at(index)

	# The windows staying put go to the rule as `visible`. A rule that reasons
	# about the whole strip — C's does — cannot see it any other way.
	var ask := context.duplicate()
	ask["visible"] = kept

	# Ask for a full strip's worth and take the first shape that is not already
	# on it. A rule is free to return shapes in any order, and C's returns them
	# best-first, so the order is the rule's answer rather than a coincidence.
	for candidate: int in _dealer.fill(_rng, _size, ask):
		if not kept.has(candidate):
			choices[index] = candidate
			return
	# Every shape a rule offered is already on the strip. Rare, and only
	# possible when the strip is as wide as the shape list, so the honest
	# answer is to leave the window as it was rather than force a repeat.


## Grows or shrinks the offer — used when an upgrade changes how many shapes
## the player gets to choose between. The offer is re-dealt rather than padded,
## because a rule is entitled to pick its shapes as a set.
func resize(size: int, context: Dictionary = {}) -> void:
	var wanted := maxi(1, size)
	if wanted == _size:
		return
	_size = wanted
	_deal(context)


func _deal(context: Dictionary) -> void:
	choices = _dealer.fill(_rng, _size, context)
	selected = 0
