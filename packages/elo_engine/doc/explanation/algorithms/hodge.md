# HodgeRank

## TL;DR — when to pick it

Enable HodgeRank when you suspect your data has **cycles or
contradictions** and you want an algorithm that will *measure* the
amount of non-transitive preference rather than paper over it.
HodgeRank is the one algorithm in the ensemble that decomposes your
match history into three components — the part that can be
explained by a single ranking (**gradient**), the part that is
rock-paper-scissors cyclic (**curl**), and the leftover topological
residue (**harmonic**) — and reports the magnitude of each. Use it
for sanity-checking whether a 1-D ranking is even meaningful for
your data, for detecting collusion/strategic voting in governance
votes, or for any situation where "is this data rankable?" is a
real question.

## The problem: cycles don't fit on a line

Suppose you have rock-paper-scissors: R beats S, S beats P, P beats
R, and each pair plays exactly once. No 1-D ranking explains this
data. If you pick any ordering — say R > S > P — then the P-beats-R
observation is an inversion. Any algorithm that tries to force a
linear ranking on this data is going to be lying, in a very
specific technical sense.

HodgeRank admits the lie and measures it.

## The physical analogy: flows on a graph

Think of your match data as a **flow** on a graph. For each pair of
items $(i, j)$, compute a single number $y_{ij}$ — call it the
"edge flow" — that summarizes how often $i$ beat $j$ versus the
other direction. A common choice is the **log-odds**:

$$ y_{ij} = \log \frac{w_{ij} + \alpha}{w_{ji} + \alpha} $$

where $w_{ij}$ counts wins of $i$ over $j$ and $\alpha$ is a small
smoothing constant. Positive $y_{ij}$ means $i$ tends to beat
$j$; negative means the reverse; zero means even.

`elo_engine` itself uses a simpler flow, the centred win rate
$y_{ij} = w_{ij} / n_{ij} - 0.5$, where $n_{ij}$ is the number of
non-skip matches between the pair. The ideas below are the same for
either choice.

So now you have a bunch of signed flows, one per edge in the
observed match graph. HodgeRank asks: **can this flow be explained
by a ranking?**

A flow is **explainable by a ranking** if there is a function
$s_i$ (the "potential" — the rank score) such that $y_{ij} = s_i
- s_j$ for every edge. In physics terms, the flow is the
**gradient** of a scalar potential. In voting terms, the flow is
consistent with a single linear ordering.

If such an $s$ exists and fits exactly, the data is perfectly
rankable. If it doesn't fit exactly, you want the closest-to-fit
$s$ — which turns out to be a least-squares problem — and the
**residual** is the part of the flow that no ranking can explain.

## The Hodge decomposition

Here is the beautiful result: **any edge flow** on a graph
decomposes uniquely into three orthogonal pieces:

1. **Gradient component**: the flow $s_i - s_j$ of the best-fit
   potential. This is what a 1-D ranking can see.
2. **Curl component** (also called "cyclic"): the part of the flow
   that loops around triangles in the graph. Rock-paper-scissors
   triangles live here.
3. **Harmonic component**: leftover flow that is neither a gradient
   nor a triangle loop. In graphs with non-trivial topology (holes,
   tunnels), the harmonic part can be nonzero; on simple graphs, it
   is usually zero or very small.

The three components are **orthogonal** in the sense that their
inner products are zero, and the decomposition is unique. This is
the **Hodge-Helmholtz theorem** from differential geometry,
specialized to graphs. The fact that combinatorial graphs have a
clean version of this theorem is one of the most elegant results
connecting topology to data.

## Worked example

Three items, rock-paper-scissors, one match each way:
- A beat B once, B never beat A.
- B beat C once, C never beat B.
- C beat A once, A never beat C.

Edge flows (using the log-odds with smoothing):
- $y_{AB} = \log((1 + 0.5)/(0 + 0.5)) = \log 3 \approx 1.1$
- $y_{BC} = \log 3 \approx 1.1$
- $y_{CA} = \log 3 \approx 1.1$

Sum around the triangle $A \to B \to C \to A$: $1.1 + 1.1 + 1.1 = 3.3
\neq 0$. This nonzero sum is the **curl** of the flow around the
triangle — it's a signature that the flow circulates rather than
flows from high to low.

HodgeRank will now:
1. Find the best-fit potential $s_i$. For a perfect cycle, the
   best fit is $s = (0, 0, 0)$ — no ranking, total tie.
