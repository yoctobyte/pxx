---
track: N
prio: 55
type: bug
status: working
owner: claude-AN-night
---

# `range(a, b, s)` with a NEGATIVE step passed at runtime yields an empty range

- **Type:** bug (NilPy, silent wrong value) — **Track N**
- **Found:** 2026-08-02, while fixing
  [[bug-nilpy-range-over-a-variant-bound-loops-forever]]. Distinct defect, same
  lowering.

## Measured

```python
def stepped(a, b, s):
    out = []
    for i in range(a, b, s):
        out.append(i)
    return out

print(stepped(10, 0, -3))     # CPython [10, 7, 4, 1]     pxx []
print(stepped(0, 10, 3))      # CPython [0, 3, 6, 9]      pxx [0, 3, 6, 9]  ok
for i in range(10, 0, -3):    # a literal step is fine
    ...
```

## Cause

The loop DIRECTION is decided at compile time, and only from a literal:

```pascal
if ((ASTKind[rngStep] = AN_INT_LIT) and (ASTIVal[rngStep] < 0)) then
  ASTIVal[cmpNode] := Ord(tkGt)
else
  ASTIVal[cmpNode] := Ord(tkLt);
```

So a step whose value is only known at run time always gets `<`, and a
descending range terminates immediately — empty, silently.

## Fix shape

Emit a RUNTIME direction test when the step is not a known-negative literal:
`if step < 0 then (i > stop) else (i < stop)`. The literal cases should keep
their current single-comparison lowering so nothing gets slower where the
direction IS known — which is the overwhelmingly common case.

Note this is the same "decided statically from a literal" shape as
[[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]];
worth reading that ticket first, since a general answer may cover both.

## Gate

A `.npy` diffed against CPython covering: negative literal step, negative
runtime step, positive runtime step, a step of 0 (CPython raises ValueError),
and descending ranges that end exactly on the bound.


## Resolved 2026-08-03

The guard now tests the direction at RUN time when the step's sign is not
already known: `(step < 0) ? (i > stop) : (i < stop)`, built as the AN_TERNARY
the frontend already uses everywhere else. A literal step keeps the existing
single-comparison lowering exactly as it was, so `range(n-1, -1, -1)` — the
common shape — pays nothing, which is what the ticket asked for.

### Two things the fix shape did not mention, both required

**The step and the stop both need a hidden temp.** Each is now read twice — the
step by the direction test and by the increment, the stop by the two ternary
arms — and re-reading an expression with side effects would run it again. That
is the same "a node referenced twice is EMITTED twice" hazard the boolean
operators had (bug-nilpy-and-or-evaluates-the-left-operand-twice, fixed earlier
today).

Binding them also evaluates each ONCE for the whole loop, which is what CPython
does with `range()`'s arguments. The previous lowering re-ran the stop
expression on every iteration — a pre-existing divergence, narrowed here for the
runtime-step path.

**A zero step.** Once the direction is a runtime question, a zero step is
reachable and the loop never advances: it HANGS. Python raises
`ValueError: range() arg 3 must not be zero`, so a `pyrange_check_step` call is
emitted before the loop on the same non-literal path. It is a pylib routine, not
inline codegen, so the message is written once and the literal path never calls
it.

### Verified

`test/test_nilpy_range_runtime_step.npy` (+ `.expected`, wired into
`make test-nilpy`), 12 lines byte-identical to CPython: negative and positive
runtime steps, a descending range ending exactly on the bound, one that
overshoots it, empty ranges from both directions, negative bounds with a
negative step, the literal-step forms as the fast-path controls, `range(n-1,
-1, -1)` with a computed start, and the zero step caught as a ValueError.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical, FPC seed clean.
(pylib.pas is frozen into the pinned builtin copy but the compiler does not use
it, so this needed no re-pin — see the note on
[[project_builtin_change_needs_repin_for_gate_fixedpoint]].)

## Log
- 2026-08-03 — resolved.
