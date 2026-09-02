# Dealing for the path, and what measuring it found

`PathDealer` replaces the even draw with two rules that both aim at the same
scarcity from opposite ends. This is what they are, what they cost, and what a
bot sweep did and did not manage to say about them.

## The arithmetic they are answering

Seven shapes, three on the strip, drawn without repeats. What that gives depends
entirely on which side the cart arrives from, and the difference is not
something a player could read off the rules.

| Cart is | Shapes that fit | Carry the path on | Resume the climb |
|---|---|---|---|
| climbing (from below) | V, DR, DL, X | all four | V, X |
| crossing (from the side) | H, UL, DL, X | H, UL, X | **UL alone** |
| descending (from above) | V, UR, UL, X | UR, UL | none exist |

Read down the last column. Climbing on, two shapes of seven keep the climb, so
an offer of three holds one 71% of the time. The moment the cart turns, exactly
one shape of seven gets it climbing again — 43%. Turning costs nearly thirty
points of that, every time, and nothing on screen says so.

## The turn rule

With probability `path_turn_chance`, once the cart is off its climb, **one cell
of the offer** — picked at random — is drawn from the shapes that carry the
path on. The other two keep whatever the even draw gave them. Within that draw
the shape that resumes the climb takes `path_straight_share` of it.

Which shapes those are comes from the geometry rather than a list, so it
follows the corner the player actually turned:

    placed DR -> cart leaves right -> joint needs L -> H, UL, X   (UL climbs)
    placed DL -> cart leaves left  -> joint needs R -> H, UR, X   (UR climbs)

Zero is off and leaves the even draw untouched.

**One cell, not all of them.** The first version chose every cell from a pool,
and it saturated: for a sideways cart the carrying shapes are exactly three,
which is exactly the size of the strip, so a high chance stopped dealing an
offer and started dealing that same fixed set every turn. Two of those three
carry the cart further sideways and only one climbs, so guaranteeing "carries
on" guaranteed mostly "keeps crossing" — and because the whole pool landed on
the strip, `path_straight_share` had nothing left to weight and went inert at
exactly the settings where it was needed. The bots showed it: the group at 0.95
shifted its cause of death from fuel to derailment, five runs in twelve against
the control's one, the cart crossing the board until it ran out of room.

Claiming one cell removes all of that. The other two stay an honest draw
however hard the knob is turned, and the check suite now asserts it — at 1.0
the strip still comes up in more than ten different combinations rather than
one.

The rule says nothing while the cart is climbing. Arriving from below, every
shape that fits carries on, so there is no split to weight; biasing the draw
there would not favour carrying on, it would favour the shapes that do not fit.

## The pity rule

Same shape: when it fires it claims one random cell. What differs is when it
fires. Every deal that lands with nothing worth having raises the odds the next
one is given something, and any deal that carries resets it.

    urge = tanh(path_pity_strength · barren_deals)

A sigmoid rescaled to start at zero — `2·σ(2kn) − 1` is exactly `tanh(kn)`.
Zero on a strip that has just served the player, and within a percent of
certain after a few barren deals, with the strength deciding how few. A curve
rather than a counter on purpose: "every fifth deal" is learnable, and a player
counting to the rescue has stopped playing the game in front of them.

It rescues from the **second** consecutive barren deal on — the streak that
earns the odds is the one before this deal, not this one. That is what "not
turning up for a while" means, and it is why the rule is quiet while the cart
climbs: an even draw is barren 29% of the time there, so two running is about
8% of deals.

What it holds out for is the *scarce* continuation rather than any of them: the
shape that keeps the cart climbing or puts it back there, falling back to
anything that does not deepen a descent only where no shape can climb at all.
Watching for merely-carrying shapes would leave the rule idle — a sideways cart
is handed one of those 89% of the time by luck alone, so a streak long enough
to matter would never form.

Unlike the turn rule this one works whether or not the cart has turned.

## The knobs

| | range | ships at |
|---|---|---|
| `path_turn_chance` | 0.00 – 1.00 | 0.00 |
| `path_straight_share` | 0.00 – 1.00 | 0.70 |
| `path_pity_strength` | 0.00 – 2.00 | 0.00 |

All three are live sliders on the debug bench, under Dealer.

## The sweep

