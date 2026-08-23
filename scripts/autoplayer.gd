## Plays the game by itself, for recording.
##
## It is deliberately not a cheat: it goes through the same two actions a
## finger has — choose one of the shapes on offer, place it at a cell — reads
## only what is on screen, and cannot see past the offer. Nothing it does is
## privileged, so a run it plays counts exactly like a played one.
##
## Nor is it optimal. It thinks for a beat before acting, its timing wanders,
## and it takes the odd wrong turn on purpose. A perfect machine reads as a
## machine on video; a good player with a pulse does not.
class_name Autoplayer
extends Node

## How well it plays. SHOWCASE is a good player with a pulse — it hesitates,
## it misplays, it dies. EXPERT is the one that has to reach a hundred cells:
## same two actions, same information, but it looks a move ahead and does not
## make casual mistakes.
enum Skill { SHOWCASE, EXPERT }

## Emitted when the bot takes a run over, naming the archetype it is playing
## as. Main passes it to the behaviour log; nothing else listens.
signal took_over(persona_name: String)

var skill: Skill = Skill.SHOWCASE

## How good it is, on a dial rather than a switch: 0 is a beginner who mostly
## reacts, 1 is the expert that weighs every shape on offer. The two presets sit
## at either end and the debug panel can put it anywhere between, which is the
## only way to see how a given standard of play meets a given set of formulas.
var proficiency: float = SHOWCASE_LEVEL

## The kind of player this is. Proficiency lives on it too, and the property
## above stays in step so the debug bench's one slider keeps working.
var persona: Persona = Persona.by_name("Optimiser")

const SHOWCASE_LEVEL := 0.35
const EXPERT_LEVEL := 1.0
## Below this it takes the first shape that works; above it, it weighs them all.
const PLANS_FROM := 0.6

## Seconds between actions. The spread is what stops it looking mechanical.
const THINK_MIN := 0.16
const THINK_MAX := 0.42
## Every so often it pauses like someone reconsidering.
const HESITATE_CHANCE := 0.08
const HESITATE_EXTRA := 0.55
## And every so often it simply plays the wrong cell.
const MISTAKE_CHANCE := 0.03
## How far ahead of the cart it will build. Beyond this the track leaves the
## screen, which is no use to a player watching and no use on video either.
## However impatient a persona is, it has to be willing to build past the
## starting runway — below this it decides the track is long enough before it
## has laid anything, and plays no moves at all.
const MIN_BUFFER := 4
const MAX_BUFFER := 5
## The expert keeps a deeper reserve than the showcase bot, but the screen is
## the real limit: track laid where the player cannot see it is not play, it
## just looks like the run is happening somewhere else.
const MAX_BUFFER_EXPERT := 10
## Below this fraction of a tank it starts routing towards crystals rather
## than straight up.
const THIRSTY := 0.45

var active: bool = false

var _main: Node
var _board: Board
var _cart: Cart
## Whatever the live experiment variant hands the player. The bot reads the
## same strip they do, and takes from it the same way.
var _offer: BlockSource
var _wait: float = 0.0
var _rng := RandomNumberGenerator.new()

## Why the last run went the way it did. Debug only; costs nothing to keep.
var tally := {}


func _bump(what: String) -> void:
	tally[what] = int(tally.get(what, 0)) + 1


func setup(main: Node, board: Board, cart: Cart, offer: BlockSource) -> void:
	_main = main
	_board = board
	_cart = cart
	_offer = offer


## `dice` fixes the bot's own randomness — benchmarks pass a seed so two runs
## of different code face the same hesitations. Left at -1 in play.
func start(level: Skill = Skill.SHOWCASE, dice: int = -1,
		level_override: float = -1.0, style: Persona = null) -> void:
	skill = level
	if style != null:
		persona = style
		proficiency = style.proficiency
	else:
		proficiency = level_override if level_override >= 0.0 \
			else (EXPERT_LEVEL if level == Skill.EXPERT else SHOWCASE_LEVEL)
		# A bare proficiency with no persona keeps the balanced weights, so the
		# bench slider behaves exactly as it did before personas existed.
		persona = Persona.by_name("Optimiser")
		persona.proficiency = proficiency
	tally = {}
	if dice >= 0:
		_rng.seed = dice
	else:
		_rng.randomize()
	active = true
	_wait = 0.6
	took_over.emit(persona.name)


