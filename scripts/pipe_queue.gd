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


func start(rng: RandomNumberGenerator, preview_size: int) -> void:
	_rng = rng
	_size = preview_size
	upcoming.clear()
	held = NONE
	_refill()


## The piece in hand.
func current() -> int:
	return upcoming[0] if not upcoming.is_empty() else PipeDefs.Type.V


## Called once the piece in hand has been placed.
func consume() -> void:
	if not upcoming.is_empty():
		upcoming.pop_front()
	_refill()


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


func _refill() -> void:
	while upcoming.size() < _size:
		upcoming.append(PipeDefs.random_type(_rng))
