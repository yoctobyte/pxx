---
track: N
prio: 55
type: bug
---

# A function with no `return` yields UNINITIALIZED garbage, not None

`math.floor`/`math.ceil` returning a float instead of an int (this ticket's
other original half) is FIXED — commit b3c00ab78db698aecc4a107208b574918057c24e.
`import math` compiles the real RTL Math unit, and `math.floor`/`math.ceil`
were reaching that unit's own `Floor`/`Ceil` (`Double->Double`, correct for the
Pascal frontend, left untouched); NilPy now intercepts the two dotted names by
name (`PyStdlibCallProc`/`PyStdlibCallAhead` in pyparser.inc) onto new
int-returning shims (`pymath_floor`/`pymath_ceil` in pylib.pas), ahead of the
ordinary qualified-call resolution. `round()` was checked against the same
table and already matched CPython (`round(x)` -> int, `round(x, n)` -> float);
no change needed. Regression: `test/test_nilpy_math_floor_ceil_int.npy`.

**What's left, and it is worse than originally described:**

```python
def f():
    pass
print(f())            # CPython: None    pxx: 0 -- OR GARBAGE, see below
```

The original framing ("typed tyInteger, so it prints 0 instead of None") is
only half true. Investigating it turned up that the 0 is not a deliberate
default at all — it is **uninitialized return-register content that happened
to read as zero** in every program that had tried the case so far.

## How this was found

`PXXDBG=a.ir:f` on `def f(): pass` reports `IR count=0` — the routine's body
compiles to literally no stores to a result slot. Confirmed the "0" was
coincidence, not initialization, empirically: adding the math.floor/ceil shims
above (an unrelated, isolated change — two new pylib functions and a dotted-
name interception, nothing touching proc epilogues) was enough to perturb
register state so that the SAME `print(f())` that printed `0` before now
prints an arbitrary garbage integer (observed: `1073794252`) once a
`math.floor`/`math.ceil` call ran first in the same program. `f() is None`
flipped from `True` to `False` in lockstep — it too was reading whatever
register happened to hold 0.

Plain Pascal does not have this gap: a `function f: Integer; begin end;`
reliably returns 0 even after another function set a return register to a
large nonzero value first (checked with a two-function repro) — so there is a
real Result-zero-init mechanism in the shared codegen, and NilPy's `def` with
an empty/no-return body is not going through it, or is skipping it for this
shape specifically.

## Shape of a fix

Root-cause where a NilPy `def`'s IR body is finalized (`pyparser.inc`, the
same neighbourhood as `PyDefReturnType`/`PyMethodRetType`'s "harmless case"
comments at the three sites documented previously) and where the proc epilogue
is emitted (`ir.inc`) to find why Pascal's Result-zero-init doesn't reach this
NilPy shape — the `IR count=0` finding says the body never lowers a store at
all, so either the zero-init pass silently excludes this local/slot, or NilPy
defs don't route through the same prologue mechanism at all for a body with no
top-level statements. Do NOT reuse the two prior "harmless case" comments as
evidence this is already handled — they justify the REGISTERED type choice
(tyInteger for the signature), not that a value is ever actually stored.

This is a plain uninitialized-read bug (the class this project's own
debugging playbook calls the expensive kind — plausible wrong value, no
crash), not a design question, so no Track U ticket is needed; it stays here
once someone has time to trace the epilogue/zero-init path with `-g` + gdb or
`PXXDBG=a.ir`/`a.ast` rather than reasoning about it.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` that calls a
value-returning function FIRST (to load a nonzero value into whatever
register/slot the empty-bodied `def` would otherwise leak), then calls the
empty-bodied `def` and checks BOTH `print(f())` prints `None` (not `0`, not
garbage) and `f() is None` is `True`. A test that only calls the empty-bodied
def in isolation will not catch a regression — see how this one survived.