func stop() -> void:
	active = false


func _process(delta: float) -> void:
	if not active or _main == null:
		return
	if _main.state != 1:  # only while a run is live
		return
	# One action per frame is not enough when frames are long — on a stuttering
	# phone the cart keeps rolling while the hand waits for the next frame. Work
	# through the time that actually passed, capped so a hitch cannot turn into
	# a burst of play no finger could match.
	_wait -= delta
	var actions := 0
	while _wait <= 0.0 and actions < 4:
		_wait += _think_time()
		_act()
		actions += 1


## How long before the next action. A good player speeds up as the cart does,
## and stops dithering when the track runs out — so this tracks both, and only
## hesitates when there is room to.
func _think_time() -> float:
	var urgency: float = clampf(_main.speed / maxf(_main.balance.speed_cap, 0.1), 0.0, 1.0)
	var base: float = lerpf(THINK_MAX, THINK_MIN, urgency)
	base *= lerpf(1.0, 0.55, _grade())  # better players are quicker on the tap
	base *= persona.haste
	var jitter: float = base * _rng.randf_range(0.7, 1.3)

	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	var buffer: int = int(ahead.get("steps", 9))
	if bool(ahead.get("blocked", false)):
		return THINK_MIN * 0.35  # a wrong-facing pipe ahead: fix it now
	if buffer <= 1:
		return THINK_MIN * 0.5  # no time to think
	if buffer >= 4 and _rng.randf() < HESITATE_CHANCE * (1.0 - _grade()):
		return jitter + HESITATE_EXTRA
	return jitter


func _act() -> void:
	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	if ahead.is_empty():
		return
	var joint: Vector2i = ahead["cell"]
	var need: int = ahead["need"]
	var blocked: bool = ahead["blocked"]

	var buffer: int = int(ahead["steps"])
	var rows := _board.visible_rows()

	# Building past the top of the screen wastes pieces on track nobody can see
	# — and on video it looks like the run is happening somewhere else.
	var cap: int = clampi(int(roundf(
		lerpf(MAX_BUFFER, MAX_BUFFER_EXPERT, _grade()) * persona.patience)),
		MIN_BUFFER, MAX_BUFFER_EXPERT)
	var too_far: bool = buffer >= cap or joint.y > rows.y - 1

	# A pipe at the joint that refuses the cart is not a dead end — it is a pipe
	# nobody has replaced yet. The game lets you build over anything the cart
	# has not run through, and a cart three cells away from a wrong-facing pipe
	# is exactly when a strong player does it. Distance caps do not apply: this
	# is the run ending in three seconds.
	if blocked:
		_bump("blocked")
		var repair := _pick_for(joint, need, buffer, true)
		if repair >= 0 and _board.can_place(joint):
			# Building over the wrong-facing pipe. No slip here, however
			# casually the bot is playing — this move is the run.
			_bump("repair")
			_choose(repair)
			_main._try_place(joint)
		elif _reroute():
			_bump("reroute")
		else:
			# Nothing on offer serves the jam. Standing still is death, and
			# spending a shape behind the cart brings a fresh offer up.
			_bump("cycle")
			_dump(joint)
		return

	# Whether anything on offer merely fits, ignoring where it points the cart.
	# That is the question for deciding to wait; quality is asked separately.
	var lenient := _pick_for(joint, need, buffer, true)
	if lenient >= 0 and (too_far or not _board.can_place(joint)):
		_bump("wait")
		return  # hold the good shape until the joint opens up

	if not too_far and lenient >= 0 and _board.can_place(joint):
		var fit := _pick_for(joint, need, buffer, false)
		if fit >= 0:
			_bump("extend")
			_choose(fit)
			_place(joint)
			return
		_bump("refused")
	elif too_far:
		_bump("too_far")
	elif lenient < 0:
		_bump("wrong_shape")
	else:
		_bump("cant_place")

	# No use at the joint. Before throwing a shape away, see whether one of them
	# is track the route will want anyway.
	if _stockpile(joint):
		_bump("stockpile")
		return

	_bump("dump")
	_dump(joint)


