# Testing A/B/C before there are players

The experiment is built and the assignment works. Running it on day one would
still be a mistake, and the reason is arithmetic rather than taste.

## What each verdict costs, in players

**Retention.** Assuming a casual-game D1 around 30%, to call a difference
between two arms at the usual 80% power and 95% confidence — and correcting for
the fact that three arms means three comparisons:

| Lift you want to detect | Per arm | Total across three arms |
|---|---|---|
| D1 30% → 35% (very large) | 1,832 | **5,500** |
| D1 30% → 33% (plausible) | 5,015 | **15,000** |
| D1 30% → 32% (realistic) | 11,192 | **33,600** |

D7 is worse: fewer players reach it, so the same lift needs more of them.

**Behaviour.** Distance per run is continuous and each player supplies many
runs, so the same confidence costs far less:

| Comparison | Effect size | Runs per arm |
|---|---|---|
| A vs B at casual play | 0.98 | **16** |
| B vs C, hoarding player | 0.58 | **47** |
| B vs C, averaged over styles | 0.31 | **160** |

Sixteen runs an arm is two afternoons with three people. Fifteen thousand
installs is a marketing budget.

**So the two questions are not the same size, and they must not be asked at the
same time.** Everything the bots have already settled — that A is nobody's
best, that C pays only for a player who uses it — sits in the cheap column. The
expensive column contains exactly one question: does any of it move retention.

## Why three arms on day one is the wrong move

Beyond the statistics, there is a product cost. The first hundred players are
where the qualitative signal lives: the reviews, the messages, the recordings of
someone confused. Splitting them three ways means three fragmentary impressions
of three different games, none of them conclusive, and store reviews describing
a product that no single player experienced.

Running the test at a trickle also takes calendar time nobody wants to spend.
At fifty installs a day, 15,000 players is **ten months** — by which point the
game has changed under the experiment and the result describes a build that no
longer exists.

## The order to do it in

**Phase 0 — no players. Done.** Bot personas. They cost nothing, they already
ruled A out, and they found the thing worth knowing about C: it beats B for a
player who uses the held windows and loses to B for one who does not. No amount
of live traffic would have found that faster.

**Phase 1 — five to twenty people. Do this next.** Not statistics: observation.
Sit someone down, hand them the phone, say nothing, and watch. The single
question is whether anyone notices that the untaken windows stay. If nobody
does, C's whole advantage is unavailable to real players and the persona sweep
has told you why. This is precisely the question a bot cannot answer, and
twenty people answer it completely.

Worth watching for, in the same sessions: whether A's four-deep preview gets
read at all, where the phone gets put down, and whether anyone can say what the
fuel gauge is for.

**Phase 2 — first few hundred installs. Ship one variant.** B, on the current
evidence. Not to test it, but to get baselines: what *is* your D1, your median
first session, your runs per session? Every sample size in the table above is
computed from a guessed 30% D1. With a real number those become real plans
rather than illustrations.

Log everything, tag it with the variant, change nothing for a fortnight.

**Phase 3 — a thousand installs a week or better. Now run the test.** And run
it with **two arms, not three**: A is already out, so it is B against C, which
needs a third fewer players than the three-way and no multiple-comparison
correction. If the install rate never gets there, the test never becomes
affordable and the decision stays with Phase 1 and the bots — which is a
legitimate outcome, not a failure.

## The trick that makes a small sample work

Between-player variance is the dominant noise in any of this: people differ
from each other far more than a mechanic differs from another mechanic. A
**within-subject** design removes it — the same player plays both B and C, and
each is compared against themselves.

| Design | Players needed for B vs C on distance |
|---|---|
| Split sample (what is built now) | ~160 runs an arm, so 40–80 people |
| Within-subject, player-to-player correlation 0.5 | **40** |
| Within-subject, correlation 0.7 | **24** |

Twenty-four people is reachable. Forty is a Discord.

What it costs: order effects and learning. Whichever variant someone plays
second, they play with a better grip on the game, so the comparison has to
alternate the order across players and ideally within them. And it cannot
measure retention at all — a player who has seen both is not in either group
any more.

So it answers "which mechanic do people play better and longer within a
session", which is the question that is affordable, and leaves retention to
Phase 3.

**This is not what the current code does.** `Experiment` assigns one variant per
player and holds it for good, which is correct for a retention test and wrong
for a crossover. Supporting both would mean a second assignment mode — a
sequence rather than a fixed letter — with the events carrying which half of
the sequence they came from. That is a small change and a real decision, so it
is written down here rather than done quietly.

## Cheaper power, if it comes to that

- **A leading indicator instead of D7.** Something inside the first session that
  correlates with coming back — "started a third run", say. It is measurable in
  minutes rather than days, and it is far denser, so it needs a fraction of the
  sample. Calibrate it against real D1 once Phase 2 has some.
- **Sequential testing.** Fixed-sample-size tests waste players: they cannot
  stop early even when the answer is obvious. An always-valid test lets you stop
  the moment the signal clears, which on a large effect can be a third of the
  planned traffic.
- **Soft launch in one small market.** The standard mobile answer, and it buys
  the traffic without exposing the main audience to a half-tested build.
- **Buy the traffic.** If the retention verdict genuinely matters, 5,500
  installs at a typical CPI is a few thousand dollars. That is the honest price
  of the cheapest row in the first table, and it is worth knowing it is an
  option rather than a wall.

## What is ready either way

The assignment machinery does not have to be idle to be useful. Remote Config
can serve one variant to everyone from day one — the fallback already does — and
the `variant` user property tags every session correctly even when there is only
one group. So Phase 2's baselines arrive already in the shape Phase 3 needs, and
turning the test on later is a console change rather than a release.
