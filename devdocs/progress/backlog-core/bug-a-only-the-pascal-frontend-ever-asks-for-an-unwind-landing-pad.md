---
track: A
prio: 25
type: bug
blocked-by: []
status: backlog
summary: "UNMEASURED SIBLING, filed from a grep and named as one. The unwind landing pad that releases a frame's managed locals when an exception unwinds PAST it is shared machinery, but the REQUEST for one (`ProcCleanupFrameWanted := True`) was written only in pasparser_proc.inc until 2026-09-04, when the same two lines were added to pyparser.inc for a measured 1-block-per-managed-local-per-raise leak. The C, Rust and Zig frontends still never ask. Whether that is a defect depends on whether their bodies can hold a managed local AND be unwound past — not established here."
---

# Only the Pascal frontend ever asks for an unwind landing pad

## The evidence, and exactly what it is

```
$ grep -rn 'ProcCleanupFrameWanted := True' compiler/
compiler/pasparser_proc.inc:2793
compiler/pasparser_proc.inc:2823
compiler/pyparser.inc:30816        <- added 2026-09-04
```

That is the whole finding. The pad itself
(`EmitProcCleanupLandingPadForTarget`), the late gate inside `CompileAST`, and
six backends' `IR_EXC_ENTER` are all in shared files and all work; a frontend
that never sets the flag simply never gets one, silently, because an unwind leak
prints nothing and corrupts nothing.

For Nil-Python this was a real leak, measured at one heap block per managed
local per raise —
[[bug-nilpy-a-managed-local-in-an-unwound-frame-is-never-released]].

## What is NOT claimed

That C, Rust or Zig leak. Two things have to be true for that, and neither is
established:

1. a body in that frontend holds a local with a managed kind
   (`ProcHasManagedLocalCleanup` would answer yes), and
2. an exception can unwind past that frame.

`zparser.inc` mentions no managed kind at all, so (1) may be vacuous there. C
locals are raw pointers with no ARC; `cparser.inc` names `tyAnsiString` in four
places, none of them obviously a plain local. **Do not rank this from the grep
— the whole point of the NilPy case was that a slope measurement, not a
reading, is what settled it.**

## How to settle it, cheaply

Per frontend: a function holding a managed local, an exception raised past it in
a loop, built `-dPXX_ALLOC_CENSUS`, `live` compared at N=2000 and N=8000. Flat
means the row is either correct or unreachable — and **those two are not the
same answer**, so say which. If a frontend cannot express the shape at all, the
right outcome is a line here saying so, not a pad.