`tests/dealer_bench.gd`, five groups, the mechanic held still at variant B so
that what moves is the dealing rule and nothing else. Thirty fixed boards — the
first sweep ran twelve and could not resolve anything under about fifteen
cells, which was most of what it established. Two personas: Dabbler at
proficiency 0.20 and Optimiser at 1.00.

| group | turn | pity | |
|---|---|---|---|
| A | 0.00 | 0.00 | control — both rules off |
| B | 0.90 | 0.00 | the turn rule alone, near its ceiling |
| C | 0.00 | 1.20 | the pity rule alone, biting after one barren deal |
| D | 0.60 | 0.60 | both, middling |
| E | 0.30 | 0.25 | both, gentle |

**n = 30 a cell. `t` is the difference from the control in standard errors.**

| | Dabbler mean | median | t | Optimiser mean | median | t |
|---|---|---|---|---|---|---|
| A | 37.3 | 41.5 | — | 44.1 | 39.5 | — |
| B | 43.7 | 40.0 | +1.60 | 44.2 | 40.0 | +0.04 |
| C | 44.6 | 39.0 | +1.66 | 46.6 | 44.0 | +0.62 |
| D | 44.5 | 40.5 | +1.53 | 51.0 | 45.0 | +1.31 |
| E | 33.9 | 32.0 | −1.13 | 52.3 | 45.5 | +1.60 |

**Pooled over both personas, n = 60**

| | mean | median | vs control |
|---|---|---|---|
| A | 40.7 | 40.5 | — |
| B | 44.0 | 40.0 | +3.3 (1.13 se) |
| C | 45.6 | 42.0 | +5.0 (1.63 se) |
| **D** | **47.8** | **43.0** | **+7.1 (1.98 se)** |
| E | 43.1 | 38.5 | +2.4 (0.75 se) |

## What it says

**The reshape worked.** The derailment signature is gone: B at Dabbler ran five
derailments in twelve under the old design and five in thirty now, which is the
control's rate. No group any longer pushes the cart across the board, and that
is a mechanical result rather than a statistical one — the arithmetic above
says why it could not have survived the change.

**D is the first thing here that looks like an effect.** It is positive under
both personas, the only group that is, and pooled it sits at 1.98 standard
errors — nominally p ≈ 0.05. That is *suggestive and not established*, for
three reasons worth stating rather than burying:

* Four groups were compared against one control. Correcting for that, a
  nominal 0.05 becomes about 0.18, which is nothing.
* The distributions are heavily right-skewed. D's mean is carried by two runs
  of 122 and 130; its median is 43.0 against the control's 40.5, a far smaller
  gap than the means suggest.
* E flips sign between personas — −3.4 for the Dabbler, +8.2 for the Optimiser.
  A rule that helps one and hurts the other at gentle settings and helps both
  at middling ones is not a story; it is noise with a plausible shape.

**Both rules together beat either alone**, weakly and consistently: D is above
both B and C under both personas. If there is a real effect it is in the
combination, which is what the two were designed for — the turn rule reshapes
the moment the cart is knocked off its climb, the pity rule catches the streaks
the turn rule's single roll leaves behind.

## What ships

Group D, by decision rather than by proof: `path_turn_chance` 0.60,
`path_pity_strength` 0.60, `path_straight_share` 0.70. It is the only group
that came out ahead under both personas, and the two rules together beat either
alone — but at 1.98 standard errors across four comparisons that is a
judgement call, and it is worth writing down as one rather than dressing it up.

The evidence would be settled by **A against D and nothing else**. One
comparison instead of four removes the multiplicity problem, and at the spread
these runs show, n ≈ 100 a group resolves a seven-cell difference cleanly —
about two hours of bench with both groups side by side, and a seed list of a
hundred rather than thirty. Until that runs, the shipped setting is a bet on a
weak signal that at worst costs nothing.

Backing it out is two lines in `GameBalance.tres`:

    path_turn_chance = 0.0
    path_pity_strength = 0.0

## A note on the export filter

The iOS export writes app icons into `build/ios/`, Godot imported them back as
project assets, and the next export packaged them into the game — eighteen
files and about 53 KB, growing with every build. Neither preset excluded its
own output. Both now carry `build/*` in `exclude_filter`, and two exports in a
row produce byte-identical packages, which is the check that the loop is shut.
