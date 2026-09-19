---
slug: bug-n-a-subclass-of-a-class-with-a-flattened-base-calls-through-a-nil-vmt-slot
title: A subclass of a class with a flattened base calls through a nil VMT slot
track: N
type: bug
prio: 45
status: backlog
owner: ""
created: 2026-09-19
found-by: frankH
tags: [nilpy, multiple-inheritance, vmt, crash]
blocked-by: []
summary: "`class E(D)`, where D itself has a flattened base (`class D(P, Tag)`): EVERY method call on an E instance jumps to address 0 (SIGSEGV), including a method E inherits through D's REAL parent chain. Calls on a D instance work, and so do construction, isinstance and type(e).__name__. Present in pinned v411 as well as at HEAD, so it predates the flattened-base RTTI work. The suspect, not verified: E copies D's VMT slot count and slot table before D's flattened body is registered. That would explain a flattened method's slot but not an inherited one's."
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
