---
track: N
prio: 25
type: bug
blocked-by: []
commit: 250cbc198
summary: "`divmod(obj, n)` on a class declaring __divmod__ died with a bare 'Runtime error 219'. TWO gates were wrong: the caller demanded that BOTH operands be objects, so the dunder was never reached at all; and the dispatcher behind it demanded RetKind 6 while an unannotated def returning a tuple returns a Variant."
status: done
---

# `divmod` on a user class: Runtime error 219

```python
class D:
    def __init__(self, v): self.v = v
    def __divmod__(self, o): return (self.v // o, self.v % o)

print(divmod(D(17), 5))     # CPython (3, 2)     pxx: Runtime error 219
```

Loud, but as a bare runtime code with no message and no line — 219 is the
invalid-typecast trap, so the program died naming neither `divmod` nor the
class. Found 2026-08-15 sweeping the sibling dispatchers after
[[bug-nilpy-builtins-over-a-user-iterable-answer-empty]].

## Two gates, and the ticket only knew about the second

The ticket named `PyUserObjObjDunder`'s `RetKind <> 6` guard and said to measure
before believing it. Measuring found a gate BEFORE it:

**1. `pydivmod_v` required both operands to be objects.** `divmod(D(17), 5)` has
an int on the right, so it never entered the user-object branch at all and fell
into the numeric path, where the object handle was cast — the 219. Either side
being a user object is enough now; a dunder whose `other` is a Variant has
always been able to receive the number.

**2. The dispatcher demanded a declared class as the return.** An unannotated
`def __divmod__(self, o): return (a, b)` returns RetKind **22**, a Variant, so
the method was rejected even once reached. Rather than adding a variant arm to
`PyUserObjObjDunder`, `PyUserObjDivmod` now goes through `PyUserArithCall1` —
the dispatcher that already covers every RetKind the frontend emits, whose own
comment records that its coverage was MEASURED — and unboxes the pair. One
mechanism instead of two, and `PyUserObjObjDunder` is left with no callers of
this shape. Same guard, same symptom, as the `__hash__` one two functions down.

`PyUserArithCall1`'s own `otherObj = nil` guard went with it: the only parameter
shape it accepts is a Variant, so `otherObj` was never read — the guard was
defensive and cost the whole mixed-operand case.

The unboxed pair is RETAINED: `rv` is a local Variant, so its scope exit runs
`PXXVarClear` and releases an object-tagged slot (see `PyObjAsVar`'s note, and
`project_rtti_dunder_object_result_is_released`). Anything that is not a
TPyList answers False and leaves the caller its fallback — Python's "a pair"
contract kept rather than cast.

## Gate

`test/test_nilpy_divmod_dunder.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: `__divmod__` with a positive and a negative
receiver, the reflected `__rdivmod__` via `divmod(23, obj)`, a class declaring
both (direct wins one way, reflected the other), the result unpacked and
indexed, a loop of five so a freed or leaked pair would show, a class declaring
neither (TypeError, not 219), and the builtin int/float rows unchanged.
`gate.sh quick` GREEN, pinned v329.

## Log
- 2026-08-15 — resolved, commit 250cbc198.