2. Compute the gradient residual: what's left over? Everything,
   because the gradient is zero and the data flows nontrivially.
3. Decompose the residual into curl + harmonic. For a triangle,
   the full residual is curl.

Result: `gradientRanking` is a tie (or near-tie). `cyclicMagnitude`
is large. `harmonicMagnitude` is near zero. **This is
HodgeRank reporting that the data is not rankable** — and telling
you *why* (it's cyclic, not just noisy).

## What you do with the output

`RankingComparison.hodge` is a `HodgeResult` with three fields:

- **`gradientRanking`**: the best 1-D ranking, as a sorted list of
  items. This is what you show users when you want to act on the
  data despite the cycles.
- **`cyclicMagnitude`**: a scalar in $[0, 1]$ that tells you how
  much of your data looks like rock-paper-scissors. In `elo_engine`
  it is the share of the observed flow that the gradient ranking
  leaves unexplained (the square root of residual energy over flow
  energy). The code does not split that residual into curl and
  harmonic parts, so all of it is counted here. Large values are a
  warning: your users are producing non-transitive preferences, and
  any single ranking is partially fabricated. If this is big,
  consider showing "we detected disagreement" in your UI.
- **`harmonicMagnitude`**: in `elo_engine` this is a coverage
  measure, the fraction of item pairs that have not been compared
  yet (0 = every pair compared, 1 = no comparisons). It is a
  stand-in for the harmonic component and is not a projection onto
  it. A high value means the other two outputs rest on little data.

A useful rule of thumb: if `cyclicMagnitude` is more than, say, 0.1
(it is already a fraction of the total flow), your data is
meaningfully cyclic. Use
SerialRank (see [`serial-rank.md`](serial-rank.md)) to get a second
opinion on rankability.

## The math, one level deeper

The Hodge decomposition comes from writing the flow as a vector in
edge space and projecting onto three orthogonal subspaces:

- **Gradient space**: flows of the form $s_i - s_j$.
- **Curl space**: flows that sum to zero around every triangle.
- **Harmonic space**: the orthogonal complement.

Computing the gradient projection is a least-squares problem:
minimize $\sum_{ij} (y_{ij} - (s_i - s_j))^2$ over $s$. This
reduces to solving a Laplacian system — $L s = d$ where $L$ is the
graph Laplacian and $d$ is the divergence of the flow. `elo_engine`
solves this by Gaussian elimination, after adding a small ridge
term (0.001) to the Laplacian's diagonal.

The curl component is then the triangle-closure part of the
residual, computed by projecting onto triangle cycles and
(implicitly) separating from the harmonic component. `elo_engine`
does not take this last step: it reports the size of the whole
residual as `cyclicMagnitude`.

This is a gorgeous piece of applied algebra that comes from
combining three classic ideas: the Hodge decomposition in
differential geometry, spectral graph theory, and paired-comparison
statistics. HodgeRank was introduced by Jiang, Lim, Yao, and Ye in
2010 and has since become the standard tool for detecting
"irreducibility" in preference data.

## Failure modes

**Sparse graphs.** The triangle-cycle space is only meaningful if
you have triangles — three items that have each played each other.
Very sparse match graphs (a few edges) have trivial cycle
structure and HodgeRank's curl term will be near zero regardless of
whether the data is cyclic in spirit.

**Noisy data conflated with cycles.** HodgeRank does not distinguish
"true non-transitivity" from "noise that happened to look like a
cycle". A fat cyclic component could be a real phenomenon or could
be noise. For sparse data, prefer SerialRank or just report the
number of matches per pair and let the user decide.

**Unseen pairs.** `elo_engine` builds the Laplacian and the
divergence vector from observed pairs only, so a pair that was never
compared adds nothing to the fit, and a small ridge term (0.001)
keeps the system solvable when items are isolated. If you see
unstable gradient rankings, check match density first.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when `AlgorithmId.hodge` is
  enabled.
- Exposed as `RankingComparison.hodge`, a `HodgeResult` with
  `gradientRanking`, `cyclicMagnitude`, and `harmonicMagnitude`.
- Solves the ridge-regularized Laplacian system by Gaussian
  elimination; cost is $O(N^3)$. There is no pass over triangles.
- The gradient ranking is what appears in the consensus; the
  magnitudes are read-only metrics for you to interpret.

## One-sentence summary

HodgeRank decomposes your pairwise match flow into a ranking part,
a cyclic part, and a topological residue — the only algorithm in
the ensemble that tells you *how rankable* your data is rather than
just producing a ranking.
