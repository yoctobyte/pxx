---
track: N
prio: 40
type: bug
owner:
blocked-by: []
summary: "MECHANISM: PyCarrierNamedProc answers -1 for the carrier shape a LIFTED nested def produces, so the coercion site's warn arm never fires and nothing is said at all. The value still goes into the procedural slot and calling through it is a SIGSEGV. SPRINGS whenever a def that captures enclosing state is handed by NAME to a procedural parameter. Unchanged behaviour -- identical on pin v412 and at HEAD -- and it is the SILENT member of a family whose other members now either work or refuse by name."
---

# A capturing nested def into a procedural slot segfaults with no diagnostic

## The shape

```python
import 'cbslot.pas' as cb


def outer(k):
    def inner(a, b):
        return a + b + k      # CAPTURES k
    s = cb.MkTwo(inner)       # handed by NAME
    return cb.CallTwo(s)


print(outer(5))
```

Compiles with **no diagnostic of any kind** and segfaults (exit 139).
Identical on `stable_linux_amd64/default/pinned` (v412) and at HEAD, so this
is not introduced by the callback-thunk work -- it is what that work left
behind.

## Why nothing is said

`PyCoerceCallableArgsIn`'s procedural-parameter arm asks
`PyCarrierNamedProc(node)` which routine a carrier was built for, and only
warns when that answers `>= 0`. For a lifted nested def the carrier is not one
of `PyMakeFuncValueFor`'s three recognised forms, so the answer is -1, the arm
is skipped entirely, and the value reaches the slot unremarked.

## Why this is a refusal and not a feature

The obvious-looking repair -- thunk it, like a top-level def -- is wrong, and
the reason is the same one that keeps a bound method out:

> A procedural slot holds a bare CODE address and retains nothing. A thunk for
> a capturing def would have to reach the lifted capture state at run time, so
> it would outlive what it reads.

Note the capturing case is **already excluded by construction** from the thunk
path, not by a hand-written guard: the lambda lift appends captured state as
extra parameters, so `outer.inner` has 3 parameters (`22 22 13`) against the
slot's 2 and fails both the arity test and the all-Variant test in
`PyDefFitsCallbackThunk`. Nothing needs new analysis to decide this -- the
decision is already correct.

**So the fix is a named REFUSAL at the carrier, not new capability.** Give
`PyCarrierNamedProc` (or the arm that calls it) an answer for the lifted-def
carrier shape that is "this is a callable the frontend can name, and it is one
that cannot be thunked", so the existing warning fires with the right reason.

## The family, for whoever takes this

Three ways a callable reaches a procedural slot, after `8826e6aec` and the
thunk work:

| handed in | today |
| --- | --- |
| a Pascal routine | works -- its address is stored |
| a top-level def | works -- a `$pycbthunk_` carries the slot's signature |
| a bound method | refused BY NAME, with the reason |
| a def of wrong arity | refused BY NAME, with the reason |
| **a capturing nested def** | **silent SIGSEGV** |

The last row is the only silent one left, which is the whole argument for
ranking it: every sibling either works or says why not.

## Acceptance

That program prints a diagnostic naming `inner` and the reason a capturing def
cannot be given a code address. It does NOT have to compile -- a warning that
leads somewhere is the goal, matching the rest of the family. A positive
control is cheap: the same program with `inner` not capturing `k` must keep
working (it takes the thunk path).
