---
track: N
prio: 85
type: bug
blocked-by: []
summary: "`(a + b).x` SEGFAULTS with no output. Binding the temporary first — `c = a + b; c.x` — is correct. No annotations anywhere, ordinary Python, and the failure is silent."
status: done
---

# Attribute access directly on a dunder result segfaults

```python
class V:
    def __init__(self, x):
        self.x = float(x)
    def __add__(self, o):
        return V(self.x + o.x)

def known():
    a = V(1.0)
    b = V(2.0)
    return (a + b).x          # attribute access DIRECTLY on the dunder result

print("known %s" % known())
```

```
CPython:  known 3.0
pxx:      SIGSEGV, rc=139, NO OUTPUT AT ALL
```

## The control is one line and it is fine

```python
    c = a + b
    return c.x                # "known 3.0", rc=0
```

**`(dunder result).attr` dies; binding the temporary to a local first does not.**
That is the entire delta between the two programs.

## What it is not

- **Not an annotation bug.** There is no annotation of any kind in the file — not
  on the operand, not on the receiver, not on a local. It is not reachable from
  the class-annotated-local store fix (`PyStoreRhsToClassSlot`), whose guard
  requires an annotated local with a user-class type.
- **Not optimisation.** Reproduces at `-O0` and at `-O1`, with no flags, and at
  `--threadsafe`.
- **Not ASLR hiding a diagnostic.** `setarch -R` gives the same 139.

## The shape to chase first

The temporary's LIFETIME: the dunder's result released before the field is read,
so the attribute load dereferences a freed block. That puts it next door to the
hidden-destination defect fixed in `e59efc3f5`, at a different site — a value
that is never bound to a named slot and therefore has no owner keeping it alive
across the attribute access.

**Start with `-dPXX_OBJTRACE` and grep the address**, not with the parser. The
retain/release trace answers "who released it and when" directly; a parser
reading answers a question nobody has yet shown to be the relevant one.

## Why 85

An ordinary, idiomatic, fully unannotated Python expression compiles and then
kills the process with no diagnostic and no output. `(a + b).x`, `f(x).y`,
`(p - q).length` are how people write vector code. The user has no signal at all
— not a wrong value, not a message, not a line number — and the workaround
(bind a local) is invisible unless someone tells you.

Found 2026-09-15 by the lekkerzeilen seat while reducing an unrelated demo
crash; it was masking the operand bug in that seat's first fixture, which is how
it surfaced.

## Unknown, and cheap to settle

**Whether it is a REGRESSION.** Nobody built it against `4452ec06`. The compiler
delta from there to the binary it was found on is one 40-line additive function,
so that bisect has exactly one step.

## FIXED — it was the return-type SCAN, not the temporary's lifetime

**Not a regression: pinned v410 segfaults on the reproducer too.** And the
lifetime hypothesis above was wrong — `PXXDBG=a.ir:known` settled it in one
run, before any `-dPXX_OBJTRACE`: the failing function's `$pyresult` was a
CLASS slot (`store_sym ... tk=6`) with a retain call on the value, while the
control's was a VARIANT slot (`var_store ... c=19`). The double 3.0 was being
retained as an object pointer, then dereferenced. `PXXDBG=n.ret` confirms:
`known tk=6 rec=16` for `return (a + b).x`, `tk=22` for `c = a + b; return c.x`.

**Three chases, each blind to the same thing, in `PyInferExprType` and the
return scan:**

1. **No arm typed `PRIMARY.selector`.** Every arm keys on what the expression
   STARTS with, and the general walk types the primary and has nothing to do
   with the `.x` after it. `mk(4.0).x` failed the same way: the call arm keeps
   the callee's class. New arm before the walk: a paren group or a plain call
   followed by `.name...` is typed by `PyCtorSelectorType`, the chase the two
   construction arms already run after `Foo(...)`. Unresolved selector on a
   class → `tyVariant`, never the class.
2. **A bare local has no class identity in EITHER typing pass.** The pre-pass
   has no `PyLocals`; the body pass has them but the walk's ident arm reads only
   `TypeKind`. So `(a + b)` was a class of nobody and arm 1 had nothing to open.
   `PyChaseBareLocalClass` chases such an operand token-only through the scan's
   own `PyRetNameType`, from the dunder arm and from arm 1. Depth-bounded at 4:
   without the bound `total = total + i` chased itself and the COMPILER
   segfaulted on the tier's first accumulator loop.
3. **The receiver chase knew two right-hand sides.** `PyRetRecvClass` matched
   `c = Class(` and `c = def(` only, so `c = a + b` bound a receiver nobody
   recognised and the expression chase then widened over `c` and claimed ITS
   class for `c.x`. This is the ticket's own CONTROL and it regressed the moment
   chase 2 made `a + b` typeable — the old variant answer had been an accident
   of the operand being untypeable. Fixed by letting `PyRetRecvClass` fall back
   to `PyInferExprType` on any other RHS, and by excluding a name followed by
   `.` from the name-widening arm (it already excluded `name(` and `.name`).

Fixture `test/test_nilpy_a_selector_on_a_dunder_or_call_result_is_typed_by_the_selector.npy`,
seventeen rows, wired into `test-nilpy`. Positive control: pinned v410
segfaults on it; HEAD prints `SELTYPE OK`; every row's value matches CPython.

One inference got HONEST rather than better: `return (a + b).x + 1.0` was
`tyDouble` before and is `tyVariant` now — correct value both ways (4.0), one
box more. The dunder arm stops at a non-class left operand and the walk then
widens across the group; the old double was the name-chase arm reading `a`.
Noted, not fixed: a tighter answer needs the walk to treat `(group).sel` as a
unit, which is a second copy of arm 1 inside the walk.

## Log
- 2026-09-15 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
