---
slug: decide-the-o-level-charter
title: "The O-level charter: a maturity ladder that drains upward, and named flags for trade-offs"
track: U
type: decision
prio: 65
status: decided
found: 2026-08-30
found-by: owner, proposing a five-level scheme and asking to be corrected
summary: "RULED 2026-08-30, amended the same day. O0 zero optimization / O1 DEBUG-SAFE optimization (our divergence: this is -Og elsewhere, unenforced until someone builds the test) / O2 proven default / O3 experimental, on track for O2 / O4 RESEARCH — correct but speculative, may never promote, and its purpose is to keep O3's drain honest. The rejected idea was O4 as the TRADE-OFF bin: 'only for certain applications' is a different axis, and those stay NAMED FLAGS because an author must choose WHICH trade, not HOW MUCH. O4 is swept on a slower cadence than the ladder, because nothing depends on it."
---

# The O-level charter

The owner proposed a five-level scheme and asked to be corrected. Three levels
were right as stated, one was right under the wrong number, and the fifth mixed
two axes. He took the correction; this is the ruling.

## The ladder — maturity, and everything in it is trying to leave

| level | meaning |
| --- | --- |
| **O0** | zero optimization, source 1:1. What makes `-g` output trustworthy. |
| **O1** | **debug-safe optimization** — optimize, but never confuse a debugger. |
| **O2** | the proven default. Debuggers mostly cope. |
| **O3** | **experimental**, staging for `-O2`. Drains upward. |

**Proof for a promotion is the owner's standing rule: self-host + all tests
passed, with no more proof available until a counterproof.** See
[[decide-the-o3-tier-is-34-percent-faster-and-nothing-gates-it]].

## O1 — the correction, and the debt it carries

The owner's definition is right and **the number is ours alone**: elsewhere this
is **`-Og`**. GCC's and Clang's `-O1` genuinely does confuse debuggers — it
coalesces variables, reorders, drops frame pointers — and `-Og` exists precisely
because people kept expecting `-O1` to be debug-safe and were disappointed.

We are redefining a slot that was in limbo rather than inventing a sixth name,
which is the cheaper move. **Two things come with it:**

1. **It is a documented divergence.** Anyone arriving from GCC will read `-O1`
   as "a bit of `-O2`" and eventually file a bug. Say it in the user docs
   before they do.
2. **"Never confuses a debugger" is a promise, and a promise needs a test or it
   decays into a label.** The testable form: **every source line remains a valid
   breakpoint, and every in-scope variable is readable at its scope.**
   `tools/pxx-gdb.py` already exists, so this is buildable. Until it is built,
   `-O1` is an intention. The first pass that quietly breaks it will not be
   noticed.

**Why it is worth having at all:** `-O0` is frequently *too slow to reproduce the
bug* — timing-dependent failures vanish under it. A debug-safe optimized level is
a working tool, not tidiness.

## `-O4` — RESEARCH, and what it is not

**Amended 2026-08-30, same day, by the owner, and the amendment is correct.**
The first ruling rejected `-O4` outright. That was right about the *trade-off*
reading and wrong about the one the owner meant.

**`-O4` is the research tier: correct, but so speculative it may never
generalize.** Optimizations nobody has tried, or that go wildly beyond the usual
shapes — the owner's example is **re-laying code out to fit a CPU cache slot**,
which is not hypothetical (BOLT and Propeller do exactly this). Such a pass may
pay enormously on one microarchitecture and nothing on another, may take years to
mature, and may simply be abandoned.

**It is the same axis as the rest of the ladder, and it PROTECTS `-O3`.** The
whole objection to the original `-O4` was that one level cannot hold two
populations that behave oppositely. That argument applies here in the owner's
favour: if speculative research sits in `-O3`, then `-O3` stops meaning *"on
track for `-O2`"* and starts meaning *"unproven, unclear"* — and its drain
property, the thing that makes promotion legible, is gone. **Separating "on track"
from "may never be anything" is the same separation, one notch further out.**

| level | correct? | expected to promote? |
| --- | --- | --- |
| `-O3` | yes | **yes** — this is staging, and it drains |
| `-O4` | **yes** | **no** — promotion is possible, never assumed |

**Both must be CORRECT.** `-O4` is not permission to be wrong: a pass that fails
`optdiff` cannot be swept at all, and an unsweepable pass is not experimental, it
is unmaintainable. *Speculative in value, never in correctness.*

### What still does NOT belong in `-O4`

**The trade-offs.** *"Only for certain applications"* in the sense of *bigger
code / worse float / longer compiles* is a different axis and stays **named
flags**, because the author must choose WHICH trade, not HOW MUCH — `-Ofast`,
`-Os`, `-funroll-loops` are sideways moves, not "more than `-O3`". A pass that is
mature and simply not universally beneficial is a **flag**, not `-O4`.

### The two guards it needs

1. **Sweep it on a slower cadence than the ladder.** The combinatorial cost is
   real — see below — but it scales with what a level *promises*, and `-O4`
   promises nothing. Nothing depends on it, so it does not need to be swept on
   every `opt` run. On demand, or at a lower frequency, is enough.
2. **A research tier becomes a graveyard by default.** Things land, nothing
   revisits, and in a year it is the backlog problem in a new place. A drain
   needs pressure: an `-O4` pass with no measurement in a long while should be
   **deleted or written up**, not left. Decide that rule when the first pass
   lands, not after the fifth.

## The cost that decides it if the principle does not

`optdiff` sweeps levels combinatorially: four levels over 1960 programs today,
and that tier is currently **549 commits behind tip**. A fifth level is ~25% more
sweep on the instrument that is already furthest behind. **A named flag does not
pay that** — it diffs against `-O2` alone.

## Consequences to act on

- **Do not add an `-O4` level.** A pass that is correct but not universally
  beneficial gets a named flag and a line in the docs.
- **Build the `-O1` debugger test, or say plainly in the docs that `-O1` is
  currently unenforced.** Do not ship the promise silently.
- **Document the `-O1`/`-Og` divergence** where users will hit it.
