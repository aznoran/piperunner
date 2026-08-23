## The behaviour store: one row per decision, kept on the device.
##
## Firebase Analytics answers "how many players did X" — it aggregates, and it
## throws the individual decision away. That is the right shape for retention
## and the wrong shape for asking *why* someone played the way they did, or for
## ever training anything on it. This keeps the decisions themselves.
##
## A row is what the player could see and what they did about it: the board
## around the cart, the shapes on the strip, which one they took, where they
## put it, and the state of the run. That is a (state, action) pair, which is
## the only form a behaviour model can be fitted to — King's Candy Crush
## play-testing bot is a network trained on millions of exactly these, and
## nothing of the kind is possible from aggregates after the fact.
##
## ## What this is not
##
## It is not analytics. Nothing here is sent anywhere; it is a file in the
## app's own storage that the debug bench can export. Uploading it would be a
## separate decision, with a separate conversation about consent, and this
## deliberately does not make that decision quietly.
##
## ## Cost
##
## A row is about 150 bytes and a decision happens a few times a second, so a
## long run is perhaps 50 KB. Rows are buffered and written once per run rather
## than per decision — a file handle opened on every pipe placement would be
## felt on a phone — and the store is capped, oldest run dropped first.
extends Node

const DIR := "user://playlog"
## Keep the newest few megabytes. Enough for a few hundred runs; small enough
## that nobody has to think about it.
const MAX_BYTES := 4 * 1024 * 1024

## The board window written with each decision, in cells around the cart. Wide
## enough to hold the whole playable width, and tall enough to cover the litter
## zone below the cart and the track being built above it.
const WINDOW_ROWS_BELOW := 2
const WINDOW_ROWS_ABOVE := 9

## Cell codes. Shapes are 0..6 as PipeDefs.Type; the rest are above them so a
## reader never has to guess.
const EMPTY := 7
const ROCK := 8
const CRYSTAL := 9
const FLOODED := 10  # a pipe the cart has already run through: cannot be built on

## The column names, written into every run so the file explains itself.
## `board` is the window hex-encoded, one byte a cell, bottom row first.
const COLUMNS := "#cols\tn\tshape\tslot\tslots\theld\tstrip\tdx\tdy\tfuel\tdistance\tspeed\tthought\tboard"

var _rows: PackedStringArray = []
var _run_id: String = ""
var _began_at: float = 0.0
var _decisions: int = 0
## "human", or the persona a bot is playing as.
var _player: String = "human"


## Records who is at the controls. Called by the autoplayer when it takes over,
## which is after the run has already been opened.
func note_player(who: String) -> void:
	_player = who


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## Opens a run. Everything recorded until `end_run` belongs to it.
func begin_run(variant: String, seed_value: int, mode: int) -> void:
	_rows = PackedStringArray()
	_decisions = 0
	# Who is playing is not known yet: a run is prepared before the autoplayer,
	# if there is one, takes it over. So it is noted when it happens and
	# written at the end.
	_player = "human"
	_began_at = float(Time.get_ticks_msec()) / 1000.0
	# Seed and start time identify the run without identifying the player.
	_run_id = "%d-%d" % [seed_value, Time.get_ticks_usec()]
	_rows.append("#run\t%s\tvariant=%s\tseed=%d\tmode=%d\tutc=%s"
		% [_run_id, variant, seed_value, mode,
			Time.get_datetime_string_from_system(true)])
	# Named here rather than in a document nobody will have to hand when they
	# open the file in six months.
	_rows.append(COLUMNS)


## Records one decision: the strip the player was looking at, the shape they
## took from it, and where it went.
##
## `board` is filled by the caller because only Main can see it, and the window
## is flattened row by row from the bottom of the window upward.
func record(shape: int, slot: int, slot_count: int, was_held: bool,
		strip: Array, cell: Vector2i, cart: Vector2i, need: int,
		fuel: float, distance: int, speed: float, thought: float,
		board: PackedByteArray) -> void:
	if _run_id.is_empty():
		return
	_decisions += 1
	# Tab separated, one line, no quoting needed because no field can contain a
	# tab. Placement is written relative to the cart: what makes a move that
	# move is where it sits in front of the player, not where it sits on a
	# board that scrolls forever.
	_rows.append("%d\t%d\t%d\t%d\t%d\t%s\t%d\t%d\t%.1f\t%d\t%.2f\t%.2f\t%s"
		% [_decisions, shape, slot, slot_count, 1 if was_held else 0,
			_pack_strip(strip), cell.x - cart.x, cell.y - cart.y, fuel,
			distance, speed, thought, board.hex_encode()])


## Closes the run and writes it out.
func end_run(distance: int, score: int, reason: String) -> void:
	if _run_id.is_empty():
		return
	var seconds: float = float(Time.get_ticks_msec()) / 1000.0 - _began_at
	_rows.append("#end\tplayer=%s\tdistance=%d\tscore=%d\tseconds=%.1f\treason=%s"
		% [_player, distance, score, seconds, reason])
	_flush()
	_run_id = ""


## Everything recorded so far, as one file, for pulling off the device.
func export_all() -> String:
	var out := "user://playlog-export.tsv"
	var writer := FileAccess.open(out, FileAccess.WRITE)
	if writer == null:
		return ""
	for path in _files():
		var reader := FileAccess.open(path, FileAccess.READ)
		if reader != null:
			writer.store_string(reader.get_as_text())
	writer.close()
	return ProjectSettings.globalize_path(out)


## Rows held, and bytes on disk. The bench shows both so the store is never a
## mystery box.
func stats() -> Dictionary:
	var bytes := 0
	var runs := 0
	for path in _files():
		bytes += _size_of(path)
		runs += 1
	return {"runs": runs, "bytes": bytes, "pending": _rows.size()}


func clear() -> void:
	for path in _files():
		DirAccess.remove_absolute(path)
	_rows = PackedStringArray()


func _flush() -> void:
	if _rows.is_empty():
		return
	var path := "%s/%s.tsv" % [DIR, _run_id]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_rows) + "\n")
		file.close()
	_rows = PackedStringArray()
	_trim()


## Drops the oldest runs until the store is back under the cap. Oldest first
## because the newest play is the play worth keeping — the game changes under
## it, and a row recorded against a build nobody runs any more is noise.
func _trim() -> void:
	var files := _files()
	files.sort()
	var total := 0
	for path in files:
		total += _size_of(path)
	var i := 0
	while total > MAX_BYTES and i < files.size():
		total -= _size_of(files[i])
		DirAccess.remove_absolute(files[i])
		i += 1


func _files() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return found
	for name in dir.get_files():
		if name.ends_with(".tsv"):
			found.append("%s/%s" % [DIR, name])
	return found


func _size_of(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := int(file.get_length())
	file.close()
	return size


func _pack_strip(strip: Array) -> String:
	var parts: PackedStringArray = []
	for shape: int in strip:
		parts.append(str(shape))
	return ",".join(parts)
