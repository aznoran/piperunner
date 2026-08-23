## Where the next pipe comes from — the one thing the A/B/C experiment varies.
##
## This is the `BlockSelectionStrategy` of the experiment brief. Main talks to
## this and never to a concrete variant, so switching variants is a single
## assignment rather than a branch threaded through the game loop.
##
## Three implementations ship:
##
##   A  QueueSource      a forced queue — one piece in hand, a preview behind
##                       it, a pocket to stash an awkward shape. The mechanic
##                       the game shipped with, and the baseline to beat.
##   B  OfferSource      three shapes, take one, all three are replaced. The
##                       player chooses the shape as well as the cell, and pays
##                       for it by spending the whole offer.
##   C  HeldOfferSource  three shapes, take one, only that one is replaced.
##                       The two untaken stay put, so an awkward shape can be
##                       left on the strip until there is a use for it.
##
## A variant owns its own strip. That is why `attach` takes both: each one
## shows the widget its mechanic is built around and hides the other, and Main
## never has to ask which is on screen.
class_name BlockSource
extends RefCounted

## Which experiment group this is. The letters are the values Remote Config
## serves, so they are the names used end to end — config, code and analytics.
enum Variant { A, B, C }

## Names for analytics and for the debug bench, indexed by Variant.
const NAMES := ["A", "B", "C"]

var _balance: GameBalance
var _dealer: PipeDealer
var _rng: RandomNumberGenerator


func variant() -> int:
	push_error("BlockSource.variant is abstract — subclass it")
	return Variant.A


## The rule this variant deals shapes by. Each mechanic was designed around
## one, so the pairing belongs to the variant rather than to Main: the queue
## leans on assistance to stay survivable, and the offer deliberately does not.
func make_dealer() -> PipeDealer:
	return RandomDealer.new()


## Binds the source to the two strips in the scene and leaves **both hidden**.
##
## Binding is not showing. A source is built whenever the variant changes,
## which includes standing in the menu with the bench open — and a strip that
## appeared there would sit across the menu's own buttons with a run that has
## not started. `reveal` is the separate, deliberate step.
func attach(_queue_bar: QueueBar, _offer_bar: OfferBar) -> void:
	push_error("BlockSource.attach is abstract — subclass it")


## Shows this variant's strip. Called when a run begins, and never before.
func reveal() -> void:
	var bar := strip()
	if bar != null:
		bar.visible = true


## Begins a run. `context` is the deal context described on PipeDealer.
func start(rng: RandomNumberGenerator, balance: GameBalance,
		dealer: PipeDealer, context: Dictionary) -> void:
	_rng = rng
	_balance = balance
	_dealer = dealer


## The shape the next placement spends.
func current() -> int:
	push_error("BlockSource.current is abstract — subclass it")
	return PipeDefs.Type.V


## The player touched tap target `index`. Returns true if anything changed and
## the strip needs repainting.
func point_at(_index: int) -> bool:
	return false


## The chosen shape has been placed. Deals whatever comes next.
func spend(_context: Dictionary) -> void:
	push_error("BlockSource.spend is abstract — subclass it")


## An upgrade changed how many shapes the player gets. Safe to call every
## layout pass: implementations ignore a size they already have.
func resize(_context: Dictionary) -> void:
	pass


## Repaints the strip and refreshes the tap targets on it.
func refresh() -> void:
	push_error("BlockSource.refresh is abstract — subclass it")


## Screen-space rects the player can touch, in tap-target order. Index 0 here
## is index 0 in `point_at`.
func tap_targets() -> Array[Rect2]:
	return []


## Screen y below which touches belong to the strip rather than the board.
func strip_top() -> float:
	return INF


## The Control this variant draws on, so Main can fade the right one without
## knowing which variant is live.
func strip() -> Control:
	return null


## The shapes a placement could spend right now, left to right.
##
## Variant A returns one — the piece in hand. That is not a limitation of the
## reporting, it is the mechanic: in A the player chooses the cell and nothing
## else. Anything reading this (the bot, analytics) gets the same answer the
## player sees.
func choices() -> Array[int]:
	return [current()]


## Which slot the next placement spends, for `block_taken`. Variant A has one
## place a piece can come from, so it always reports 0.
func chosen_slot() -> int:
	return 0


## Whether the shape in the chosen slot was carried over from a previous turn
## rather than dealt this one. Only variant C can answer yes; it is the whole
## point of the comparison, so it is on the interface rather than cast for.
func chosen_was_held() -> bool:
	return false


## How many shapes are on offer, for `block_taken`.
func slot_count() -> int:
	return 1
