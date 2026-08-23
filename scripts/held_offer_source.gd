## Variant C — three shapes on the strip, take one, only that window refills.
##
## ## The held state
##
## This is the only thing that separates C from B, and the whole point of
## comparing them.
##
## In B the offer is spent whole: take any shape and all three windows are
## re-dealt, so nothing on the strip outlives the turn it was dealt on. In C a
## window is refilled only when the player takes from *that* window. The other
## two are **held** — their shapes are untouched, and they stay on the strip,
## turn after turn, until the player finally takes from them.
##
## What that buys the player is a stash they did not have to pay for. An
## awkward shape can be left sitting in its window until the joint that wants
## it comes round — a stash they never had to pay for. What it costs them is that the strip goes stale: take
## repeatedly from one window and the other two silently become dead weight,
## and the choice narrows to one live shape and two shapes they have already
## decided against.
##
## Which of those dominates is the question the experiment answers, so the two
## behaviours have to be otherwise identical — same strip, same dealer, same
## number of windows. Only the refill differs, and it is the one method
## overridden here.
##
## `block_taken` carries `was_held` so the analysis can separate a take from a
## freshly dealt window from a take from one the player had been sitting on.
class_name HeldOfferSource
extends OfferSource

## True for a window whose shape was carried over from an earlier turn rather
## than dealt on the last one. Parallel to the offer's choices, and rebuilt
## whenever the offer is re-dealt from scratch.
var _held: Array[bool] = []


func variant() -> int:
	return Variant.C


## C's own rule. Refilling one window while two stay put is a different problem
## from dealing three at once — the strip can go stale, and only one slot can
## do anything about it. See HeldOfferDealer.
func make_dealer() -> PipeDealer:
	return HeldOfferDealer.new()


func start(rng: RandomNumberGenerator, balance: GameBalance,
		dealer: PipeDealer, context: Dictionary) -> void:
	super(rng, balance, dealer, context)
	# A fresh offer is entirely fresh: at the start of a run nothing has been
	# sat on yet.
	_reset_held()


## Refills only the window that was taken from, and marks every other window
## as held from here on. The shapes in them are not re-rolled, not re-ordered
## and not replaced — the player is entitled to find them exactly where they
## left them.
func spend(context: Dictionary) -> void:
	var taken := _offer.selected
	_offer.replace(taken, context)

	if _held.size() != _offer.choices.size():
		_reset_held()
	for i in _held.size():
		# Everything the player did not take has now outlived a turn, which is
		# what being held means. The window they took from is fresh again.
		_held[i] = i != taken
	_held[taken] = false


func resize(context: Dictionary) -> void:
	var before := _offer.choices.size()
	super(context)
	if _offer.choices.size() != before:
		# A resize re-deals the whole offer rather than padding it, so nothing
		# on the strip is held any more.
		_reset_held()


func holds_windows() -> bool:
	return true


func chosen_was_held() -> bool:
	var index := _offer.selected
	if index < 0 or index >= _held.size():
		return false
	return _held[index]


func _held_flags() -> Array[bool]:
	if _held.size() != _offer.choices.size():
		_reset_held()
	return _held


func _reset_held() -> void:
	_held.clear()
	_held.resize(_offer.choices.size())
	_held.fill(false)
