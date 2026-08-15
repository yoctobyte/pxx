---
track: N
prio: 35
type: bug
blocked-by: []
commit: PENDING-COMMIT
summary: "Assigning a nested def's value to an OUTER name of the same spelling — `g = make()` over a `def g` inside make — bound None: the def is a LOCAL of the enclosing scope and must shadow the module global, but three gates asked only whether a symbol of that name existed at all."
status: done
---

# A nested def shadowed by an outer name binds to None

```python
def make3(base):
    def g(x, off=base):
        return x + off
    return g

g = make3(10)          # the OUTER name is also `g`
print(g(1))            # CPython 11
                       # pxx: TypeError: object is not callable — the name is None
```

Renaming either side fixed it. Found 2026-08-15 while testing
[[bug-nilpy-a-nested-defs-default-parameter-ignores-the-callers-value]], where
the first draft of the test hit it by accident.

Loud, and the message blamed the wrong party: "the name is None (an import that
did not resolve, or a value never assigned)" when the value WAS assigned, from a
call whose return went missing.

## Cause — measured, and it is not where the ticket guessed

The filed ticket pointed at `PyQualifyNested` picking the wrong row between the
qualified `make3.g` and the module `g`. It is simpler and one level up.

Varying the shape found the boundary: `g = 5` after the same factory was fine,
`h = make3(10)` was fine, and `t = make3(10); g = t` failed — and it failed on
`t`'s line, BEFORE the colliding assignment. So the defect is not in the
assignment at all. It is in `return g` inside `make3`: the module-level `g` had
already been allocated (the assignment being parsed), `FindSym('g')` found it,
and all three gates around the nested-def lookup read

```pascal
(FindSym(name) < 0) and (FindProc(PyQualifyNested(name)) >= 0)
```

so `return g` handed back the module global — None, since its own assignment had
not run yet.

In Python a `def` BINDS A LOCAL of the enclosing scope; it shadows a global
unconditionally. "Does a symbol of this name exist anywhere" was never the right
question. `PyNestedDefOutranksSym` asks the right one — the found symbol is an
`skGlobal` and a qualified nested proc of that name exists — and the three gates
(the func-value arm and the qualify-the-call arm in `parser.inc`, plus
`PyMakeFuncValue`'s early exit) now go through it. All three, because this is a
one-concept-three-sites shape and fixing one arm leaves the value path or the
call path still reading the global.

A genuine LOCAL of the same name still wins: that is a REBINDING in the same
scope (`def g(): ...` then `g = 5`), which the redefinition machinery settles.

Not handled, and noted in the code: an enclosing body that declares `global g`,
where Python does give the module binding back. No corpus needs it;
`PyBodyDeclaresNonlocal` is the shape a fix would follow.

## Gate

`test/test_nilpy_nested_def_outer_name_collision.npy` (+`.expected`, in the
Makefile), byte-identical to CPython: the straight collision, the name rebound
from a second factory call, a defaulted parameter on the shadowed def, the inner
def called INSIDE its own scope while the outer name exists, a two-level nest
where the middle name collides too, the collision through an intermediate
variable, a module-level `def` of the same name (a different question, still
right), and controls. `gate.sh quick` GREEN.

## Log
- 2026-08-15 — resolved, commit 9496262c9.
