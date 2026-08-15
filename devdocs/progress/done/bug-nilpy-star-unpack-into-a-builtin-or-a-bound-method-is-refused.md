---
track: N
prio: 30
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "`f(1, *xs)` — a star anywhere but the first argument of a plain function — reported \"expected expression\" pointing at the operand, while the identical `obj.m(1, *xs)` worked. One construct, two spellings, one of them wired. The ticket's own table was measured wrong: bound methods were never broken; the remaining gaps are the fixed-arity builtins, re-filed."
status: done
---

# A star that is not the first argument is refused

```python
def add3(a, b, c): return a + b + c
xs = [2, 3]
print(add3(1, *xs))        # CPython 6
                           # pascal26: error: expected expression  near: print add3 1 >>> xs
```

The message names neither the star nor the callee, so it reads as a syntax error
in the caller's own code.

## What was actually broken — the ticket's table re-measured

The filed table said `zip(*m)`, `sum(*xs)` and a bound method in a variable were
refused while `f(*xs)`, `print(*xs)` and `max(*xs)` worked. Sweeping the shapes
one program at a time on the binary at HEAD, 2026-08-15:

| call shape | measured |
| --- | --- |
| `f(*xs)`, star FIRST, plain callee | works (run-time arity dispatch) |
| `print(*xs)` | works |
| `obj.m(*xs)` / `obj.m(1, *xs)` | works |
| a bound method in a variable — `h = k.g; h(*xs)` | **works** — the ticket has this wrong |
| `f(1, *xs)` — star not first | **refused**, "expected expression" — FIXED HERE |
| `zip(*m)` | refused — re-filed |
| `sum(*xs)` | refused, with its own message — re-filed |
| `max(*xs)` | **compiles, then raises at run time** — re-filed |
| `f(*xs)` into a callee that declares `*args` | refused — re-filed |

A ticket reports a symptom and names a plausible cause; this one named four, and
two of them had moved. Worth re-measuring before believing any table.

## Fix

`PyStarExpandCallArgs` — the compile-time expansion across a callee's remaining
declared slots, one `pystar_arg` read each behind a single arity guard — was
reached from the four METHOD call sites and from no plain-proc one. The plain
sites had only the first-position arm (`PyStarForwardCall`, the run-time
dispatch on `len(args)`, which is what keeps a callee's DEFAULTS working), and a
star in any later position fell into the expression parser, where `*` is not an
expression. `PyStarUnpackProcArgs` is the plain-proc twin of the method sites'
`PyStarUnpackMethodArgs` and is called from both plain call-parse sites.
`devdocs/dev/normalise-dont-special-case.md`.

Inherited from that expansion, unchanged: a callee with DEFAULTS in the starred
range is refused loudly rather than filled with None — the same trade the method
path already makes.

## Re-filed, measured, not fixed here

- [[bug-nilpy-star-unpack-into-a-fixed-arity-builtin]] — `zip`, `sum`, `max`.
  One mechanism: each is lowered at a FIXED compile-time arity, so a run-time
  count has nowhere to go. `max(*xs)` is the bad one — it compiles and then
  raises "forwarded call got 3 arguments, expected 2 to 2".
- [[bug-nilpy-star-unpack-into-a-star-args-callee]] — `f(*xs)` where `f` itself
  declares `*args`; the arm that would handle it explicitly excludes that case.

## Gate

`test/test_nilpy_star_not_first_argument.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: one and two fixed arguments before the star; a str
operand; a slice, a tuple, a call and a variant (`d["k"]`) as the operand; a
method receiver and a call from inside a method body; a nested star inside a
starred operand; and the first-position form as a control. `gate.sh quick`
GREEN. The first-position lowering stays owned by `test_nilpy_star_forward.npy`.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
