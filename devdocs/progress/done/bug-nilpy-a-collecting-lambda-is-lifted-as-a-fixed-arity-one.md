---
track: N
prio: 40
type: bug
blocked-by: []
resolved: PENDING-COMMIT
summary: "`lambda *a: len(a)` — the lifter's parameter loop skipped the `*` outright, so `a` became an ordinary parameter and `f(1, 2)` raised \"TypeError: <lambda>() takes 1 positional argument but 2 were given\" on a form CPython accepts. The star position now rides the bound-fn object and the bridge packs."
---

# A collecting lambda

```python
f = lambda *a: len(a)
print(f(1, 2))        # CPython 2
                      # pxx  TypeError: <lambda>() takes 1 positional argument
                      #      but 2 were given
```

Measured 2026-08-15, the sibling of
[[bug-nilpy-a-star-args-def-taken-as-a-value-is-called-with-loose-arguments]]
and found by the same sweep. Same concept, the OTHER callable representation:
a lambda lifts through `pyboundfn_*` (pyeval's word-based bridge), not through
the `pybound_new` pair.

## Root cause

The lifter's header loop matched only `tkIdent`; a `tkStar` fell through to the
`Next` at the bottom, so `*a` was indistinguishable from `a`. The lifted proc
then declared ONE Variant parameter, `pyboundfn_setdefaults` published that as
the legal arity, and the arity check — correctly, given what it had been told —
refused every call with more than one argument. Loud rather than silent, which
is the one thing this shape had going for it.

## The fix

`pyboundfn_setstar(obj, si)`, chained after `pyboundfn_setown` exactly as the
other setters are. It records the own-parameter index that COLLECTS, and that
one field carries both halves of the semantics:

- `pyboundfn_callvn` packs arguments `si..nargs-1` into a `TPyList`, marks it a
  TUPLE (as `PyPackStarArgs` does at a written call site) and writes the
  pointer into the word slot the loop had filled with the first surplus
  argument;
- `PyBoundFnArityBad` reads it as "at least `si` arguments, no ceiling" — a
  default written after `*` is keyword-only in Python and can never be supplied
  positionally, so there is no positional-override arrangement to make either
  and `setdefaults` is not emitted at all for this shape.

Frontend side: the star parameter is typed `TPyList` (the same type the def
header gives `*args`), `ProcPyStarIdx` is recorded on the lifted proc, and
`pyboundfn_setstar` joins the three callable-CONSTRUCTOR name lists. Missing
that last step is worth remembering: the chain's final node is what gets boxed,
so an unlisted setter made the whole lambda box as a plain integer and the call
died with "object is not callable" — a symptom nowhere near the change.

## What is still open

- `lambda **kw:` still does not compile (`undefined variable`). Two `tkStar`
  tokens are deliberately NOT treated as a star here, so that shape is exactly
  as it was.
- Star position > 3 keeps the bridge's existing three-argument ceiling.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v333.
`test/test_nilpy_lambda_star_args.npy`, byte-identical to CPython: arity 0..3,
the tuple the body sees, fixed parameters before the star, a lambda passed as
an argument, and one with a capture as well as a star. Re-checked the nine
existing star/callable `.npy` tests against their oracles.
