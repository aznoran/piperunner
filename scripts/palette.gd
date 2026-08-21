## Colours lifted straight from the reference prototype so the port looks
## identical. Grouped so a biome swap (spec section 11, P1) can override them.
class_name Palette
extends RefCounted

const BG_TOP := Color("111c2e")
const BG_MID := Color("0b1220")
const BG_BOTTOM := Color("070a12")

const TEAL := Color("4ce0b3")
const AMBER := Color("ffd23f")
const RED := Color("ff4d4d")

const GRID := Color(1.0, 1.0, 1.0, 0.05)

const ROCK_FILL := Color("222d45")
const ROCK_EDGE := Color("354464")

const PIPE_SHELL := Color("33456a")
const PIPE_SHELL_FLOODED := Color("2b3854")
const PIPE_CORE := Color("7d93bd")
const PIPE_CORE_FLOODED := Color("4ce0b3")

const CRYSTAL := Color("4ce0b3")
const CRYSTAL_CORE := Color("d5fff3")

const CART_BODY := Color.WHITE
const CART_WINDOW := Color("0d1524")

const GHOST_OK := Color("4ce0b3")
const GHOST_BAD := Color("ff4d4d")
const GHOST_PIPE := Color("eafff8")

## One colour per shape, so the piece in hand is recognisable at a glance
## without reading its outline. Used for the queue slots and the placement
## ghost; pipes already on the board stay on the status colours above, since
## there the important question is what has been driven over.
const PIPE_TYPE := {
	PipeDefs.Type.V: Color("4ce0b3"),
	PipeDefs.Type.H: Color("ffd23f"),
	PipeDefs.Type.UR: Color("56b8ff"),
	PipeDefs.Type.UL: Color("b07cff"),
	PipeDefs.Type.DR: Color("ff9f45"),
	PipeDefs.Type.DL: Color("ff6ea9"),
	PipeDefs.Type.X: Color("eafff8"),
}


const SLOT_FILL := Color("15203a")
const SLOT_EDGE := Color("4ce0b3")
const SLOT_EDGE_DIM := Color("2a3450")
const SLOT_PIPE_DIM := Color("5a6b90")
