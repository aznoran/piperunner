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
