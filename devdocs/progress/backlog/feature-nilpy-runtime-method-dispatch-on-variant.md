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

## Recon 2026-07-31 — confirmed still genuinely open, not stale

Given how many other tickets this session turned out to already be fixed,
checked this one for real too, rather than assuming: it is NOT stale. The
exact silent-wrong-value case the ticket predicts is measured and
reproducible:

```python
def get_container(flag):
    return bytearray() if flag else [1, 2]
c = get_container(True)
c.append(99)
print(c)          # CPython: bytearray(b'c')    pxx: b'\x01'
```

`.append(99)` on a dynamically-typed bytearray receiver dispatches to the
"append prefers TPyList" workaround and silently produces the wrong value
— no error, no diagnostic. The argument-type-narrowing idea in this
ticket's own "Shape" section does NOT resolve this specific case: an
Integer argument (99) is accepted by BOTH `TPyBytes.append(Integer)` and
`TPyList.append(Variant)` (Integer coerces to Variant), so only a genuine
RUNTIME class test on the receiver disambiguates it — the harder half this
ticket already anticipated. Not attempted this pass: it needs new runtime
type-dispatch codegen (test the receiver's class tag, branch to the
matching method), not a quick patch, and is real new machinery rather than
a stale-ticket verification like most of what else got closed today.

## Gate

`test-nilpy` green with a `.npy` case that calls an ambiguous method name on a
dynamically-typed receiver of EACH candidate class and gets the right one
(diffed against CPython) + `--tier quick` + self-host byte-identical.
