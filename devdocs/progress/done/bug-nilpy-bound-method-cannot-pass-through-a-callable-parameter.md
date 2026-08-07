---
track: N
prio: 40
type: bug
status: done
owner: claude-AN
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

## 2026-08-07 — the 2026-08-04 correction is ITSELF stale; the ORIGINAL title was right

Re-measured before doing anything, and the boundary has moved. The 2026-08-04
note concluded "a bound method cannot be used as a VALUE anywhere" and returned
the ticket to backlog on that basis. That is no longer true — the callable-value
work since then fixed it:

| shape | 2026-08-04 | 2026-08-07 (before this fix) |
| --- | --- | --- |
| `C().m(5)` direct | 105 | 105 |
| `g = c.m` then `g(5)` | crash | **105** |
| `fs = [c.m]` then `fs[0](5)` | crash | **105** |
| `ap(c.m, 5)` unannotated param | crash | **105** |
| `ap(lambda x: c.m(x), 5)` | 105 | 105 |
| `apply(c.m, 5)` **annotated** | (the original bug) | **still raised** |

So the only surviving failure was the one the ticket was originally filed for,
and the fix it originally proposed — type a `Callable[...]` PARAMETER as
tyVariant, keep a FIELD tyPointer — became the right one, because the
"workaround" it depends on (an unannotated parameter) now genuinely works. The
2026-08-04 session rejected that fix for removing "an ABI limitation that was not
the thing standing in the way"; it is now the only thing standing in the way.

### The change

`PyAnnParamScope`, mirroring the existing `PyAnnRetScope` exactly: set around a
parameter's annotation read (the three sites that store a parameter type — the
def header and both method paths, which must agree or the ABI silently
mismatches). The `callable` branch of `PyAnnTypeAt` returns tyVariant under it,
and drops the `$proctype` signature with it — keeping the signature would
marshal the call against a procedural type again, which is the very thing with
no room for a receiver. A FIELD sees the flag clear and keeps both.

All six rows above now match CPython.

### The named risk, checked: the Callable FIELD path is unaffected

uforth's `native: Optional[Callable[["VM"], None]]` shape, exercised directly:

| binary | result |
| --- | --- |
| PINNED (pre-change) | `inc 2` |
| this change | `inc 2` |
| CPython | `inc 2` |

`make test-uforth` could NOT serve as the gate: it fails identically on the
PINNED binary at `uforth.py:411` — *"no class declares a method or callable
field .to_bytes()"* — so the corpus was already red for an unrelated reason.
Controlled rather than assumed, and not attributed to this change.

### A pre-existing crash found and filed, not folded in

`ap(C().m, 5)` — a bound method of a **TEMPORARY** receiver — segfaults, on the
pinned binary and through an UNANNOTATED parameter too. That is receiver
lifetime, not the callable ABI, so it is
[[bug-nilpy-bound-method-of-a-temporary-receiver-segfaults]] and the row is left
commented out in the test naming that ticket, rather than blaming a pre-existing
crash on this commit.

### Test

`test/test_nilpy_callable_param_heap_callable.npy` extended as the gate asked —
a bound method through the annotated parameter, one via a list element, one
bound to a name, two instances keeping their own receivers, and the Callable
FIELD path at the bottom. 11 lines byte-identical to the CPython oracle.

### Gate

`make fpc-check` byte-identical, self-host fixedpoint, `tools/gate.sh quick`.

## Log
- 2026-08-07 — resolved, commit 792071996.
