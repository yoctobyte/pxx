---
track: N
prio: 50
type: feature
---

# NilPy: dispatch a method call on a VARIANT receiver at RUNTIME

Raised 2026-07-20 during the uforth drive, twice.

## The problem

A method call on a value with no static class — `wordlists.get(wid, {}).append(w)`
— is resolved by NAME across every declared class. When two unrelated classes
declare the name, the frontend cannot decide and errors:

```
Nil Python: .append() on a dynamically-typed value is ambiguous
```

## How it has been dodged so far, and why that runs out

1. **TPyList.get / TPyBytes.get -> .at.** Legitimate: Python lists and
   bytearrays have no `.get`, so those were internal accessors squatting on the
   real TPyDict API. Removing the collision was correct, not a workaround.
2. **append/extend: a NARROW documented preference for TPyList** (pyparser.inc,
   search TPyBytes in the variant-method resolver). This one IS a workaround.
   Python genuinely has both `list.append` and `bytearray.append`, so neither
   can be renamed. It leans on two facts: TPyList.append takes a Variant and so
   accepts anything, and a bytearray receiver is nearly always a
   statically-typed local that never reaches this path.

Dodge 2 is silently wrong for a dynamically-typed bytearray receiver. There is
no third rename available — the next collision has to be solved properly.

## Shape

The variant already carries VT_OBJECT plus a real class pointer, and `is` tests
against a class already work (isinstance is built on them). So the call can
lower to a runtime chain: test the receiver's class, dispatch to that class's
method, and fall through to a "no method" error. Costs one compare per
candidate, only on calls that are actually ambiguous — everything with a static
class keeps its direct call.

Consider also using the ARGUMENT types to narrow the candidate set first: for
`.append(w)` with a class-typed `w`, TPyBytes.append(Integer) cannot match, so
only TPyList survives and no runtime test is needed.

## Gate

`test-nilpy` green with a `.npy` case that calls an ambiguous method name on a
dynamically-typed receiver of EACH candidate class and gets the right one
(diffed against CPython) + `--tier quick` + self-host byte-identical.
