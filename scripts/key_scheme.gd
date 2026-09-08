## Which keys pick which shape off the strip.
##
## The keyboard only chooses; the pointer still places. That split is the whole
## design: choosing is free and repeatable, placing spends the turn (see
## Main._on_offer_chosen), and the two wanted different hands on a desktop the
## same way they want different fingers on a phone.
##
## Three home-row-ish layouts and the digits, because which one is comfortable
## depends on where the other hand is — a player driving the mouse right-handed
## reaches for A S D, a left-handed one for the arrows, and neither is a
## default worth arguing for. The strip draws whichever is chosen onto the
## slots, so the setting explains itself the moment a run starts.
class_name KeyScheme
extends RefCounted

## Order matters: it is the index stored in GameState and shown in the picker.
enum Id { QWE, ASD, ARROWS, DIGITS }

## Names for the settings picker.
const NAMES: Array[String] = ["Q W E R", "A S D F", "← ↓ → ↑", "1 2 3 4"]

## Slots are read left to right, so the fourth entry is the one an upgrade
## widens the offer into — four is the most the strip is ever dealt.
const KEYS: Array = [
	[KEY_Q, KEY_W, KEY_E, KEY_R],
	[KEY_A, KEY_S, KEY_D, KEY_F],
	[KEY_LEFT, KEY_DOWN, KEY_RIGHT, KEY_UP],
	[KEY_1, KEY_2, KEY_3, KEY_4],
]

## What each key is called on the slot it picks. The arrows are drawn as
## glyphs rather than spelled out: a cap is a few pixels wide.
const CAPS: Array = [
	["Q", "W", "E", "R"],
	["A", "S", "D", "F"],
	["←", "↓", "→", "↑"],
	["1", "2", "3", "4"],
]

## Also accepted, always, whichever scheme is chosen. The number row is what a
## player tries first without being told, and refusing it to protect a setting
## nobody has opened yet would be a small piece of rudeness.
const UNIVERSAL: Array = [KEY_1, KEY_2, KEY_3, KEY_4]


static func clamp_id(scheme: int) -> int:
	return clampi(scheme, 0, NAMES.size() - 1)


## The slot `keycode` picks, or -1 if it picks none. `slots` is how many the
## strip is showing, so a fourth key does nothing until the offer is that wide.
static func slot_for(scheme: int, keycode: int, slots: int) -> int:
	var row: Array = KEYS[clamp_id(scheme)]
	for i in mini(slots, row.size()):
		if row[i] == keycode:
			return i
	for i in mini(slots, UNIVERSAL.size()):
		if UNIVERSAL[i] == keycode:
			return i
	return -1


static func cap(scheme: int, index: int) -> String:
	var row: Array = CAPS[clamp_id(scheme)]
	return String(row[index]) if index < row.size() else ""
