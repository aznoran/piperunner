## Everything the experiment measures, in one place.
##
## Every event carries the variant, so any report can be split three ways
## without joining against anything. The variant also goes on as a *user
## property*, which is the only thing Firebase's own retention report can be
## filtered by: D1 and D7 are computed from sessions the SDK logs by itself,
## and those carry no parameters of ours.
##
## ## Naming
##
## `session_start` is a reserved Firebase event name — the SDK logs its own and
## rejects ours — so the pair here is `play_session_start` / `play_session_end`.
## They measure time in the app from the game's point of view; Firebase's
## automatic sessions keep counting alongside them, already split by variant
## through the user property.
##
## ## Ordering
##
## The variant is not known at boot: Remote Config has to answer first. Events
## logged before then would be filed under the fallback and quietly corrupt the
## first session of every new player, so they are held here and flushed once
## Experiment publishes the group. In practice that is the same frame for
## everyone who already has a group on disk.
extends Node

## Firebase caps a custom parameter's string value at 100 characters.
const VALUE_LIMIT := 100
## A guard against the buffer growing without bound if the variant never
## resolves. Far above a real session's worth of pre-resolve events.
const BUFFER_LIMIT := 64

var _variant: String = ""
var _debug_override: bool = false
## Events logged before the variant was known: [name, params] pairs.
var _pending: Array = []
## Wall-clock seconds at the last play_session_start.
var _session_began: float = 0.0
## Deaths retried in a row without going back to the menu.
var _retry_streak: int = 0


func _ready() -> void:
	# Analytics has to outlive the tree being torn down, so that the closing
	# session event still reaches the SDK.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Records the group and stamps it on the user. Called by Experiment as soon as
## the group is known, which releases anything buffered.
func set_variant(letter: String, overridden: bool = false) -> void:
	_variant = letter
	_debug_override = overridden

	var native := FirebaseBridge.analytics()
	if native != null:
		native.set_user_property("variant", letter)
	_flush()


func session_start() -> void:
	_session_began = _now()
	log_event("play_session_start", {})


func session_end() -> void:
	log_event("play_session_end", {
		"duration_s": int(_now() - _session_began),
	})


## A run that ended by itself — the cart derailed, ran dry or reached a goal.
func run_completed(distance: int, score: int, seconds: float,
		reason: String) -> void:
	log_event("run_completed", {
		"distance": distance,
		"score": score,
		"duration_s": int(seconds),
		"reason": reason,
	})
	_retry_streak = 0


## A run the player walked out of — back to the menu, or the app closing
## mid-run. `stage` says what they were doing, so an abandon on the first cell
## is not counted the same as one at cell ninety.
func run_abandoned(distance: int, seconds: float, stage: String) -> void:
	log_event("run_abandoned", {
		"distance": distance,
		"duration_s": int(seconds),
		"stage": stage,
	})
	_retry_streak = 0


## A shape taken off the strip.
##
## `slot` and `slot_count` are what separate the variants: in A there is one
## place a piece can come from, in B and C there are three. `was_held` is the
## question variant C exists to answer — whether the player took the shape that
## had just been dealt, or one they had been sitting on for a turn or more.
func block_taken(shape: int, slot: int, slot_count: int,
		was_held: bool, distance: int) -> void:
	log_event("block_taken", {
		"shape": PipeDefs.name_of(shape),
		"slot": slot,
		"slot_count": slot_count,
		"was_held": was_held,
		"distance": distance,
	})


## A restart straight after a death. The parameter is the length of the streak,
## so "how many players retry three times in a row" is one filter rather than a
## session reconstruction.
func retry() -> void:
	_retry_streak += 1
	log_event("retry", {"streak": _retry_streak})


## Sends an event, or holds it until the variant is known.
func log_event(event: String, params: Dictionary) -> void:
	if _variant.is_empty():
		if _pending.size() < BUFFER_LIMIT:
			_pending.append([event, params])
		return
	_send(event, params)


func _flush() -> void:
	var held := _pending
	_pending = []
	for entry: Array in held:
		_send(entry[0], entry[1])


func _send(event: String, params: Dictionary) -> void:
	var full := params.duplicate()
	full["variant"] = _variant
	if _debug_override:
		# Marks a session the bench was steering. Nothing forced from the debug
		# menu belongs in the experiment's numbers.
		full["debug_override"] = true

	var native := FirebaseBridge.analytics()
	if native != null:
		native.log_event(event, _clean(full))
		return
	if OS.is_debug_build():
		print("[analytics] %s %s" % [event, full])


## Firebase rejects an event whose string values run long, and silently drops
## the whole event rather than truncating. Cheaper to trim here.
func _clean(params: Dictionary) -> Dictionary:
	var out := {}
	for key: String in params:
		var value: Variant = params[key]
		if value is String and (value as String).length() > VALUE_LIMIT:
			value = (value as String).substr(0, VALUE_LIMIT)
		out[key] = value
	return out


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
