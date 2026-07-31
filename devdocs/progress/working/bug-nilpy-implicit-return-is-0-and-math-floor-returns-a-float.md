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

## FIXED — commit (this session)

The premise that "Plain Pascal does not have this gap" / "there is a real
Result-zero-init mechanism in the shared codegen" was ITSELF wrong — measured,
not assumed. Under `-g`/`-O0` a plain `function Empty: Integer; begin end;`
called right after a function that sets `rax` to a large value ALSO returns
that garbage value (confirmed with gdb: the stack slot at `[rbp-4]` genuinely
still held the prior call's `0x4000cccc` when Empty's epilogue read it). The
"reliable 0" observed at the DEFAULT `-O2` was an OPTIMIZER ARTIFACT specific
to `-O2` (a function that never stores to Result gets its Result load folded
to a constant at that optimization level) — not a deliberate zero-init
contract, and NilPy's `def` body structure just doesn't happen to trigger the
same fold. `bug-a-nilpy-...` sibling investigations elsewhere in this codebase
already document exactly this kind of misattributed-to-a-mechanism-that-
doesn't-exist trap; this is another instance of it.

The REAL, narrowly-scoped fix: `PyPrependResultZero` (pyparser.inc) already
existed to zero a MANAGED Result slot (AnsiString/Variant) at body entry for
methods — its own comment explicitly called a scalar (Integer) Result
"harmless" to leave uninitialized. Extended it (new `PyZeroLitFor` helper) to
also emit an explicit `Result := 0`-shaped assignment for the plain scalar
kinds (Integer family, Boolean, Single/Double), and wired the call into
`PyParseDef`'s own body (previously only the method-body path called it) so a
plain top-level/nested `def` gets the same guarantee a method already did for
its managed kinds. Verified with `-g`/gdb that the fix holds at BOTH `-O0` and
`-O2` (deterministic `0`, not a lucky optimizer fold), and that `f() is None`
now correctly returns `True` off that deterministic value (it already did
before, coincidentally — see below).

## What's NOT fixed, and is out of scope here

`print(f())` still prints `0`, not the CPython text `None`. This is NOT new:
even an EXPLICIT `return None` in a def whose registered return type ends up
SCALAR (e.g. a def some caller uses in an int-returning position) already
prints `0` today, while `f() is None` still correctly says `True` — confirmed
by direct testing (`def g(): return None; print(g())` prints `0`, `g() is
None` prints `True`, both BEFORE and AFTER this fix). NilPy already has a
None-detection mechanism independent of print/repr formatting for a
scalar-typed slot; making `print()` show `None` for a scalar-shaped return
is a wider, pre-existing gap (real None-carrying Variant return values), not
something this fix's narrower undefined-behaviour scope introduced or was
meant to close. That gap tracks with `feature-nilpy-none-variant` — do not
reopen this ticket for it; file/point there instead.

## Gate

`make test-nilpy` + self-host byte-identical (confirmed), plus
`test/test_nilpy_implicit_return_none.npy`: a value-returning function runs
FIRST (to load a nonzero value into whatever register/slot an uninitialized
Result would otherwise leak), then a bodyless top-level `def` AND a bodyless
method both report a deterministic `0` and `is None` `True` — verified at
both `-O0` and the default `-O2`, and re-verified after fixing an unrelated
comprehension-scope regression (`bug-nilpy-comprehension-variable-leaks-and-
clobbers-the-enclosing-scope`) landed in the same session to make sure the
two didn't interact.
