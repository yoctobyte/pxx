---
prio: 25
track: N
type: bug
blocked-by: []
summary: "divmod(obj, n) on a class declaring __divmod__ dies with 'Runtime error 219' (invalid typecast) instead of returning the pair. The dispatcher demands RetKind=6 (a class) and a NilPy def returning a tuple does not declare that, so the dunder is never called and the fallback casts something that is not a TPyList."
---

# `divmod` on a user class: Runtime error 219

```python
class D:
    def __init__(self, v):
        self.v = v
    def __divmod__(self, o):
        return (self.v // o, self.v % o)

print(divmod(D(17), 5))     # CPython: (3, 2)     pxx: Runtime error 219
```

Reproduces at v324. Found 2026-08-15 while resolving
[[bug-nilpy-builtins-over-a-user-iterable-answer-empty]] — sweeping the OTHER
dispatchers in the same family after fixing the no-arg one. That pin does not
touch this path.

**Loud, but as a bare runtime code with no message and no line**, which is
worse than an exception: 219 is the invalid-typecast trap, so the program dies
naming neither `divmod` nor the class.

## Where

`pylib.pas`, `PyUserObjObjDunder` — the 1-argument, object-RETURNING dunder
dispatcher (only caller: `PyUserObjDivmod`, for `__divmod__` / `__rdivmod__`):

```pascal
  if mi^.RetKind <> 6 then Exit;              { returns a class (the tuple) }
```

A NilPy `def` returning a TUPLE almost certainly does not register RetKind 6 —
the sibling arithmetic dispatcher next door handles a whole family of RetKinds
(str, int, float, bool, list, mixed pair) precisely because the frontend emits
several. So the guard rejects the method, `PyUserObjDivmod` answers False, and
the caller's fallback casts a value that is not a `TPyList` — hence 219.

**Measure the RetKind before fixing** (`PXXDBG=a.ir:D.__divmod__`, or print
`mi^.RetKind` from the dispatcher): the guard above is a hypothesis with one
strong piece of evidence, not a confirmed cause. The arithmetic dispatcher's
own comment says its coverage was established by measuring, not by reasoning.

## Shape of a fix

Accept the RetKind the frontend actually emits — most likely 22 (variant) — and
unbox it to the object, exactly as `PyUserObjNoArgDunder` does across its six
arms. Then `PyUserObjDivmod`'s existing "must be a TPyList, else answer False"
check does the rest, so a dunder returning something that is not a pair still
falls back instead of being cast.

While there: whatever the dispatcher hands back must be RETAINED before it is
boxed. The no-arg dispatcher had exactly that defect — a class-typed call
temporary is released at the end of the statement while the box does not
retain, so the caller got a freed object — see the resolution note on
[[bug-nilpy-builtins-over-a-user-iterable-answer-empty]]. A `PXXObjRetain` was
tried here speculatively and changed nothing (the RetKind guard exits first),
so it was NOT shipped; it becomes relevant the moment the guard is widened.

## Gate

`.npy` diffed against CPython: `divmod(obj, n)` with `__divmod__`, the
reflected `divmod(n, obj)` with `__rdivmod__`, a class declaring neither
(TypeError, not 219), a `__divmod__` returning a NON-pair (falls back rather
than casting), and the builtin `divmod(7, 2)` / `divmod(-7, 2)` rows unchanged.
