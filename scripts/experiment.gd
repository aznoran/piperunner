## Which gameplay variant this player is in, and how they got there.
##
## The group comes from Remote Config, under `gameplay_variant`, as one of
## "A", "B" or "C". Firebase buckets by installation ID, so a player who lands
## in C stays in C for as long as the app is installed — that stability is what
## makes the comparison mean anything, and it is why the assignment is not
## rolled here.
##
## Three rules keep the data honest:
##
##   * **Assign once.** The first answer Remote Config gives is written to disk
##     and is the answer from then on. A later fetch that disagrees — a
##     reconfigured experiment, a changed rollout — does not move a player who
##     is already counted, because a player who switched variants mid-test
##     belongs to neither group.
##
##   * **Offline keeps its group.** The A fallback is only for a player who has
##     never been assigned at all. Once a group is on disk, a session with no
##     network uses it. Falling back to A there would file a C player's
##     sessions under A and quietly poison the baseline.
##
##   * **Debug overrides are marked.** The bench can force a variant for
##     testing. That is not an assignment: it does not overwrite the group on
##     disk, and every event it produces carries `debug_override` so the
##     analysis can throw it away.
extends Node

## Emitted once the group is known — on the first fetch, or straight away when
## one is already on disk. Main waits for this before the first run so the
## first session is filed under the right group.
signal resolved(variant: int)

## Remote Config key and the values it may hold.
const KEY := "gameplay_variant"
## What a player gets when Remote Config has never answered. The brief's
## baseline: whatever else happens, an unassigned player plays the game the
## way it shipped.
const FALLBACK := BlockSource.Variant.A
## Where the group lives between sessions.
const SAVE_PATH := "user://experiment.cfg"
## How stale a cached config may be before a fetch goes to the network. Twelve
## hours: the group never changes once assigned, so fetching harder buys
## nothing.
const FETCH_INTERVAL := 43200

## The group this player is in.
var variant: int = FALLBACK
## True once Remote Config or the save file has actually answered. Until then
## `variant` is the fallback and nothing has been assigned.
var assigned: bool = false
## Set while the bench is forcing a variant. Events carry it so overridden
## sessions can be filtered out of the analysis.
var debug_override: bool = false


func _ready() -> void:
	_load()
	if assigned:
		# Already in a group: nothing to wait for, and a later fetch must not
		# move them.
		_publish()
		return

	var config := FirebaseBridge.remote_config()
	if config == null:
		# No SDK — desktop, or a build without the plugins. Stay unassigned so
		# that a real device with a real config still gets to assign properly.
		_publish()
		return

	if config.has_signal("fetched"):
		config.fetched.connect(_on_fetched, CONNECT_ONE_SHOT)
	config.fetch(FETCH_INTERVAL)


## The variant's letter, as Remote Config and the dashboard spell it.
func name_of() -> String:
	return BlockSource.NAMES[variant]


## Builds the source for the live variant. The one place a variant letter turns
## into behaviour — everywhere else in the game talks to BlockSource.
func make_source() -> BlockSource:
	match variant:
		BlockSource.Variant.B:
			return OfferSource.new()
		BlockSource.Variant.C:
			return HeldOfferSource.new()
		_:
			return QueueSource.new()


## Forces a variant from the debug bench. Deliberately does not persist and
## does not count as an assignment: this is for trying the other two, not for
## joining their groups.
func override(to: int) -> void:
	variant = clampi(to, 0, BlockSource.NAMES.size() - 1)
	debug_override = true
	Analytics.set_variant(name_of(), true)
	resolved.emit(variant)


func _on_fetched(success: bool) -> void:
	if not success:
		_publish()
		return
	var config := FirebaseBridge.remote_config()
	if config == null:
		_publish()
		return

	var letter: String = config.get_string(KEY, BlockSource.NAMES[FALLBACK])
	var index: int = BlockSource.NAMES.find(letter.strip_edges().to_upper())
	if index == -1:
		# A value nobody in this build understands. Better the baseline than a
		# guess: a mistyped config should not scatter players at random.
		push_warning("Unknown %s value %s — falling back" % [KEY, letter])
		_publish()
		return

	variant = index
	assigned = true
	_save()
	_publish()


## Announces the group and stamps it on the user, once. The user property is
## what lets Firebase's own retention report be split by variant — D1 and D7
## are computed from sessions the SDK logs by itself, so they can only be
## filtered by a property, never by an event parameter.
func _publish() -> void:
	Analytics.set_variant(name_of(), debug_override)
	resolved.emit(variant)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	var letter: String = config.get_value("experiment", "variant", "")
	var index: int = BlockSource.NAMES.find(letter)
	if index == -1:
		return
	variant = index
	assigned = true


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("experiment", "variant", name_of())
	config.save(SAVE_PATH)
