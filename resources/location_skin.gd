## The whole look of a location in one resource.
##
## Everything the game draws procedurally reads its colours from here, so a new
## location is a new .tres and nothing else — the rules, the generation and the
## events are identical everywhere, only their appearance changes. Swap it at
## runtime through the Skins autoload.
class_name LocationSkin
extends Resource

@export var display_name: String = "Neon Neutral"

@export_group("Background")
@export var bg_top: Color = Color("111c2e")
@export var bg_mid: Color = Color("0b1220")
@export var bg_bottom: Color = Color("070a12")

@export_group("Board")
@export var grid: Color = Color(1.0, 1.0, 1.0, 0.05)
@export var rock_fill: Color = Color("222d45")
@export var rock_edge: Color = Color("354464")

@export_group("Track")
## Thick outer casing of a pipe, before and after the cart runs through it.
@export var pipe_shell: Color = Color("33456a")
@export var pipe_shell_used: Color = Color("2b3854")
## Thin bright line inside the casing.
@export var pipe_core: Color = Color("7d93bd")
@export var pipe_core_used: Color = Color("4ce0b3")
## One colour per shape, keyed by PipeDefs.Type. Used in the queue and on the
## placement ghost, where the question is "which shape is this", not "have I
## driven over it".
@export var shape_colors: Dictionary = {}

@export_group("Events")
## Whatever the location calls a fuel pickup — crystal, ember, cell.
@export var pickup: Color = Color("4ce0b3")
@export var pickup_core: Color = Color("d5fff3")
## Opacity of the shaft of light that marks a pickup from far away.
@export var pickup_beam_alpha: float = 0.07
@export var cart_body: Color = Color.WHITE
@export var cart_window: Color = Color("0d1524")
@export var cart_glow: Color = Color("4ce0b3")
@export var cart_glow_low: Color = Color("ff4d4d")
## The replay line of the player's best run.
@export var record_ghost: Color = Color(0.60, 0.72, 1.0, 0.35)

@export_group("Feedback")
## Positive, caution and failure. Also drive the HUD and the screen tints.
@export var accent: Color = Color("4ce0b3")
@export var warn: Color = Color("ffd23f")
@export var danger: Color = Color("ff4d4d")
@export var ghost_ok: Color = Color("4ce0b3")
@export var ghost_bad: Color = Color("ff4d4d")
@export var ghost_pipe: Color = Color("eafff8")
## Ring on the cell the cart needs next: one colour when the piece in hand
## fits there, another when it does not.
@export var frontier_fits: Color = Color("4ce0b3")
@export var frontier_waiting: Color = Color.WHITE

@export_group("Sprites")
## Optional artwork. Where a texture is set it replaces the drawn shape;
## where it is null the colours above are used instead, so a location can be
## pure colour, pure art, or a mix of the two.
@export var rock_texture: Texture2D
@export var pickup_texture: Texture2D
@export var cart_texture: Texture2D
## Alternative cart looks for this location. The player picks one in settings;
## empty means the single cart_texture, or the drawn cart when that is null too.
@export var cart_variants: Array[Texture2D] = []
## Pixel art needs nearest-neighbour sampling or it turns to mush when scaled
## up to cell size.
@export var pixel_art: bool = false

@export_group("Queue")
@export var slot_fill: Color = Color("15203a")


## Cart artwork for the chosen variant, wrapping if the index runs past the
## end. Null when this location draws its cart from colours instead.
func cart_art(variant: int) -> Texture2D:
	if cart_variants.is_empty():
		return cart_texture
	return cart_variants[variant % cart_variants.size()]


## How many cart looks this location offers.
func cart_variant_count() -> int:
	return maxi(cart_variants.size(), 1)


## Colour for a pipe shape, falling back to the accent if a skin forgets one.
func shape_color(type: int) -> Color:
	return shape_colors.get(type, accent)
