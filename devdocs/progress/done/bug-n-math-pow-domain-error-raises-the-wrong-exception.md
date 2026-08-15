---
track: N
prio: 25
type: bug
summary: "Every math domain error in NilPy raises `ZeroDivisionError: division by zero` where CPython raises `ValueError: math domain error` — sqrt(-1), log(-1), log(0) and pow(-8, 0.5) all of them, and the same call compiled as PASCAL returns Nan without raising at all. Three behaviours for one operation; a CPython program's `except ValueError:` catches none of ours."
status: done
owner: agent-AN
---

# Every math domain error is a ZeroDivisionError

- **Type:** bug (upward-compatibility divergence) — **Track N**.
- **Found:** 2026-08-14, sweeping edge cases while landing `math.pow`
  ([[bug-n-math-trunc-and-log-need-frontend-intercepts]]).

## Measured — one mechanism, not four bugs

Compiled at HEAD and run, against CPython on the same box:

| call | pxx (NilPy) | CPython |
| --- | --- | --- |
| `math.sqrt(-1)` | `ZeroDivisionError: division by zero` | `ValueError: math domain error` |
| `math.log(-1)` | `ZeroDivisionError: division by zero` | `ValueError: math domain error` |
| `math.log(0)` | `ZeroDivisionError: division by zero` | `ValueError: math domain error` |
| `math.pow(-8, 0.5)` | `ZeroDivisionError: division by zero` | `ValueError: math domain error` |

All four give the SAME message, so this is one site, not four.

And the third behaviour, which is the useful clue:

```pascal
program p; uses math;
begin WriteLn(Sqrt(-1.0)); end.     { prints ` Nan`, raises nothing }
```

The same RTL routine, reached from Pascal, returns a quiet NaN. So the
difference is on the NilPy side of the call, not in `Sqrt`.

## Cause: NOT yet located — do not trust a guess here

Two theories were checked and **both are wrong**, which is why they are written
down rather than left for the next person to re-derive:

- *"NilPy unmasks the FPU invalid-operation exception and the SIGFPE handler
  reports it."* Unmasking is `--fpc-float-errors` only (`FpcFloatErrors`,
  default False, opt-in since 2026-07-02), and that path prints an FPC runtime
  error 207, not a Python exception.
- *"sysutils' `PXXDivZeroHook` turns the trap into an exception."* That hook
  raises `EDivByZero` with the message `Division by zero` — capital D. Ours is
  lowercase `division by zero`, which is pylib's own text
  (`pylib.pas:7770` / `:7904`, the two float/int true-division guards).

The lowercase message says a **pylib division guard** is what fires, so
something on the NilPy path is dividing — but `math.sqrt` is not in the stdlib
call table at all, so where it lands was not established. Start by dumping the
AST/IR of a def wrapping `math.sqrt(-1.0)` (`PXXDBG=a.ir:<proc>`) and reading
which proc the call node names; do not reason about it.

## Why it is worth a ticket at prio 25

No wrong VALUE: every route refuses. But the exception TYPE is observable, and
`try: ... except ValueError:` is exactly how CPython code guards these calls, so
a working CPython program catches none of ours — the upward-compatibility rule.
The message is also actively misleading: nothing divided by zero.

Priced at 25 because a refusal that is loud and catchable-as-Exception is a far
smaller harm than a wrong number.

## Scope

Fix the ONE site, not `pow`. The table above is the gate: all four rows, plus
`math.asin(2)` / `math.acos(2)` once those names exist at all (they are
currently `undefined variable` — a separate small gap worth folding into the
same test).

## Resolution (2026-08-15) — the cause was NOT in math at all

The ticket's own instruction was right: dump what the call lands on rather than
reason about it. The lowercase `division by zero` was the clue it said it was,
and it points somewhere much wider than `math`.

`math.sqrt` lowers to the RTL's `Sqrt` (`lib/rtl/math.pas:177`), whose
FPC-faithful NaN idiom is written

```pascal
if x < 0.0 then begin z := 0.0; Result := z / z; Exit; end;
```

**That `z / z` was being compiled as a PYTHON true-division.** The intercepts in
`ir.inc` that give `/`, `//` and `%` their Python semantics are gated on
`PyProgramMode`, which is true for the WHOLE compilation — including the Pascal
RTL units an `import` drags into it. So `z / z` became a `pytruediv_f` call,
which raises `ZeroDivisionError` on a zero divisor. Same for `Ln`'s `-1.0 / z`.

That also explains the three behaviours the ticket found so puzzling: the same
`Sqrt`, reached from a Pascal program, has no intercept and returns its NaN.

It is worse than a wrong exception type, and this is the part that made it a
Track A fix rather than a math patch: **every `div` and `mod` in an imported RTL
unit silently acquired Python's FLOOR rule** — `(-7) div 2` is -3 in Pascal and
-4 in Python — so any RTL routine doing negative integer division inside a NilPy
program computed a different number than the same routine in a Pascal program.
No test covered that, and nothing would have reported it.

### The fix

`ASTPyUser`, a new parallel AST array recording `NilPyUserCode` at each node's
BIRTH — the only point where the unit context still exists (by IR lowering it is
long gone). The fourteen Python-semantics binop intercepts now ask
`PyNodeIsUser(node)` instead of `PyProgramMode`. `NilPyUserCode` is already the
repo's predicate for "code the NilPy user wrote", covering both the `.npy`
program and an imported `.py` module — verified: a `//` inside an imported
module still floors, and the RTL's does not.

A new parallel array rather than a TSymbol/record field, per
[[project_tsymbol_field_landmine]]; grown in `EnsureASTCapacity` with its
siblings and copied by `CloneAST`, which is where a missed one is a silent
out-of-bounds.

### ...and then the domain errors, which are a separate half

With the RTL restored to Pascal semantics, `math.sqrt(-1)` answers `nan` — right
for Pascal, still wrong for Python. CPython REFUSES its domain errors, so four
argument guards in pylib (`pymath_dom_nonneg` / `_pos` / `_unit` / `_pow`) raise
`ValueError('math domain error')`, wrapped around argument 0 in
`PyParseStdlibCall`.

On the ARGUMENT, not the result, and that is load-bearing: `math.sqrt(nan)` is
`nan` in CPython, and a result check cannot tell that from `sqrt(-1)`. A NaN
fails every comparison and passes straight through.

`math.sqrt`, `math.log10` and `math.log2` were resolving by ordinary qualified
lookup (the RTL spells them identically) and so never reached that function at
all; they are in the shim table now, which is what gets them the guard.

### Gate

`test/test_nilpy_math_domain_errors.npy`, byte-identical to CPython: the
ticket's four rows, the rest of the domain surface, NaN and infinite arguments
passing through, the boundaries being IN the domain, a negative base with an
integral exponent still computing, and a real `ZeroDivisionError` still being
one. The four math sibling tests and the float/division-sensitive NilPy tests
re-run green.

### Not covered

- `math.sqrt(inf)` answers `nan` — the RTL's Newton kernel has no infinity
  guard. Pre-existing (identical under pinned v317), filed as
  [[bug-b-sqrt-of-infinity-answers-nan]].
- `math.asin`/`math.acos` are 1-2 ulps off libm mid-range —
  [[bug-b-arcsin-arccos-lose-2-ulps-vs-libm]], filed earlier the same day.

## Log
- 2026-08-15 — resolved, commit 58ff34b28.
