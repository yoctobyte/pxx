---
slug: decide-the-o-level-charter
title: "The O-level charter: a maturity ladder that drains upward, and named flags for trade-offs"
track: U
type: decision
prio: 65
status: decided
found: 2026-08-30
found-by: owner, proposing a five-level scheme and asking to be corrected
summary: "RULED 2026-08-30. O0 zero optimization / O1 DEBUG-SAFE optimization (our divergence: this is -Og elsewhere, and it needs a test or it is only a label) / O2 proven default / O3 experimental, staging for O2. NO -O4 maturity tier: 'only for certain applications' is a TRADE-OFF, not a maturity stage, and mixing the two axes puts draining and permanent passes in one level where neither can be told apart. Permanent trade-offs are NAMED FLAGS, because an author must choose WHICH trade, not HOW MUCH."
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

## No `-O4` maturity tier — the axis error

The proposal used the number for **maturity** (experimental → very
experimental). But *"only for certain applications"* is a **trade-off**, not a
maturity stage, and the two axes behave in opposite ways:

- a pass on its way up should **drain** out of its level;
- a pass that is only right for some programs **never moves**, because moving
  was never the point.

Put both in one level and **you cannot tell by looking which kind you are
holding.** The permanent residents make the pipeline look stuck; the young
passes inherit "this may never promote" and stop being chased. That is the same
two-jobs-in-one-field conflation `owner:` and `working/` carried until they were
untangled the same day.

**Second reason, and it is the user-facing one:** *"level 4"* does not tell an
application author what they are buying. Bigger code? Worse float accuracy?
Longer compile times? **They must choose WHICH trade, not HOW MUCH.** Every real
toolchain expresses these sideways rather than upward for exactly this reason —
`-Ofast` breaks IEEE, `-Os`/`-Oz` trade speed for size, `-funroll-loops` trades
cache for branches. None of them is "more than `-O3`".

**So: permanent trade-offs are NAMED FLAGS.** If a bundle is ever wanted, `-O4`
may exist as a **documented bundle of those flags** — never as a tier, and never
as somewhere passes wait.

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