## Whether laying this piece here is a move worth making.
##
## Not fitting the joint is only half the question. A piece that fits can still
## point the cart downward or into the wall, and the score is distance climbed
## — a run that wanders sideways along row three is a run going nowhere. The
## exception is a cart about to derail: then any track beats no track.
func _worth_extending(cell: Vector2i, piece: int, entry: int, buffer: int) -> bool:
	var exit: int = PipeDefs.exit_side(piece, entry)
	if exit == PipeDefs.NO_EXIT:
		return false

	var next: Vector2i = cell + PipeDefs.DIR[exit]
	if next.x < 0 or next.x >= _main.balance.cols:
		return false
	if _board.rocks.has(next):
		return false
	if _opens_off_board(cell, piece):
		return false
	# Pointing the cart at a pipe that will not take it is how these runs end.
	# Only when the track has run out is it worth the gamble — by then there is
	# time to build over it, and no track at all is certain death.
	if not _clear(next, PipeDefs.OPPOSITE[exit]) and buffer > 2:
		return false

	# Out of road: take whatever keeps the cart alive. The expert calls it a
	# cell earlier — every refusal costs a turn, and a turn spent not building
	# is how the buffer reaches zero. Derailing, not fuel, is what ends these
	# runs.
	if buffer <= (2 if _plans() else 1):
		return true

	# A crystal is always worth the detour.
	if _board.crystals.has(next):
		return true

	if exit == PipeDefs.Side.D:
		# Ground given back has to be climbed again, so this is a last resort —
		# but with the track running out it still beats no track at all.
		# Measured: allowing it on a full tank instead drops the run from 69
		# cells to 12, because the route walks itself down out of the build
		# zone and every move after that is refused.
		return _plans() and buffer <= 3

	if exit == PipeDefs.Side.L or exit == PipeDefs.Side.R:
		var beyond: Vector2i = next + PipeDefs.DIR[exit]
		if beyond.x < 0 or beyond.x >= _main.balance.cols:
			return false
		if _board.rocks.has(Vector2i(next.x, next.y + 1)):
			return false

		var crystal := _nearest_crystal()
		if crystal != Board.NO_CELL:
			# Towards fuel is always worth it; away from it only with a
			# comfortable tank.
			if absi(next.x - crystal.x) < absi(cell.x - crystal.x):
				return true
			return _main.fuel / _main.balance.fuel_max > 0.5

		# No crystal in sight: sideways keeps the track alive and costs no
		# height, so the expert takes it rather than burning the turn.
		return _plans() \
			or _main.fuel / _main.balance.fuel_max < _thirst()

	return true


# --- choosing -----------------------------------------------------------

## The shape on offer that best serves this joint, or -1 when none does.
##
## There is no queue to read to the end any more — the two shapes not taken
## vanish along with the one that is, so nothing on screen belongs to a later
## turn. What is left to be good at is this turn: which of the three keeps the
## cart climbing, and which of them points it at a wall.
##
## `desperate` drops the bar to "it fits and the cart survives". That is for a
## jammed joint, where the run ends in three seconds and there is no time to be
## fussy about which way the track points.
func _pick_for(joint: Vector2i, need: int, buffer: int, desperate: bool) -> int:
	var best := -1
	var best_score := -INF
	for i in _offer.choices().size():
		var piece: int = _offer.choices()[i]
		if not _serves(piece, need):
			continue
		if not desperate and not _worth_extending(joint, piece, need, buffer):
			continue
		if not _plans():
			return i  # a player who reacts takes the first shape that works
		var score := _score(joint, piece, need)
		score -= _cost_of_losing(i) * persona.hoarding
		if score > best_score:
			best_score = score
			best = i
	return best


