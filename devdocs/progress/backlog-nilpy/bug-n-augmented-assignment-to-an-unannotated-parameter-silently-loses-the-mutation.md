---
type: bug
track: N
prio: 70
status: open
slug: bug-n-augmented-assignment-to-an-unannotated-parameter-silently-loses-the-mutation
---

# `p += x` on an UNANNOTATED PARAMETER never dispatches `__iadd__`, and silently loses the caller's mutation

**A WRONG VALUE, NOT A CRASH, on the ordinary accumulator idiom.** Measured
2026-09-15.

```python
class V:
    def __init__(self, x): self.x = x
    def __iadd__(self, o):
        self.x += o.x
        return self
    def __add__(self, o):
        return V(self.x + o.x)

D = V(0.5)
def f(p):        # p is a PARAMETER, unannotated
    p += D

a = V(1.0)
f(a)
# CPython: a.x == 1.5   (__iadd__ mutated the caller's object)
# NilPy:   a.x == 1.0   (__add__ made a new object, bound to the local)
```

Measured directly with `id()`:

| | in_place | caller_sees |
|---|---|---|
| NilPy, receiver is a PARAMETER | False | **1.00** |
| CPython, same | True | 1.50 |
| NilPy, receiver is a LOCAL | True | 1.50 |

**WITH BOTH DUNDERS DECLARED IT IS SILENT. WITH ONLY `__iadd__` IT IS LOUD** —
`TypeError: expected a number, got object`, because the target falls through to
the numeric path. The silent shape is the common one: declaring both `__iadd__`
and `__add__` is the normal idiom, and it is what `lekkerzeilen`'s `math3d.py`
does.

## THE FACTORIAL — it is the RECEIVER's storage class, and nothing else

Five rows, receiver and operand varied independently. `V` declares only
`__iadd__` so the failure is loud rather than silent:

| receiver | operand | NilPy | CPython |
|---|---|---|---|
| LOCAL | param | ok | ok |
| ATTRIBUTE | param | ok | ok |
| GLOBAL | — | ok | ok |
| PARAMETER | global | **FAIL** | ok |
| PARAMETER | local | **FAIL** | ok |
| PARAMETER | param | **FAIL** | ok |

The operand's storage class makes no difference. **I first attributed this to
the operand** — the two probes that disagreed differed in the operand as well as
in the class's dunder set, and I named the factor that varied in front of me.
The matrix above is what corrected it, and it is the fourth time in two days
that a factor named from the rows to hand was retired by one more row.

**AN ANNOTATED PARAMETER IS FINE**: `def f(p: V)` dispatches correctly. That is
the tell that names the cause.

## CAUSE, LOCATED IN SOURCE

`PyAugClassDunder` (`compiler/pyparser.inc:29139`) opens with

```pascal
  if Syms[symIdx].TypeKind <> tyClass then Exit;
```

so the whole `__iadd__`/`__add__` dispatch is keyed on the target's **STATIC**
type. An unannotated parameter is not statically `tyClass` — it arrives as a
Variant — so the arm exits, the caller keeps its path, and the numeric
`AN_BINOP` below runs on the instance handle. `PyAugClassDunderNode`, the
field-target twin at `:29182`, has the same shape and the same `IntToTypeKind(
ASTTk[lhsNode]) <> tyClass` gate; attributes happen to pass it because a field's
declared type is known.

This is the same defect as
`bug-nilpy-augmented-assign-on-a-class-instance-silently-yields-zero` and
`bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero`, both
already fixed and both cited in that function's own comments — **arriving
through the one target shape whose type is not known until run time.** The two
fixed arms are the statically-typed cases; the Variant case never got one. That
is exactly the normalise-don't-special-case shape: a construct reachable through
three target spellings, repaired twice, with the third left on the broken path.

## THE RUNTIME MACHINERY ALREADY EXISTS — this is a wiring job, not a new mechanism

`compiler/builtin/pylib.pas` already dispatches a user dunder from a Variant at
run time, by NAME:

- `PyUserArithCall1(selfObj, otherObj, otherV, dunder, out result)` — `:5377`
- `PyUserObjHasDunder(o, dunder)` — `:6332`

So "try `__iadd__`, else `__add__`, rebind" is expressible with what is there.
The shape of the fix is a pylib helper that takes both dunder names and does the
CPython rule at run time, plus an arm in the aug-assign lowering that routes a
Variant-typed target to it instead of falling through to `AN_BINOP`.

**DO NOT FIX THIS BY MAKING THE STATIC GATE LOOSER.** The gate is correct for
what it does; the missing thing is a runtime path for the case where the static
type is genuinely unknown. Widening `tyClass` to include Variant would send
every Variant `+=` — ints, floats, strings, lists — through user-dunder lookup.

## NOT A LEKKERZEILEN BLOCKER — checked, not assumed

The lekkerzeilen seat ran the census on both trees: **seven** augmented
assignments to a parameter, and none is exposed. Every one takes a SCALAR
(`angle` a float, `n` an int, `count` an int), which has no mutating `__iadd__`,
so CPython rebinds the local too and there is no divergence to have. And every
one of those functions RETURNS the value and every caller uses the return, so
even under the exact failure mode the value comes back out. Sites:
`vessel.py:17,19`, `traffic.py:348,350`, `traffic.py:113,115`,
`pcl/tkhtmlview.py:271`.

So this is ranked on GENERALITY — a silent wrong value on an ordinary idiom —
and not on the demo.

## REPRO

`$SCRATCH/vc/iadd.npy` (the five-row matrix) and `iadd4.npy` (the `id()`
in-place check) from session `01FcK7gV4FyP2pctkY9QUaPV`. Both are a few lines;
the file above reproduces it standalone. Compiler measured: `79551a1b6d05f02e`
(= `e59efc3f5`). CPython 3 is the oracle and disagrees on every failing row.

## A SEPARATE THING NOTICED IN PASSING, NOT FILED

A nested `class W: pass` inside a function body is a parse error
(`pascal26:N: error: expected expression`). Unrelated to this ticket and not
investigated — noted here only so the next person does not spend the minute I
did wondering why a probe would not compile.
