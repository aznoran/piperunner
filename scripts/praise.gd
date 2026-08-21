## Picks what to shout at the player, and when to keep quiet.
##
## Praise is feedback, not decoration: it says "that thing you just did was
## good" while the player still remembers doing it. So every message is tied to
## a specific act, and the whole class exists to stop the game saying it too
## often — praise devalues faster than anything else on screen.
class_name Praise
extends RefCounted

## What happened. Weight decides which wins when two land together.
enum Kind { CHAIN, CLUTCH, CLEAN, SWEEP, RECORD }

const WEIGHTS := {
	Kind.CHAIN: 1,
	Kind.CLEAN: 2,
	Kind.SWEEP: 3,
	Kind.CLUTCH: 4,
	Kind.RECORD: 5,
}

## One and the same word must not come back inside this many messages.
const SAME_TEXT_GAP := 3

var _balance: GameBalance
var _cooldown: float = 0.0
var _shown: int = 0
var _recent: Array[String] = []


func setup(balance: GameBalance) -> void:
	_balance = balance


func start_run() -> void:
	_cooldown = 0.0
	_shown = 0
	_recent.clear()


func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## The bar for a chain rises as the run goes on: two crystals in a row is worth
## saying something about at the start and routine by row fifty.
func chain_threshold(distance: int) -> int:
	return _balance.praise_combo_base + int(floor(
		float(distance) / float(maxi(_balance.praise_combo_step, 1))))


## Returns the text to show, or "" to stay silent.
func consider(kind: Kind, combo: int = 0) -> String:
	var text := _text_for(kind, combo)
	if text.is_empty():
		return ""
	# A record is once a run and never waits its turn.
	if kind != Kind.RECORD:
		if _cooldown > 0.0 or _shown >= _balance.praise_run_cap:
			return ""
		if _recent.has(text):
			return ""
	_cooldown = _balance.praise_cooldown
	_shown += 1
	_recent.push_front(text)
	while _recent.size() > SAME_TEXT_GAP:
		_recent.pop_back()
	return text


func _text_for(kind: Kind, combo: int) -> String:
	match kind:
		Kind.RECORD:
			return "NEW BEST"
		Kind.CLUTCH:
			return "CLUTCH"
		Kind.CLEAN:
			return "CLEAN"
		Kind.SWEEP:
			return "SWEEP"
		Kind.CHAIN:
			if combo >= 5:
				return "PERFECT"
			if combo == 4:
				return "SUPER"
			if combo == 3:
				return "GREAT"
			if combo == 2:
				return "NICE"
			return ""
		_:
			return ""
