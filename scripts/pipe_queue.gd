## The forced queue and the HOLD pocket. Spec section 09.
##
## The whole tension of the game is that you do not choose the piece, only the
## cell — so the queue never rewinds and HOLD is a swap, not a reroll.
class_name PipeQueue
extends RefCounted

const NONE := -1

var upcoming: Array[int] = []
var held: int = NONE

var _rng: RandomNumberGenerator
var _size: int = 4
var _dealer: Dealer


func start(rng: RandomNumberGenerator, preview_size: int, dealer: Dealer = null) -> void:
	_rng = rng
	_size = preview_size
	_dealer = dealer
	upcoming.clear()
	held = NONE
	_refill()


## The piece in hand.
func current() -> int:
	return upcoming[0] if not upcoming.is_empty() else PipeDefs.Type.V


## Called once the piece in hand has been placed. `need` is the side the cart
## will arrive from at the joint it still has to reach, and `assist` how hard
## the dealer may lean towards serving it.
func consume(need: int = PipeDefs.NO_EXIT, assist: float = 0.0) -> void:
	if not upcoming.is_empty():
		upcoming.pop_front()
	_refill(need, assist)


## Pockets the current piece, or swaps it with what is already pocketed.
## Swapping must not advance the queue, or the player could cycle forever for
## the piece they want. Exactly one free skip per run, the very first.
func swap_hold() -> void:
	if held == NONE:
		held = current()
		consume()
	else:
		var in_hand := current()
		if upcoming.is_empty():
			upcoming.append(held)
		else:
			upcoming[0] = held
		held = in_hand


## Grows or trims the preview without discarding the pieces already queued —
## used when an upgrade changes how far ahead the player can see.
func resize(preview_size: int) -> void:
	_size = maxi(1, preview_size)
	while upcoming.size() > _size:
		upcoming.pop_back()
	_refill()


## Only ever appends. A piece the player has already seen is never changed —
## they plan against the preview, and swapping what they were shown is not
## assistance, it is cheating, and it is noticed.
func _refill(need: int = PipeDefs.NO_EXIT, assist: float = 0.0) -> void:
	while upcoming.size() < _size:
		if _dealer == null:
			upcoming.append(PipeDefs.random_type(_rng))
		else:
			upcoming.append(_dealer.deal(_rng, need, assist))

	# If nothing on screen can serve the joint, make the piece at the back — the
	# one still unseen — the way out.
	if _dealer != null and assist > 0.0 and not upcoming.is_empty():
		if _dealer.window_is_dead(upcoming, need):
			upcoming[upcoming.size() - 1] = _dealer.rescue(_rng, need)
