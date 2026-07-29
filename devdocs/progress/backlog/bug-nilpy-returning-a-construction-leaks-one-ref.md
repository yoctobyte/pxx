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

## Gate

`make test-nilpy` + self-host byte-identical, plus the RSS-slope pair above
(both must be flat afterwards) and the existing reclamation tests.
