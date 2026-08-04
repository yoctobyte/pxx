---
track: N
prio: 45
type: bug
summary: "abs() of a negative INTEGER EXPRESSION returns the value unchanged — abs(0 - i) is -5, not 5"
status: done
owner: claude-AN
---

# `abs()` of a negative integer expression returns it unchanged

```python
i = 5
print(abs(0 - i))     # CPython: 5      pxx: -5
print(abs(i))         # CPython: 5      pxx: 5   (correct)
```

Found by the promo output-diff sweep
([[task-n-enumerate-the-promo-surface-by-output-diff]]) and confirmed to be
**independent of promotable ints**: it reproduces with the promotion default
OFF and with a plain `tyInteger` operand, so it is not part of that arc. Filed
separately rather than folded in.

## Why it matters more than the one-liner suggests

`abs()` on an already-positive value is correct, so a test that only checks
`abs(5)` is blind to this. The failing shape is the one that actually appears
in code — a difference, a delta, an error term — and it returns a NEGATIVE
number where Python guarantees a non-negative one. Anything that then compares
against a tolerance (`if abs(a - b) < eps`) silently takes the wrong branch,
which is the "plausible wrong value far from the cause" failure mode, not a
crash.

## Where to look

The `abs` intrinsic's lowering, for whether it is emitting a conditional
negate at all when the argument's static type is an integer EXPRESSION rather
than a simple load. Diff the IR of `abs(i)` against `abs(0 - i)`
(`PXXDBG=a.ir:<proc>`).

## Gate

Per-fix loop. Add a `.npy` test covering `abs()` over a negative expression, a
negative literal, a negative float and a promo — check `ls test/ | grep abs`
first for an existing file to extend.

## CORRECTION 2026-08-04 — this was NOT pre-existing; it was a promo regression

The filing above says it "reproduces with the promotion default OFF". **That was
wrong, and the way it was wrong is worth recording:** the check was run in a
session that had ALREADY applied the promotable-int default, and it "removed the
promo" by rewriting `i + 1` to `i` — which does nothing for `abs(0 - i)`, whose
promo comes from the `0 - i` subtraction, not from the edited part. So the
"without promo" run still had a promo argument.

Verified properly against `stable_linux_amd64/default/pinned`: `abs(0 - i)`
answers **5** there and **-5** at HEAD. A regression, introduced by the default.

Same lesson as the ticket this came from: **check the thing you think you are
checking.** A control that does not actually remove the variable under test is
worse than no control, because it launders a regression into a pre-existing bug.

## Root cause

The `Abs` intrinsic hand-builds its call and picks `__pxxAbsInt` for anything
non-float ([[project_findproc_by_name_ignores_overloads]]). A promo argument
therefore arrived as its **slot ADDRESS** — a positive pointer — so the sign was
never inspected and the value came back unchanged.

Fixed by routing a promo argument to `pyabs_v` (Variant parameter, boxes
losslessly), which gained a `VT_PROMO_INT64` arm: the payload IS the exact
decimal, so the absolute value is that text minus its leading `-`. Reading it as
a machine int first would narrow mod 2^64, which is the whole reason the tag
exists.

## Log
- 2026-08-04 — resolved, commit PENDING-COMMIT.
