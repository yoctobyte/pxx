---
track: N
prio: 65
type: bug
blocked-by: []
---

# `def f(a, b=[])` SEGFAULTS the moment the default is used as a container

Found by proactive CPython-diff sweeping. A crash, so filed at higher
priority than the usual feature-gap findings from the same sweep.

```python
def f(a, b=[]):
    b.append(a)
    return b
print(f(1))
```
CPython prints `[1]` (with the well-known mutable-default-argument gotcha:
the SAME list object is reused and grows across calls — `f(2)` next would
print `[1, 2]`). pxx: `Segmentation fault (core dumped)`.

## Root cause

NilPy already has a DELIBERATE, documented simplification for a non-constant
default expression (`PyParamDefaultAt` in `compiler/pyparser.inc`, see its own
comment): a name, call, or list-literal default is not evaluated at
def-time (true Python semantics deferred to
`feature-nilpy-closure-default-and-remaining`); instead the parameter is
treated as an optional **None**-valued default and the token span is skipped.
That's fine for a `Variant`-typed parameter (`DefaultArgValueNode` in
`compiler/parser.inc` has an explicit branch: `isNilPy and (Params[k].TypeKind
= tyVariant) and (...IsNone or ...) then exprNode := PyMakeNone`).

But when body-usage inference pins the parameter's STATIC type to a class
(here `TPyList`, from `b.append(a)`/`return b` in the body) rather than a
generic `Variant`, `DefaultArgValueNode` falls through to its final `else`
branch instead:
```pascal
exprNode := AllocNode(AN_INT_LIT);
ASTIVal[exprNode] := ProcParamDefaultVal[mpi * MAX_PROC_PARAMS + k];  { = 0 }
ASTTk[exprNode] := Ord(Procs[mpi].Params[k].TypeKind);                { = tyClass }
if Procs[mpi].Params[k].TypeKind = tyVariant then
  ASTTk[exprNode] := Ord(tyInteger);                                  { skipped: not tyVariant }
```
This builds an integer-literal-0 node but TAGS it `tyClass` — which lowers to
passing a bare null pointer as `b`. The first container method call
(`b.append(a)`) then dereferences that null pointer directly, with no
None-check anywhere in the dispatch path: SIGSEGV.

## Fix direction (not attempted here)

Two independent angles, either sufficient to stop the crash:
1. **Cheapest, safe-but-approximate**: when a class-typed parameter's default
   falls to this branch, inject a genuine construction (`TPyList.Create` /
   the class's constructor call) as the default value instead of a null
   literal — gives "fresh empty container per call" rather than CPython's
   real shared-instance-across-calls aliasing, but is a strict improvement
   (no crash, and matches what most callers of this idiom actually *intend*,
   even though it isn't what CPython *does*). Needs generating a full
   AN_CALL/constructor sequence as a default-arg value node, likely requiring
   the same hidden-temp-and-hoist machinery bound method values already use
   elsewhere in this file — traced far enough to locate the bug precisely,
   not far enough to be confident injecting that construction safely across
   every `DefaultArgValueNode`/`FillDefaultArgs` call site without its own
   dedicated pass.
2. **General defensive fix**: make container instance-method dispatch
   (`TPyList`/`TPyDict`/etc.) null-check the receiver and raise a clean
   NilPy-style runtime error (mirroring CPython's `AttributeError: 'NoneType'
   object has no attribute 'append'`) instead of an unchecked dereference —
   protects against ANY accidentally-None class receiver, not just this
   default-arg path, but touches the shared method-call codegen broadly and
   needs its own gate pass to confirm no perf/behavior regression on the
   (extremely hot) ordinary non-None call path.

Either fix touches `compiler/parser.inc`/`compiler/pyparser.inc` under the
self-host gate. Scoped as its own ticket rather than attempted inline while
sweeping — a crash-class bug deserves a careful, dedicated pass rather than a
quick patch to default-arg machinery shared with every other parameter kind.

## Log
- 2026-07-31 — resolved, commit 8aa45e194.
