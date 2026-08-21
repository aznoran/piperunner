## The location skin currently in effect.
##
## Locations differ only in appearance: same rules, same generation, same
## events. Anything that draws asks here for its colours, and Main pushes a
## change down to its children — there is deliberately no listener list here,
## since a static array of Callables outlives the nodes it points at.
##
## A plain global class rather than an autoload, so scripts holding a skin
## reference compile standalone for headless tools and tests.
class_name Skins
extends RefCounted

const DEFAULT_SKIN := "res://resources/skins/NeonNeutral.tres"

## Every location that ships. Order is the order they cycle in.
const CATALOGUE_PATHS := [
	"res://resources/skins/NeonNeutral.tres",
	"res://resources/skins/Forest.tres",
]

static var _current: LocationSkin
static var _catalogue: Array[LocationSkin] = []


static func current() -> LocationSkin:
	if _current == null:
		_current = load(DEFAULT_SKIN)
	return _current


## Makes `skin` the one new readers get. Call Main.apply_skin() instead if a
## run is live — it also refreshes everything already on screen.
static func set_current(skin: LocationSkin) -> void:
	if skin != null:
		_current = skin


static func catalogue() -> Array[LocationSkin]:
	if _catalogue.is_empty():
		for path: String in CATALOGUE_PATHS:
			var skin: LocationSkin = load(path)
			if skin != null:
				_catalogue.append(skin)
	return _catalogue


static func by_name(display_name: String) -> LocationSkin:
	for skin in catalogue():
		if skin.display_name == display_name:
			return skin
	return null


## The location after the current one, wrapping around.
static func next() -> LocationSkin:
	var all := catalogue()
	if all.is_empty():
		return current()
	var index := all.find(current())
	return all[(index + 1) % all.size()]
