## A kind of player, rather than a strength of one.
##
## The proficiency dial the bot already had varies *how well* it plays. That is
## one axis, and on its own it makes every bot the same player having a better
## or worse day — which is exactly the wrong instrument for comparing
## mechanics, because a mechanic is judged by the range of people it suits.
##
## A persona varies *how* it plays: what it reaches for, what it is willing to
## throw away, how long it will wait for something better. This is the
## procedural-persona idea from the automated-playtesting literature —
## archetypes expressed as utility weights and turned loose on the game — and
## it is the cheap half of it: the weights are written down rather than
## evolved, because five hand-built archetypes answer the question we actually
## have and a search would take a week to arrive somewhere similar.
##
## The one that matters most here is the hoarder. Variant C's whole mechanic is
## banking a shape for a joint that has not arrived yet, and no bot the project
## had could do that, so C was being measured with its own mechanic switched
## off. `hoarding` is what turns it back on.
class_name Persona
extends RefCounted

## Shown in the debug bench and written into every logged row.
var name: String = "Optimiser"

## How well it plays, 0..1 — the old dial, now one trait among several.
var proficiency: float = 1.0

## Weight on climbing. The score is height, so this is how single-minded the
## persona is about the score itself.
var climb: float = 4.0
## Weight on crystals, and on turning toward them. A scavenger detours; a
## rusher drives past.
var fuel: float = 6.0
## How long it will hold a shape waiting for the joint to open, rather than
## spending it behind the cart to bring the next one up. Scales the distance it
## is willing to build ahead.
var patience: float = 1.0
## How readily it leaves a shape in a window for later, in the variants that
## keep windows. 0 spends whatever is best right now; 1 protects the shapes the
## strip would miss most.
var hoarding: float = 0.0
## Weight on speed gates, on top of how badly the cart needs one. A player who
## never looks up does not steer for them; one who has learned what they are
## plans the route around them.
var gates: float = 6.0
## Multiplier on think time. Below 1 is a fast, twitchy player.
var haste: float = 1.0
## Multiplier on the odds of simply playing the wrong cell.
var sloppiness: float = 0.0


static func make(fields: Dictionary) -> Persona:
	var persona := Persona.new()
	for key: String in fields:
		persona.set(key, fields[key])
	return persona


## The five archetypes, in the order the bench runs them.
##
## They are meant to bracket a real audience rather than to be optimal: the
## point of a persona sweep is that a mechanic which only suits the optimiser
## is a mechanic with one customer.
static func catalogue() -> Array[Persona]:
	return [
		# The phone-in-one-hand player. Slow to react, plays the first thing
		# that works, throws away anything awkward rather than waiting.
		make({
			"name": "Dabbler", "proficiency": 0.20,
			"climb": 3.0, "fuel": 3.0, "patience": 0.4, "gates": 1.5,
			"hoarding": 0.0, "haste": 1.25, "sloppiness": 1.6,
		}),
		# Height at any cost. Ignores crystals, never waits, dies with a dry
		# tank a long way up.
		make({
			"name": "Rusher", "proficiency": 0.55,
			"climb": 7.0, "fuel": 1.0, "patience": 0.3, "gates": 3.0,
			"hoarding": 0.0, "haste": 0.7, "sloppiness": 0.6,
		}),
		# Fuel first. Detours for every crystal and treats height as something
		# that happens on the way.
		make({
			"name": "Scavenger", "proficiency": 0.55,
			"climb": 2.0, "fuel": 12.0, "patience": 1.2,
			"hoarding": 0.2, "haste": 1.0, "sloppiness": 0.6,
		}),
		# Plays the strip as an inventory: keeps what the strip would miss,
		# spends what it can replace, waits rather than dumps.
		make({
			"name": "Hoarder", "proficiency": 0.85,
			"climb": 4.0, "fuel": 6.0, "patience": 1.8,
			"hoarding": 1.0, "haste": 1.15, "sloppiness": 0.3,
		}),
		# The bot as it was tuned: balanced, plans, no casual mistakes.
		make({
			"name": "Optimiser", "proficiency": 1.0,
			"climb": 4.0, "fuel": 6.0, "patience": 1.0,
			"hoarding": 0.0, "haste": 1.0, "sloppiness": 0.0,
		}),
	]


static func by_name(wanted: String) -> Persona:
	for persona in catalogue():
		if persona.name == wanted:
			return persona
	return catalogue()[catalogue().size() - 1]
