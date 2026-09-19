---
slug: bug-n-a-subclass-of-a-class-with-a-flattened-base-calls-through-a-nil-vmt-slot
title: A subclass of a class with a flattened base calls through a nil VMT slot
track: N
type: bug
prio: 45
status: done
owner: frankH
created: 2026-09-19
found-by: frankH
tags: [nilpy, multiple-inheritance, vmt, crash]
blocked-by: []
summary: "MECHANISM: the NilPy member pre-pass lays a class out early (hoists it) when its parent is settled, and DEFERS to PyParseClass a class whose parent is not — one with several bases, a mixin base, or an unresolved one. It checked only that the parent was RESOLVED, not that the parent had been LAID OUT, so a single-base subclass of a deferred class (`class E(D)` under `class D(P, Tag)`) was laid out against a D of size 0 with no virtual slots. Every slot D owns was nil in E's VMT (a jump to 0, SIGSEGV, no diagnostic), and E's OWN methods took slot numbers D's methods already held — so `E().who()` silently ran E's first method instead of the inherited one, a wrong call with a plausible value, worse than the crash. BLAST RADIUS: any subclass of any class with two or more bases, an ordinary Python shape; not a regression — pinned v411 has it too. FIXED 2026-09-19: a class whose parent was deferred is deferred as well (PyLayoutDeferred), so it is laid out after its parent. Test: test_nilpy_a_subclass_of_a_multiply_inheriting_class_is_laid_out_after_it."
---

# Repro (17 lines, CPython prints `tag`)

```python
class Tag:
    def tag(self) -> str:
        return "tag"


class P:
    pass


class D(P, Tag):
    pass


class E(D):
    pass


e = E()
print(e.tag())
```

Measured 2026-09-19 with pxx at HEAD after 578c9c39e, and with pinned v411:

- Both compilers: SIGSEGV. The gdb backtrace shows frame #0 at 0x0 and #1 at the call site.
- `print(e.who())`, with `who` inherited from a real ancestor `Root` of `P`, also SIGSEGVs.
- `e = E(); print("made"); print(isinstance(e, Tag)); print(type(e).__name__)` runs correctly.
- `d = D(); d.tag()` runs correctly.

# Where to look

- The VMT fill is at the end of the NilPy class layout (`UClsVMTOffset[ci] := DataLen`
  in pyparser.inc). It walks the parent chain for slots the class does not override.
- The slot count is inherited once, at `UClsVirtCount[ci] := UClsVirtCount[UClsParent[ci]]`.

Measure both for E before theorising. In particular, find out why an inherited
REAL-chain slot is nil too, which the ordering suspect does not explain.

Not on That Space Program's path: its only two-base class, `EphemerisMissing`,
has no subclass.

## 2026-09-19 — FIXED (frankH)

The suspect above was wrong, and the observation it could not explain was the
tell. Measured with gdb on the repro: the call is `call *0x20(%rax)` (slot 4)
through E's VMT, and E's whole VMT is zero. Varying the shape settled it:
`E().who()` (inherited from P through D's REAL parent) printed **"own"**, E's
own first method. So E's slot count started at the root's, not at D's.

Cause: `PyClassHeaderSweep` hoists a class's full registration when its parent
is resolved, and defers a class with several bases to PyParseClass. `E(D)` has
one base, D resolves, so E was hoisted, and laid out before D's statement had
laid D out (size 0, `UClsVirtCount` still the root count). The VMT fill was
correct about the numbers it was given.

Fix (pyparser.inc): `PyLayoutDeferred[ci]` records a class the pre-pass
declined; a subclass of one declines too. It is transitive because a Python
base precedes its subclass in the source.

Test: test_nilpy_a_subclass_of_a_multiply_inheriting_class_is_laid_out_after_it,
.expected is CPython 3.14.4's output. It covers a flattened method, a method
inherited through the real chain two levels up, a field from the parent's
`__init__`, the subclass's own method, an override one level further down,
dispatch through a base-typed name, and isinstance. Pinned v411 (bc884808fda5)
SIGSEGVs on it.
