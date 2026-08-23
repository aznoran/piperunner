## The forced queue and the HOLD pocket. Spec section 09.
##
## The whole tension of this mechanic is that you do not choose the piece, only
## the cell — so the queue never rewinds and HOLD is a swap, not a reroll.
##
## This is the model behind variant A of the experiment; the strip that draws
## it is QueueBar and the two are wired together by QueueSource.
class_name PipeQueue
extends RefCounted

const NONE := -1

var upcoming: Array[int] = []
var held: int = NONE

var _rng: RandomNumberGenerator
var _size: int = 4
var _dealer: PipeDealer


func start(rng: RandomNumberGenerator, preview_size: int,
		dealer: PipeDealer = null, context: Dictionary = {}) -> void:
	_rng = rng
	_size = maxi(1, preview_size)
	_dealer = dealer if dealer != null else RandomDealer.new()
	upcoming.clear()
	held = NONE
	_refill(context)


## The piece in hand.
func current() -> int:
	return upcoming[0] if not upcoming.is_empty() else PipeDefs.Type.V


## Called once the piece in hand has been placed.
func consume(context: Dictionary = {}) -> void:
	if not upcoming.is_empty():
		upcoming.pop_front()
	_refill(context)


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
func resize(preview_size: int, context: Dictionary = {}) -> void:
	_size = maxi(1, preview_size)
	while upcoming.size() > _size:
		upcoming.pop_back()
	_refill(context)


## Only ever appends. A piece the player has already seen is never changed —
## they plan against the preview, and swapping what they were shown is not
## assistance, it is cheating, and it is noticed.
##
## The pieces already on screen go to the rule as `visible`, so a rule that
## rescues a dead window can see what the player is looking at.
func _refill(context: Dictionary) -> void:
	var missing: int = _size - upcoming.size()
	if missing <= 0:
		return
	var ask := context.duplicate()
	ask["visible"] = upcoming.duplicate()
	upcoming.append_array(_dealer.fill(_rng, missing, ask))