## What the strip gives up by spending the shape in slot `i`.
##
## Only meaningful where windows are held: in B the whole strip is replaced
## next turn, so nothing is being given up at all, and in A there is nothing to
## choose between. Where they are held, spending a shape costs the strip every
## side no other window can answer — so a hoarder reaches for the redundant
## shape and leaves the one that covers ground the others do not.
##
## This is the bot doing what variant C is for. Without it the strip is played
## as if it were re-dealt every turn, which is variant B with extra steps, and
## measuring C that way measures nothing.
func _cost_of_losing(index: int) -> float:
	if persona.hoarding <= 0.0 or not _offer.holds_windows():
		return 0.0
	var shapes := _offer.choices()
	if index < 0 or index >= shapes.size():
		return 0.0

	var elsewhere := {}
	for i in shapes.size():
		if i == index:
			continue
		for side: int in PipeDefs.SIDES[shapes[i]]:
			elsewhere[side] = true

	var lost := 0.0
	for side: int in PipeDefs.SIDES[shapes[index]]:
		if not elsewhere.has(side):
			lost += 1.0
	return lost * 2.0


## What laying this shape at the joint is worth. One ply deep by necessity: the
## cell the cart ends up in next, and whether that is a cell worth arriving at.
func _score(joint: Vector2i, piece: int, entry: int) -> float:
	var exit: int = PipeDefs.exit_side(piece, entry)
	if exit == PipeDefs.NO_EXIT:
		return -1000.0
	var next: Vector2i = joint + PipeDefs.DIR[exit]
	if next.x < 0 or next.x >= _main.balance.cols or _board.rocks.has(next):
		return -1000.0

	var score: float = float(next.y - joint.y) * persona.climb
	if _board.crystals.has(next):
		score += persona.fuel  # fuel is distance
	if not _clear(next, PipeDefs.OPPOSITE[exit]):
		score -= 8.0  # aiming the cart at a pipe that will not take it

	# Sideways towards the nearest crystal beats sideways away from it.
	var crystal := _nearest_crystal()
	if crystal != Board.NO_CELL:
		score += float(absi(joint.x - crystal.x) - absi(next.x - crystal.x)) \
			* persona.fuel * 0.25
	return score


## Points the offer at one of its shapes, through the same call a tap makes.
func _choose(index: int) -> void:
	# Already pointing there. Worth checking rather than tapping anyway: a tap
	# is a real action, and a redundant one costs a turn the cart is still
	# rolling through.
	if index == _offer.chosen_slot():
		return
	_main._on_offer_chosen(index)


## True when this shape, here, would throw the cart off the board — from any
## side it opens onto, not only the one the bot is planning for.
##
## The joint is the entry expected right now, but it is not the only entry the
## route can produce: track gets built over, litter gets driven through, and a
## reroute turns the cart into a cell from a new direction. A piece that opens
## onto a wall is a derailment waiting for the cart to arrive the other way.
## The plan tree used to see that coming a few moves out; one ply cannot, so
## these are refused outright.
func _opens_off_board(cell: Vector2i, piece: int) -> bool:
	for side: int in PipeDefs.SIDES[piece]:
		var exit: int = PipeDefs.exit_side(piece, side)
		if exit == PipeDefs.NO_EXIT:
			continue
		var beyond: Vector2i = cell + PipeDefs.DIR[exit]
		if beyond.x < 0 or beyond.x >= _main.balance.cols:
			return true
	return false


