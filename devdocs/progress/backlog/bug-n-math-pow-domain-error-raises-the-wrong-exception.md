---
track: N
prio: 25
type: bug
summary: "Every math domain error in NilPy raises `ZeroDivisionError: division by zero` where CPython raises `ValueError: math domain error` — sqrt(-1), log(-1), log(0) and pow(-8, 0.5) all of them, and the same call compiled as PASCAL returns Nan without raising at all. Three behaviours for one operation; a CPython program's `except ValueError:` catches none of ours."
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
