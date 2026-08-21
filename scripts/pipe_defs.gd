## Pipe geometry: which sides each piece opens onto, and how the cart passes
## through. Spec section 04.
class_name PipeDefs
extends RefCounted

## Sides of a cell. Note that U/D are in *board* space, where row grows upward.
enum Side { U, D, L, R }

enum Type { V, H, UR, UL, DR, DL, X }

## Returned by exit_side() when a pipe refuses the cart from that side.
const NO_EXIT := -1

const SIDES := {
	Type.V:  [Side.U, Side.D],
	Type.H:  [Side.L, Side.R],
	Type.UR: [Side.U, Side.R],
	Type.UL: [Side.U, Side.L],
	Type.DR: [Side.D, Side.R],
	Type.DL: [Side.D, Side.L],
	Type.X:  [Side.U, Side.D, Side.L, Side.R],
}

const OPPOSITE := {
	Side.U: Side.D,
	Side.D: Side.U,
	Side.L: Side.R,
	Side.R: Side.L,
}

## Board-space step for each side. row grows upward, so U is +1 row.
const DIR := {
	Side.U: Vector2i(0, 1),
	Side.D: Vector2i(0, -1),
	Side.L: Vector2i(-1, 0),
	Side.R: Vector2i(1, 0),
}

## Drop weights from spec section 04. Vertical dominates so the run can breathe.
const WEIGHTS := {
	Type.V: 24,
	Type.H: 12,
	Type.UR: 13,
	Type.UL: 13,
	Type.DR: 10,
	Type.DL: 10,
	Type.X: 8,
}

const WEIGHT_TOTAL := 24 + 12 + 13 + 13 + 10 + 10 + 8


## Where the cart leaves a pipe it entered through `entry`, or NO_EXIT if that
## side is closed. `entry` is the side of the cell the cart came in through:
## a cart travelling upward enters the next cell through its D side.
static func exit_side(type: int, entry: int) -> int:
	var sides: Array = SIDES[type]
	if not sides.has(entry):
		return NO_EXIT
	if type == Type.X:
		return OPPOSITE[entry]  # crossroads: straight through
	return sides[1] if sides[0] == entry else sides[0]


## Weighted pick. Takes an explicit RNG — spec section 11 requires deterministic
## generation for daily challenges, so nothing here may call global randi().
static func random_type(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf() * WEIGHT_TOTAL
	for type: int in WEIGHTS:
		roll -= WEIGHTS[type]
		if roll <= 0.0:
			return type
	return Type.V