## Ground a plan may route through: empty, or a pipe that already takes the
## cart from that side. Deliberately stricter than _accepts, which counts on
## being able to build over a wrong-facing pipe — true at the joint in front of
## the cart, wishful thinking four moves down a line.
func _clear(cell: Vector2i, side: int) -> bool:
	var existing := _board.get_pipe(cell)
	return existing == null or PipeDefs.SIDES[existing.type].has(side)


## The pipes the cart is going to run through, in the order it meets them,
## each with the side it will arrive from.
func _route() -> Array:
	var cell: Vector2i = _cart.cell()
	var entry: int = _cart.entry
	var path := []
	for _i in 40:
		var pipe := _board.get_pipe(cell)
		if pipe == null:
			break
		var exit: int = PipeDefs.exit_side(pipe.type, entry)
		if exit == PipeDefs.NO_EXIT:
			break
		path.append({"cell": cell, "entry": entry})
		cell += PipeDefs.DIR[exit]
		entry = PipeDefs.OPPOSITE[exit]
	return path


## Sends the cart a different way by rebuilding a pipe it has not reached yet.
##
## When the jam itself cannot be built over — the cart is standing on it, or it
## is already run through — the track further back usually can be, and turning
## the route aside a cell earlier saves the run just as well. This is the move
## a player makes without thinking about it and the bot used to die without.
func _reroute() -> bool:
	var path := _route()
	var rows := _board.visible_rows()
	# Latest first: the change closest to the jam disturbs the least track.
	for i in range(path.size() - 1, -1, -1):
		var cell: Vector2i = path[i]["cell"]
		var entry: int = path[i]["entry"]
		if not _board.can_place(cell):
			continue
		var existing := _board.get_pipe(cell)
		for c in _offer.choices().size():
			var piece: int = _offer.choices()[c]
			if not _serves(piece, entry):
				continue
			if existing != null and existing.type == piece:
				continue  # same pipe, same jam
			var exit: int = PipeDefs.exit_side(piece, entry)
			if exit == PipeDefs.NO_EXIT:
				continue
			var next: Vector2i = cell + PipeDefs.DIR[exit]
			if next.x < 0 or next.x >= _main.balance.cols:
				continue
			if _board.rocks.has(next) or not _clear(next, PipeDefs.OPPOSITE[exit]):
				continue
			if next.y > rows.y - 1 or _opens_off_board(cell, piece):
				continue
			_choose(c)
			_main._try_place(cell)
			return true
	return false


## Where this bot sits between the two presets, 0..1. Every skill-dependent
## number is a lerp along this, so the presets keep exactly the behaviour they
## were tuned and measured at.
func _grade() -> float:
	return clampf((proficiency - SHOWCASE_LEVEL)
		/ maxf(EXPERT_LEVEL - SHOWCASE_LEVEL, 0.001), 0.0, 1.0)


## Whether it is good enough to plan rather than react.
func _plans() -> bool:
	return proficiency >= PLANS_FROM


## Whether the cart survives entering this cell from `side`. Empty ground is
## fine — that is just track not built yet. A pipe already there has to take
## that entry, and one the cart has run through can no longer be replaced.
func _accepts(cell: Vector2i, side: int) -> bool:
	var existing := _board.get_pipe(cell)
	if existing == null:
		return true
	if PipeDefs.SIDES[existing.type].has(side):
		return true
	return not existing.flooded and _board.can_place(cell)


