## Makes the game's typeface cover Russian.
##
## Chakra Petch is Latin and Thai; it has no Cyrillic at all, so every Russian
## string drew as a row of empty boxes the moment the platform served the game
## in ru. Godot's own bundled font has the Cyrillic — and, going the other way,
## none of the arrows the keyboard hints are drawn with, which Chakra Petch
## does have. Neither font is enough on its own and both are already in the
## build, so they are chained rather than replaced: Chakra Petch keeps the
## game's face for everything it can draw, and anything it cannot falls through
## to the bundled font.
##
## Done in code because the fallback is a built-in resource with no res:// path
## for a .tres to point at.
class_name Fonts
extends RefCounted

const FACES := [
	"res://art/fonts/ChakraPetch-SemiBold.ttf",
	"res://art/fonts/ChakraPetch-Bold.ttf",
	"res://art/fonts/ChakraPetch-Medium.ttf",
]


## The game's face, with the fallback already chained onto it.
##
## Everything that draws text by hand used to reach for ThemeDB.fallback_font,
## which is the *bundled* font rather than the game's — so the strip and the
## board were set in a different typeface from every Control beside them, and
## the keyboard hints drew as boxes, the arrows being exactly what the bundled
## font is missing. One face, asked for in one place.
static func face() -> Font:
	install_fallbacks()
	var chosen: Font = load(FACES[0])
	return chosen if chosen != null else ThemeDB.fallback_font


## Call once, before anything draws. Loading a font here returns the same
## cached resource the theme holds, so setting the fallback on it settles the
## question for every label in the game rather than for a copy of one.
static func install_fallbacks() -> void:
	var backstop: Font = ThemeDB.fallback_font
	if backstop == null:
		return
	for path in FACES:
		var face: FontFile = load(path)
		if face == null or face.fallbacks.has(backstop):
			continue
		face.fallbacks = face.fallbacks + [backstop]
