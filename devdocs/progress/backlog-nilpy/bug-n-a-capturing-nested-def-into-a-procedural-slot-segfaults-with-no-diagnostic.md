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

## THE CARRIER SHAPE, MEASURED 2026-09-20 -- this ticket had GUESSED it

The text above says `PyCarrierNamedProc` "does not recognise the carrier shape
a capturing nested def produces". That was written from reasoning. Measured at
`c72af31f3a6e` with a probe printing the callee name at the coercion site, the
shape is **two layers deep**:

```
pyvar_of_callable( pyboundfn_bind( <lifted proc>, <captures> ) )
```

`pyvar_of_callable` is a FOURTH carrier spelling beside the three
`PyCarrierNamedProc` knows (`pybound_new_sig`, `pybound_new_star`,
`pybound_new`), and `pyboundfn_bind` is the closure binder inside it.

**An attempt was made and reverted rather than half-landed.** Teaching the
function to unwrap `pyvar_of_callable` and accept `pyboundfn_bind` gets as far
as the binder and still answers -1, because the AN_PROCADDR fallback reads only
the FIRST argument of the call and the lifted proc is not there. So the
remaining work is to find where in `pyboundfn_bind`'s argument list the routine
is, which is a small measurement this ticket now has the setup for.

**It is still a naming problem and not a capability one.** Once named, a lifted
routine carries its captures as EXTRA PARAMETERS, so it fails `ProcSigCompatible`
on arity and fails `PyDefFitsCallbackThunk`'s all-Variant test, and takes the
named refusal. That is the correct outcome and the whole goal.

## It is silent at BOTH coercion sites, which is why it survived two fixes

| site | a def | a bound method | a CAPTURING def |
| --- | --- | --- | --- |
| argument (`MkTwo(f)`) | thunk, works | refused by name | **silent SIGSEGV** |
| store (`e.two = f`) | thunk, works | refused by name | **silent SIGSEGV** |

Both sites ask `PyCarrierNamedProc` first and skip their whole arm on -1, so
one unrecognised carrier shape produces the identical silence at both. Fixing
the function fixes both rows at once -- which is the argument for fixing it
there rather than adding a check at either site.

## Acceptance

That program prints a diagnostic naming `inner` and the reason a capturing def
cannot be given a code address. It does NOT have to compile -- a warning that
leads somewhere is the goal, matching the rest of the family. A positive
control is cheap: the same program with `inner` not capturing `k` must keep
working (it takes the thunk path).
