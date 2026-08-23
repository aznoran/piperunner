# Which variant suits whom

Measured, not guessed — but measured with a bot, which is a proxy with known
blind spots. Both halves matter, so both are here.

## Method

`tests/variant_bench.gd` plays one variant at one standard of play across a
fixed list of seeds, so every variant meets the same boards. Nobody is given
upgrades: the shop is not what is being compared, and a bigger tank for the
planning bot would make the skill levels incomparable.

The bot's proficiency dial stands in for the player:

| Dial | Stands for | Behaviour |
|---|---|---|
| 0.20 | casual | slow to react, hesitates, plays the wrong cell now and then, takes the first shape that works |
| 0.50 | improving | quicker, fewer mistakes, still one move at a time |
| 1.00 | strong | fast, no casual mistakes, reads the strip and scores its options |

Distance is the score, so distance is the measure. `n` is 8 at casual, 6 at the
other two.

## Results

**Casual (0.20), n = 8**

| | mean | median | worst | best | how the runs ended |
|---|---|---|---|---|---|
| A queue | 22.5 | 18 | 12 | 51 | **derailed 5, off the edge 3, out of fuel 0** |
| B offer | **52.8** | **47** | **28** | 93 | out of fuel 7, derailed 1 |
| C held | 35.0 | 27 | 17 | 64 | out of fuel 6, derailed 2 |

**Improving (0.50), n = 6**

| | mean | median | worst | best | how the runs ended |
|---|---|---|---|---|---|
| A queue | 22.3 | 21.5 | 10 | 33 | out of fuel 4, derailed 2 |
| B offer | 30.8 | 29.5 | 21 | 46 | out of fuel 5, derailed 1 |
| C held | **36.7** | **35.5** | **22** | **54** | out of fuel 5, derailed 1 |

**Strong (1.00), n = 6**

| | mean | median | worst | best | how the runs ended |
|---|---|---|---|---|---|
| A queue | 33.5 | 31.5 | **23** | 49 | out of fuel 5, derailed 1 |
| B offer | **62.0** | **46** | 18 | **154** | out of fuel 5, derailed 1 |
| C held | 30.2 | 28.5 | 16 | 53 | out of fuel 3, derailed 2, off the edge 1 |

## What the numbers say

### The clearest result is not a distance, it is a cause of death

At casual, **every single A run ended with the track running out** — derailed
or off the edge, and not one out of fuel. In B and C, seven and six of eight
ended out of fuel.

That is the whole difference in one line. A casual player in A dies because the
game handed them shapes they could not use; a casual player in B or C dies
because they travelled far enough to burn a tank. The first reads as the game's
fault and invites the player to close it. The second reads as an ending they
earned and invites another go — and it is also the death the fuel economy, the
crystals and the continue offer were all designed around. In A, at casual
skill, that entire economy never gets to matter.

### The floor moves more than the mean

B's *worst* casual run is 28 cells. A's *median* is 18. A casual player's bad
day in B still beats their normal day in A.

For retention the floor is the number that counts: a player who has just been
killed at cell 12 for reasons they cannot name is the player who does not open
the app tomorrow. B roughly doubles that floor and C sits between the two.

### The offer is not easier, it is fairer

The obvious objection to B is that it simply made the game easy, and an easy
game loses players too. The death causes say otherwise. B's casual runs are not
strolls — they end at a median of 47 cells with an empty tank. The difficulty
did not go away; it moved off the draw and onto the economy, which is where a
casual game wants it. Skill in B is spending fuel well, not surviving the deck.

### B and C are not separated by this data

B wins at casual and strong, C wins in the middle, and that zigzag at n = 6 is
what noise looks like. What can be said is that both clear A comfortably below
strong play, and that C's one win is in the band where a player has started
paying attention.

## Where the bot is a bad witness

Worth stating plainly, because it bears on exactly the comparison that matters:

- **C's whole point is a skill the bot does not have.** Holding a window means
  banking an awkward shape for a joint that has not arrived yet. The bot plans
  one move ahead and takes the best shape on offer *now*; it never deliberately
  leaves something for later. So C is being measured with its main mechanic
  switched off, and its ceiling is almost certainly higher than 53.
- **The bot never gets bored, confused or annoyed.** It cannot report that A's
  four-deep preview is a lot to read on a bus, or that C's two held windows are
  invisible state a new player will not notice going stale.
- **It does not learn.** Every run is that dial's first run, so nothing here
  says how a variant feels in week two.
- **Small samples.** The A-versus-offer gap is far larger than the spread and
  is safe to act on. Anything finer — B versus C, the mid-skill zigzag — is not.

## Recommendations

### For casual players: B

The highest floor, the highest median, and the failure moved from "the game
gave me nothing" to "I ran out of road". It also asks the least: nothing to
memorise, no preview to read, no hidden state to keep straight, and a live
decision every single turn. That is the right shape for a game played one-handed
with half an eye on it.

### Who wants what

| Player | Variant | Why |
|---|---|---|
| New, casual, plays in short bursts | **B** | Highest floor. No memory load. Dies to the economy rather than to the draw. |
| Getting into it, playing longer sessions | **C** | The only variant with state to manage, so the only one that keeps paying for attention. Its mid-skill win is the one place the data hints at this. |
| Puzzle-minded, likes reading ahead | **A** | The four-deep preview and the pocket are a planning game, and rewarding for someone who wants one. |
| Chasing a big number, recording clips | **B** | The longest run measured anywhere, 154 cells, and the widest spread — which is what makes a highlight. |

### If only one ships

**B.** It is the best variant for the largest group, it is the only one whose
casual deaths are the deaths the game was designed around, and it is the
cheapest to explain: three shapes, take one. A is a planning game wearing a
runner's clothes, and its casual numbers show the cost of that. C is the most
interesting of the three and the most likely to be underrated here — but it
asks the player to notice something invisible, and the ones who would enjoy that
are the ones who would have stayed anyway.

### The hedge worth considering

B and C differ by one method. Nothing stops the game shipping B and turning on
the held windows later — as an unlock, or after a handful of runs — which gives
the casual player B's floor and the engaged player C's depth without asking
anyone to choose. That is not part of the A/B/C test, but it is the obvious
thing to do with the result.
