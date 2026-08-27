---
track: N
prio: 60
type: bug
owner: frank1-AN
blocked-by: []
resolved: PENDING-COMMIT
summary: "`self.fn = named`, a class field assigned a module-level def, was `error: cannot infer the type of field self.fn - annotate it` — and once typed, `h.fn(1, 2)` was `H has no method .fn()`. Two compile refusals of the ordinary dispatch-table shape, each with its answer already written for the neighbouring spelling."
---

# A field assigned a module-level def has no inferable type

```python
def named(a, b=10):
    return a + b

class H:
    def __init__(self):
        self.fn = named        # pascal26: cannot infer the type of field self.fn

h = H()
print(h.fn(1, 2))              # ...and then: H has no method .fn()
```

CPython prints `3`. A dispatch table held in a field is ordinary Python, and
both refusals are COMPILE errors, so neither could be worked around.

Found 2026-08-27 in the sibling sweep of
[[bug-nilpy-a-keyword-call-through-a-statically-unknown-callee-does-not-compile]].
Pre-existing: identical on pinned v386.

## Two defects, and both answers already existed elsewhere

**1. The field could not be typed.** The class-field pre-pass has two arms for
exactly this blind spot already — a module-level LITERAL global
(`PyModuleGlobalLiteralType`) and a global holding an INSTANCE
(`PyModuleGlobalCtorClass`) — because "the name is bound outside this class body"
and none of the body scanners can see it. A module-level `def` is the third
member of that family and had no arm.

The first cut asked `FindProcInUnit` and **changed nothing at all**, which is the
measurement that found the real constraint: `PyRegisterClassFieldsPrepass` runs
**before** `PyRegisterDefShells` (both call sites order them, and say why), so at
field-inference time no Proc exists for a module-level def. Only the tokens can
answer, exactly as for a literal global. Hence `PyModuleGlobalIsDef`, a depth-0
at-statement-start scan for `tkFunction` followed by the name.

The type is **variant with no recorded signature**, and that is the existing
rule rather than a new one: a LOCAL holding a def is already a variant carrying
the callable, and the ctor-PARAMETER arm immediately below answers variant for
`self.on_next = on_next`, where the parameter routinely *is* a function. It is
also the correct answer — the test rebinds `h.fn` to a different function, which
is what a dispatch table does, and a static signature would be wrong the moment
it did.

**2. The call did not resolve.** With the field typed, `h.fn(1, 2)` was `H has
no method .fn()`. The VARIANT-receiver dispatcher has claimed procedural fields
for a while — two passes around `PyMakeVariantFieldCall`, one for a field with a
recorded signature and one for a plain class's variant Callable field — and the
STATIC-receiver route (`PyParseClassMethodCall`) had no such arm. So the
receiver the frontend knew **more** about was the one that failed, the same
inversion the ticket this was found under describes for keyword arguments.

Measured before the fix: `g = h.fn` then `g(1, 2)` answered 3, while
`h.fn(1, 2)` did not. Reading the field and calling it were each fine; only
writing them as one statement failed. The fix reuses `PyMakeVariantFieldCall` —
the same builder, not a second lowering — and fires only when the class really
declares the field, so an unknown name still gets the diagnostic and typo
detection is unchanged.

## Resolution — 2026-08-27

Fixedpoint `7b1b947a22b3`, `tools/gate.sh quick` GREEN.
Test: `test/test_nilpy_field_holding_a_def.npy` + `.expected`, registered in the
Makefile — reading via a local (the control that isolates the store), calling
directly, positional and keyword, a second field, a REBOUND field, the
ctor-parameter spelling, and `self.<field>(...)` from inside the class.

**Canaries green, named:** `callable_field_all_shapes`,
`callable_field_call_returns`, `callable_replaces_its_own_slot`,
`callable_value_defaults`, `callable_param_heap_callable`,
`a_field_widens_across_methods`, `class_field_infer_from_ctor`,
`kwarg_overload`.

**One cell deliberately left and filed:**
[[bug-n-a-keyword-argument-through-a-procedural-field-needs-a-plain-receiver]] —
`H().fn(1, b=2)` and `hs[0].fn(1, b=2)` still refuse a KEYWORD argument (a
constructor-call or subscript receiver; a call RESULT and a plain local both
work, and all four work positionally). That is argument parsing shared by every
callable-field call, a different blast radius from field typing, and it wants its
own gate rather than riding along.
