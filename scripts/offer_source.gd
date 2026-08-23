## Variant B — three shapes on the strip, take one, all three are replaced.
##
## Where the queue traded on not choosing the piece, this trades on the
## opposite, and pays for it by being spent whole. The two shapes the player
## did not take do not carry over: if they did, the strip would slowly become
## a hand they accumulate rather than a decision they make.
##
## There is no preview here on purpose. Nothing on screen belongs to a future
## turn, so nothing can be planned around beyond the turn being played.
class_name OfferSource
extends BlockSource

var _offer := PipeOffer.new()
var _bar: OfferBar


func variant() -> int:
	return Variant.B


## Even rather than weighted, and distinct rather than free. Three shapes are
## not a draw — the player is being handed a decision, not a piece — and both
## weighting the options and letting them repeat only make that decision
## quieter. Assistance would blunt it further, so the offer does without.
func make_dealer() -> PipeDealer:
	return RandomDealer.new()


func attach(queue_bar: QueueBar, offer_bar: OfferBar) -> void:
	_bar = offer_bar
	offer_bar.visible = true
	queue_bar.visible = false


func start(rng: RandomNumberGenerator, balance: GameBalance,
		dealer: PipeDealer, context: Dictionary) -> void:
	super(rng, balance, dealer, context)
	_offer.start(rng, balance.offer_size, dealer, context)


func current() -> int:
	return _offer.current()


## Choosing is not committing — only placing is — so pointing at a different
## shape is free and reversible as often as the player likes.
func point_at(index: int) -> bool:
	return _offer.select(index)


func spend(context: Dictionary) -> void:
	_offer.take(context)


func resize(context: Dictionary) -> void:
	_offer.resize(_balance.offer_size, context)


func refresh() -> void:
	if _bar != null:
		_bar.set_contents(_offer.choices, _offer.selected, _held_flags())


func tap_targets() -> Array[Rect2]:
	return _bar.slot_rects if _bar != null else [] as Array[Rect2]


func strip_top() -> float:
	return _bar.strip_top if _bar != null else INF


func strip() -> Control:
	return _bar


func choices() -> Array[int]:
	return _offer.choices


func chosen_slot() -> int:
	return _offer.selected


func slot_count() -> int:
	return _offer.choices.size()


## Nothing on this strip is held — every slot is dealt fresh each turn. The
## held variant overrides this, and the bar draws whatever it is told.
func _held_flags() -> Array[bool]:
	var flags: Array[bool] = []
	flags.resize(_offer.choices.size())
	flags.fill(false)
	return flags