## Somewhere useful for a piece that does not serve the joint.
##
## The refusal version of this — decline the move unless the queue can follow
## it — measured worse than no expertise at all: refusing costs a turn, the
## buffer drains, and the cart derails anyway. Building ahead spends the same
## turn on track the cart will need, which is what a strong player does with
## an awkward piece.
##
## It lays into the column the route is climbing, one or two cells past the
## joint, where the cart will arrive from below.
func _stockpile(joint: Vector2i) -> bool:
	if not _plans():
		return false

	# Only stockpile straight ahead when the route is not about to turn off
	# towards fuel.
	var target := _nearest_crystal()
	if target != Board.NO_CELL and absi(target.x - joint.x) > 1:
		return false

	var rows := _board.visible_rows()
	for step in [1, 2]:
		var spot := Vector2i(joint.x, joint.y + step)
		if spot.y > rows.y - 1:
			break
		if _board.get_pipe(spot) != null:
			continue
		if not _board.can_place(spot):
			continue
		for c in _offer.choices().size():
			var piece: int = _offer.choices()[c]
			# Only a shape that takes the cart from below is any use up there.
			if not _serves(piece, PipeDefs.Side.D):
				continue
			var exit: int = PipeDefs.exit_side(piece, PipeDefs.Side.D)
			if exit == PipeDefs.NO_EXIT:
				continue
			var next: Vector2i = spot + PipeDefs.DIR[exit]
			if next.x < 0 or next.x >= _main.balance.cols or _board.rocks.has(next):
				continue
			if _opens_off_board(spot, piece):
				continue
			_choose(c)
			_main._try_place(spot)
			return true
	return false


## When to start caring about fuel. The expert plans its refuelling earlier,
## because a hundred cells cannot be crossed on one tank.
func _thirst() -> float:
	return lerpf(THIRSTY, 0.75, _grade())


## The nearest crystal ahead that is actually on screen. Chasing one off the
## top of the display would take the run out of frame.
func _nearest_crystal() -> Vector2i:
	var rows := _board.visible_rows()
	var best := Board.NO_CELL
	var best_cost := 999
	for cell: Vector2i in _board.crystals:
		if cell.y <= _cart.row or cell.y > rows.y:
			continue
		var cost: int = (cell.y - _cart.row) + absi(cell.x - _cart.col) * 2
		if cost < best_cost:
			best_cost = cost
			best = cell
	return best


func _serves(piece: int, need: int) -> bool:
	return PipeDefs.SIDES[piece].has(need)


func _place(cell: Vector2i) -> void:
	# The occasional misplay, so the run has texture.
	if _rng.randf() < MISTAKE_CHANCE * (1.0 - _grade()) * persona.sloppiness:
		var sideways: int = [PipeDefs.Side.L, PipeDefs.Side.R][_rng.randi() % 2]
		var slip: Vector2i = cell + PipeDefs.DIR[sideways]
		if _board.can_place(slip):
			_main._try_place(slip)
			return
	_main._try_place(cell)


## Junk goes behind the cart, in the litter zone — the play the game is built
## around. Which shape gets spent used to look arbitrary — the offer is re-dealt
## whole either way — but litter is not as safely out of the way as that
## assumes: a route that turns back down runs through it, and a wall-facing
## pipe left there kills the cart. So the shape is chosen too. It also has to
## go somewhere the
## viewer can see: a piece dropped off the bottom of the screen looks to them
## like the piece simply vanished.
func _dump(joint: Vector2i) -> void:
	var rows := _board.visible_rows()
	var lowest: int = maxi(_board.max_row - _main.balance.place_below, rows.x + 1)
	var highest: int = mini(_cart.row, rows.y)

	var best := Board.NO_CELL
	var best_score := -1000.0
	for row in range(lowest, highest):
		for col in _main.balance.cols:
			var spot := Vector2i(col, row)
			if spot == joint or _board.get_pipe(spot) != null:
				continue
			if not _board.can_place(spot):
				continue
			# Just behind the cart and off to one side: in shot, out of the way.
			var score := 6.0 - absf(float(_cart.row - row) - 2.0) \
				+ absf(col - _cart.col) * 0.5
			if score > best_score:
				best_score = score
				best = spot

	if best != Board.NO_CELL:
		_choose(_safe_at(best))
		_main._try_place(best)


## Which shape can be left at this cell without pointing the cart off the board
## should the route ever come back through it. Falls back to whatever is
## already chosen when none of them is safe there.
func _safe_at(cell: Vector2i) -> int:
	for i in _offer.choices().size():
		if not _opens_off_board(cell, _offer.choices()[i]):
			return i
	return _offer.chosen_slot()
