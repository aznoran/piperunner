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

static var _current: LocationSkin


static func current() -> LocationSkin:
	if _current == null:
		_current = load(DEFAULT_SKIN)
	return _current


## Makes `skin` the one new readers get. Call Main.apply_skin() instead if a
## run is live — it also refreshes everything already on screen.
static func set_current(skin: LocationSkin) -> void:
	if skin != null:
		_current = skin
