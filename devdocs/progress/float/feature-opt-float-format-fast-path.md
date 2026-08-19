---
track: O+F
prio: 30
type: feature
blocked-by: []
summary: "Fixed-point float formatting is 4.7x slower since it started taking its digits from the double's exact decimal expansion (8.8us vs 1.85us per %.2f, measured over 200k). Correct now, and worth a fast path for the values that provably cannot sit near a midpoint."
---

# A fast path for fixed-point float formatting

- **Type:** optimization — **Track O** (Track A file ownership:
  `compiler/builtin/pylib.pas`)
- **Opened:** 2026-08-13, by the fix for
  [[bug-nilpy-float-formatting-manufactures-ties-by-scaling]], which is what
  made it slower and is not to be undone.

## Measured

200,000 `"%.2f" % (i / 7.0)` in a NilPy loop, same box, same program:

| binary | wall |
| --- | --- |
| pinned (scaled arithmetic, WRONG for midpoint-adjacent values) | 0.37 s |
| HEAD (exact decimal expansion) | 1.76 s |

So ~1.85us -> ~8.8us per format. Correctness first: the old path printed
`0.2` for `"%.1f" % 0.15` where CPython prints `0.1`, and got the error in both
directions, so this is a cost that was paid for something.

## Why it costs what it does

`PyExDecDigits` expands the mantissa into the FULL exact decimal expansion —
for a value with a large negative binary exponent that is dozens to hundreds of
digits, built one at a time into an AnsiString — and the formatter then keeps a
handful of them. The work is proportional to the expansion, not to `prec`.

## Where the fast path is

Not a guard band on the scaled arithmetic: "the remainder is not near 0.5" is
exactly the judgement the bug was about, and a band wide enough to be safe for
large values is wide enough to catch real values. Two directions that are
actually provable:

1. **Stop the expansion early.** The formatter needs `decExp + 1 + prec` digits
   plus enough to decide the round (one digit, plus whether any nonzero digit
   follows). `PyExDecOfMant` could take a digit budget and stop, with a "rest
   is nonzero" flag — the same information `PyExDecRound` already computes by
   scanning the tail. That keeps the answer exact and makes the cost
   proportional to `prec`.
2. **A power-of-two shortcut.** A double whose exponent makes it an exact
   multiple of 10^-prec (all the x.5, x.25, x.125 cases, and every integer)
   cannot be near a midpoint by construction, and its digits are the scaled
   integer. Cheap to test on the mantissa's trailing zero count.

(1) is the general one and probably the whole job.

## Gate

The `bug-nilpy-float-formatting-manufactures-ties-by-scaling` test still exact
(it carries the midpoint rows), the dense sweep in that ticket still matching
CPython, and the benchmark above back under ~2x of pinned.
