---
track: N
prio: 40
type: bug
---

# A bound method cannot be passed through a `Callable[...]` parameter

```python
class C:
    def m(self, x: int) -> int:
        return x + 100

def apply(f: Callable[[int], int], v: int) -> int:
    return f(v)

apply(C().m, 5)
```

```
TypeError: parameter f is declared Callable[...], which carries a code address
only, and a BOUND METHOD also needs its receiver — pass a plain function, a
lambda, or declare the parameter without an annotation
```

CPython prints 105. The residual of
[[bug-nilpy-callable-annotated-param-segfaults-on-a-heap-callable]], which fixed
the plain def, the lambda/closure and the lifted bound-fn cases (all three
segfaulted); this one is a representation limit rather than a coercion bug, so
it was split off rather than bodged.

**The workaround works and is what the message says**: drop the annotation.
`def apply(f, v): return f(v)` takes a bound method, a lambda and a def alike —
an unannotated parameter is a VARIANT, and the dynamic-call path
(`pyvar_callv<n>`) already tells all four callable shapes apart, receiver
included.

## Why

`Callable[...]` registers a `$proctype` signature and types the parameter
tyPointer (`PyAnnTypeAt`, the `callable` branch). A bound method is a
{code, receiver} PAIR — 16 bytes — and a pointer parameter has room for the code
half only. Dropping the receiver would call the method with whatever happened to
be in the Self register, which is the silent-wrong-value class this project
refuses.

## Shape of a fix

Type a `Callable[...]` PARAMETER as tyVariant and let the call go through
`PyMakeDynCall` — the same dispatcher the unannotated form already uses, which
handles all four shapes. The annotation then informs arity and diagnostics
rather than the ABI, which is what it does for the RESULT already (the declared
result is documented as a hint, not an ABI — see the `callable` branch's own
comment).

The catch to check first: a Callable FIELD must stay tyPointer. uforth's
`native: Callable[[VM], None]` is read as a code address by the field-call path
(`PyWrapClosureFieldCall`), so the change has to distinguish the PARAMETER
context from the FIELD context inside `PyAnnTypeAt`, or move the decision to the
two callers.

## Gate

`make test-nilpy` plus the existing
`test/test_nilpy_callable_param_heap_callable.npy` extended with a bound method
and a bound method stored in a list, diffed against CPython — and uforth still
green, since it is the Callable-field user.


## 2026-08-04 — BOTH the title and the documented workaround are wrong

Picked this up to do the fix it describes (type a `Callable[...]` PARAMETER as
tyVariant, keep a FIELD tyPointer). Implemented it — `PyAnnParamScope` set around
the parameter-annotation read, the `$proctype` signature dropped when the
parameter comes back variant so the call goes through the dynamic dispatcher —
and then measured, which stopped it.

### The `Callable` annotation is a red herring

**The documented workaround does not work.** `def apply(f, v): return f(v)`,
with no annotation anywhere, takes a bound method and **segfaults** — on
`stable_linux_amd64/default/pinned` as well, so this is not new:

```python
class C:
    def m(self, x): return x + 100
def ap(f, v): return f(v)
print(ap(C().m, 5))        # SIGSEGV. CPython: 105
```

So the ticket's "the workaround works and is what the message says" is false,
and typing the annotated parameter as a variant only makes the annotated form
behave exactly like the unannotated one — i.e. it removes an ABI limitation that
was not the thing standing in the way. Reverted rather than landed: it changes
the ABI of every `Callable[...]` parameter for no user-visible gain, which is
the wrong trade.

### The real boundary, measured

| shape | result |
| --- | --- |
| `C().m(5)` — direct call | **105**, correct |
| `g = C().m` then `g(5)` | crashes |
| `fs = [C().m]` then `fs[0](5)` | crashes |
| `ap(C().m, 5)` — unannotated parameter | crashes |
| `ap(lambda x: c.m(x), 5)` — wrapped | **105**, correct |

So it is not about parameters, annotations or the `Callable` ABI at all: **a
bound method cannot be used as a VALUE anywhere.** Assigning it, putting it in a
list and passing it all fail the same way, and the only thing that works is
wrapping it in a lambda — which is the workaround the diagnostic should have
named.

### Where to look next

`pyvar_callv<n>` is documented as telling all four callable shapes apart,
receiver included, so the gap is more likely in CREATING the {code, receiver}
pair when `C().m` appears in a value position than in calling it —
`pyboundfn_new`/`PXXObjIsBoundPair` (pyeval.pas) are the machinery that exists
for exactly this. Check whether a bare `obj.method` in a value position builds
one at all before touching the call side.

Retitled in spirit: the `Callable` parameter is one symptom of
"a bound method is not a first-class value". Returned to `backlog/` with that
correction rather than left as a parameter-ABI ticket, since fixing it there
would have produced a change that helps nobody.
