## Variant A — the forced queue the game shipped with, and the baseline the
## other two have to beat.
##
## The player does not choose the shape, only the cell. One piece is in hand,
## the rest of the preview trails behind it, and the single thing they can do
## about a shape they cannot use is pocket it — which is a swap, not a reroll.
##
## So there is exactly one tap target on this strip: the pocket.
class_name QueueSource
extends BlockSource

var _queue := PipeQueue.new()
var _bar: QueueBar


func variant() -> int:
	return Variant.A


## The queue is a forced draw, so it needs the thumb on the scale: without it
## a run of shapes that do not fit the joint is simply a death sentence with
## no decision in it. Spec section 04 and docs/feel-and-dealer.md.
func make_dealer() -> PipeDealer:
	return AssistDealer.new()


func attach(queue_bar: QueueBar, offer_bar: OfferBar) -> void:
	_bar = queue_bar
	queue_bar.visible = false
	offer_bar.visible = false


func start(rng: RandomNumberGenerator, balance: GameBalance,
		dealer: PipeDealer, context: Dictionary) -> void:
	super(rng, balance, dealer, context)
	_queue.start(rng, balance.queue_preview, dealer, context)


func current() -> int:
	return _queue.current()


## The pocket is the only target, so any tap on this strip is a swap.
func point_at(index: int) -> bool:
	if index != 0:
		return false
	_queue.swap_hold()
	return true


func spend(context: Dictionary) -> void:
	_queue.consume(context)


func resize(context: Dictionary) -> void:
	_queue.resize(_balance.queue_preview, context)


func refresh() -> void:
	if _bar != null:
		_bar.set_contents(_queue.upcoming, _queue.held)


func tap_targets() -> Array[Rect2]:
	if _bar == null:
		return []
	return [_bar.hold_rect]


func strip_top() -> float:
	return _bar.strip_top if _bar != null else INF


func strip() -> Control:
	return _bar


## The piece in hand, and only that: the preview behind it belongs to future
## turns and the pocket is reached by tapping, not by choosing.
func choices() -> Array[int]:
	return [_queue.current()]


func slot_count() -> int:
	return _queue.upcoming.size()


## What the pocket holds, or PipeQueue.NONE. Main needs it to decide whether a
## tap on the pocket is worth a puff of dust.
func held() -> int:
	return _queue.held
