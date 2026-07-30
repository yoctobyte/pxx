---
track: N
prio: 60
type: bug
---

# `return Node(...)` leaks one object ref per call; `x = Node(...); return x` does not

The return-ownership retain (ir.inc, the `Syms[varIdx].TypeKind = tyClass`
arm of AN_RETURN/AN_EXIT) takes an unconditional +1, on the reasoning that
"a returned local's own ref dies in the callee's scope-exit release right
after this". That holds only when the returned expression is a BORROWED
lvalue. When it is already owned — a construction, or another call's result —
there is no local binding and no scope-exit release, so the +1 is never
balanced and one ref leaks per call.

The AN_ASSIGN class-rebind arm a few hundred lines up already states the rule
and applies it:

```pascal
{ A construction OR any call result is OWNED (+1 already: rc=1 from
  PXXObjAlloc, or the callee's return-retain) — retaining it again
  would leak one ref per call. Only lvalue-ish sources are borrows. }
if not ((ASTKind[ASTRight[node]] = AN_CALL) or
        (ASTKind[ASTRight[node]] = AN_VIRTUAL_CALL) or
        (ASTKind[ASTRight[node]] = AN_INTF_CALL) or
        (ASTKind[ASTRight[node]] = AN_CALL_IND) or
        (ASTKind[ASTRight[node]] = AN_METACLASS_NEW)) then
```

The return arm has no such exclusion.

## Measured (RSS slope, 20k vs 320k iterations)

```python
def make(i: int) -> Node:
    return Node("n", i)        # 1.9 MB -> 25.4 MB   (~78 B/iter)

def make(i: int) -> Node:
    x = Node("n", i)
    return x                   # 0.43 MB -> 0.43 MB  FLAT
```

Driver: `while i < n: y = make(i); i = i + 1`. Measured with
`/usr/bin/time -f %M`; the two programs differ only in that one line, which
is what makes the slope the evidence rather than the absolute number
(see [[project_leak_vs_arena_artifact_diagnosis]]).

Pre-existing on the main-program path, so it is not a regression from
[[bug-nilpy-object-reclamation-disabled-inside-py-modules]] — but that fix
turns the same path on inside imported `.py` modules, so this leak now
reaches module code too.

## Fix direction

Give the return arm the same owned-source exclusion as the assign arm. Both
are stating one invariant (call results and constructions are owned; lvalues
are borrows), so they should read from ONE predicate rather than two copies
that can drift — which is exactly how they drifted here.

## Fixed 2026-07-30 — measured both ways

One predicate now, `IRNodeYieldsOwnedRef` in ir.inc, read by the return arm and
by BOTH assignment arms (there were two copies of the exclusion, not one — which
is how far the drift had already gone).

RSS slope, same driver, 20k vs 320k iterations:

| build | `return Node(...)` | `x = Node(...); return x` |
| --- | --- | --- |
| before | 1972 KB -> 25396 KB | flat |
| after  | 436 KB -> 436 KB | 436 KB -> 436 KB |

The "before" column is a compiler built from the commit preceding the fix, run
in the same shell — so the slope is the evidence, not the absolute number.

`test/test_nilpy_return_ownership.npy` is the correctness half: a construction,
a call result, a local, a field and an index are each returned and then read
back AFTER 200 further allocations have had the chance to reuse a freed block,
so an over-release shows up as wrong data rather than as luck. The RSS pair
stays a manual measurement — a byte threshold in `make` would be a machine-
specific number, and the correctness test is what a regression would trip first.

## Gate

`make test-nilpy` + self-host byte-identical, plus the RSS-slope pair above
(both must be flat afterwards) and the existing reclamation tests.
