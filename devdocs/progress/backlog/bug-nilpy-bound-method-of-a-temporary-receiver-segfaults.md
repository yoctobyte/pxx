---
track: N
prio: 45
type: bug
summary: "`f(C().m)` — a bound method whose receiver is a TEMPORARY — segfaults. `c = C(); f(c.m)` is fine, so the pair outlives the instance it points at: a receiver-lifetime bug, not a callable-value one"
---

# A bound method of a temporary receiver segfaults

```python
class C:
    def m(self, x):
        return x + 100

def ap(f, v):
    return f(v)

print(ap(C().m, 5))          # CPython: 105    pxx: SIGSEGV
```

Binding the instance to a name first is enough to make it work:

```python
c = C()
print(ap(c.m, 5))            # 105, correct
```

## Measured 2026-08-07 — pre-existing, and NOT about annotations

Found while fixing
[[bug-nilpy-bound-method-cannot-pass-through-a-callable-parameter]] and
deliberately kept out of that change's test, because attributing it there would
have blamed a pre-existing crash on a new commit.

| binary | `ap(C().m, 5)` — UNANNOTATED parameter |
| --- | --- |
| `stable_linux_amd64/default/pinned` (pre-change) | **SIGSEGV** |
| that session's HEAD | **SIGSEGV** |
| CPython | 105 |

Both ends crash, and the parameter carries no `Callable[...]` annotation, so
neither the annotation ABI nor the variant-typing change is involved. Every
other bound-method shape works: `c.m` assigned to a name, stored in a list,
passed through an unannotated parameter, and (since that fix) passed through an
annotated one, including two instances keeping their own receivers.

The single variable is whether the receiver is a **temporary**.

## Likely shape

`obj.method` in a value position builds a `{code, receiver}` pair
(`pybound_new`, pylib). When the receiver is a named local, that local holds a
reference and outlives the call. When it is `C()`, the instance is a call-result
temporary whose reference is dropped at the end of the statement — the pair then
points at a freed block, and the method runs with a dangling Self.

So the pair almost certainly does **not retain its receiver**. Check
`pybound_new` for a `PXXObjRetain` on the receiver half and
`PyObjFinalize`'s `rawKind <> 0` branch for the matching release — that branch
already releases both `Code` and `Recv`, which suggests the *release* side
exists and only the retain is missing. If so this is a one-line fix plus a test,
but confirm with `-dPXX_OBJTRACE`/`-dPXX_HEAP_DEBUG` before changing it: an
unbalanced retain would leak every bound method instead, and this family has a
history of confidently-wrong refcount fixes
([[bug-nilpy-bound-fn-closure-objects-are-never-freed]]).

## Gate

Per-fix loop, plus `test/test_nilpy_callable_param_heap_callable.npy` gaining
the `C().m` row that is commented out there today (the comment names this
ticket), byte-identical to the CPython oracle. Check `-dPXX_HEAP_DEBUG` is clean
on the repro, so the fix is not merely making the freed block survive by luck.
