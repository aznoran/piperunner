## Which gameplay variant this player is in, and how they got there.
##
## ## The switch
##
## C is built, tested and **not served**. Two Remote Config keys, not one:
##
##   held_windows_enabled   the switch. False, or absent, and every player
##                          gets B — whatever else the config says, and
##                          whatever group they were in before.
##   gameplay_variant       the split, "B" or "C". Only consulted while the
##                          switch is on.
##
## Two keys rather than one because they answer different questions. The split
## is an experiment setting, fiddled with while a test is being planned; the
## switch is a decision about what players get. Collapsing them into one value
## means a mistyped rollout percentage starts serving an untested mechanic, and
## there is no way to take it back in a hurry.
##
## The switch also overrides a saved group, which is the one place the
## assign-once rule below is deliberately broken. That is what a kill switch
## is: turning it off has to put everybody back on B, including the players
## already in C. The saved letter is kept rather than erased, so turning it on
## again restores the groups instead of reshuffling them.
##
## ## The split, when it is running
##
## The group comes from Remote Config, under `gameplay_variant`, as "B" or "C".
## Firebase buckets by installation ID, so a player who lands in C stays in C
## for as long as the app is installed — that stability is what makes the
## comparison mean anything, and it is why the assignment is not rolled here.
##
## Three rules keep the data honest:
##
##   * **Assign once.** The first answer Remote Config gives is written to disk
##     and is the answer from then on. A later fetch that disagrees — a
##     reconfigured experiment, a changed rollout — does not move a player who
##     is already counted, because a player who switched variants mid-test
##     belongs to neither group.
##
##   * **Offline keeps its group, once the switch is on.** A player already in
##     C keeps C on a session with no network. Falling back to B there would
##     file their runs under the baseline and quietly poison it. Before the
##     switch is on there is no group to keep, so B it is.
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
## The master switch. Until this is true, C is not served to anybody.
const SWITCH := "held_windows_enabled"
## What a player gets when the switch is off, when Remote Config has never
## answered, and when it answers with something this build does not understand.
const FALLBACK := BlockSource.Variant.B
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
## Whether the config has opened C up. False until a fetch says otherwise, so
## a build that never reaches the network serves B and nothing else.
var held_windows_enabled: bool = false


func _ready() -> void:
	_load()

	var config := FirebaseBridge.remote_config()
	if config == null:
		# No SDK — desktop, or a build without the plugins. The switch stays
		# off, so B it is, and the saved group is left alone so that a build
		# which can reach the config still honours it.
		variant = FALLBACK
		_publish()
		return

	# Fetched even for a player already in a group, unlike a plain assign-once
	# design: the switch has to be able to reach them.
	if config.has_signal("fetched"):
		config.fetched.connect(_on_fetched, CONNECT_ONE_SHOT)
	config.fetch(FETCH_INTERVAL)


## The variant's letter, as Remote Config and the dashboard spell it.
func name_of() -> String:
	return BlockSource.NAMES[variant]


## Builds the source for the live variant. The one place a variant letter turns
## into behaviour — everywhere else in the game talks to BlockSource.
func make_source() -> BlockSource:
	if variant == BlockSource.Variant.C:
		return HeldOfferSource.new()
	return OfferSource.new()


## Forces a variant from the debug bench. Deliberately does not persist and
## does not count as an assignment: this is for trying C without shipping it,
## not for joining its group.
func override(to: int) -> void:
	variant = clampi(to, 0, BlockSource.NAMES.size() - 1)
	debug_override = true
	resolved.emit(variant)


func _on_fetched(success: bool) -> void:
	if not success:
		variant = FALLBACK
		_publish()
		return
	var config := FirebaseBridge.remote_config()
	if config == null:
		variant = FALLBACK
		_publish()
		return

	held_windows_enabled = config.get_string(SWITCH, "false") \
		.strip_edges().to_lower() in ["true", "1", "yes", "on"]
	if not held_windows_enabled:
		# The switch is off. Everyone plays B, including anyone already
		# assigned to C — see the note at the top about why this one case
		# overrides the saved group.
		variant = FALLBACK
		_publish()
		return

	var letter: String = config.get_string(KEY, BlockSource.NAMES[FALLBACK])
	var index: int = BlockSource.NAMES.find(letter.strip_edges().to_upper())
	if index == -1:
		# A value nobody in this build understands. Better the baseline than a
		# guess: a mistyped config should not scatter players at random.
		push_warning("Unknown %s value %s — falling back" % [KEY, letter])
		variant = FALLBACK
		_publish()
		return

	variant = index
	assigned = true
	_save()
	_publish()


## Announces the group. Stamping it on the user is Main's job rather than this
## file's: reaching for another autoload by its global name binds this script
## to the whole project being stood up, which a headless harness never does,
## and it is the kind of coupling that only fails where it is hardest to see.
func _publish() -> void:
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
