---
track: A
prio: 25
type: bug
blocked-by: []
status: done
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

## 2026-09-06 — SETTLED, by the method this ticket asked for (frank-coord-core)

This ticket said "do not rank this from the grep" and named the two conditions.
Both were checked per frontend. **No pad is needed for C, Rust or Zig today,
and one of the three is a near miss rather than a permanent no.**

| frontend | (1) can a body hold a managed local? | (2) can an exception unwind past it? | verdict |
| --- | --- | --- | --- |
| Pascal | yes | yes | asks — correct |
| NilPy | yes | yes | asks since 2026-09-04 — correct |
| C | yes | **no pxx exception** | no pad needed |
| Rust | **yes, measured** | **no — `panic!` is not implemented** | no pad needed TODAY |
| Zig | no | no | vacuous on both counts |

**How (2) was settled, and it is stronger than a slope measurement.** The pad
exists to run when an exception unwinds past a frame, so the question is whether
a frontend can produce an exception at all. Counting the AST nodes each frontend
CONSTRUCTS:

```
                 AN_TRY_EXCEPT  AN_TRY_FINALLY  AN_RAISE
pasparser_proc         0              1            0
pyparser               3              5            1
cparser                0              0            0
rparser                0              0            0
zparser                0              0            0
```

C, Rust and Zig never build an exception node. Nothing they compile can raise,
so nothing can unwind past their frames — that is not "we measured flat", it is
"the shape does not exist", which is the stronger of the two answers this ticket
asked us to distinguish.

**Rust is (1)-LIVE and only (2) saves it.** Measured: a Rust function holding a
`String` local compiles and runs (`let s = String::from(...)`, prints 14). What
is missing is the raise — `panic!("boom")` is refused with
`Rust: undefined variable panic`. **So the day `panic!` lands as an unwinding
construct, this ticket becomes real for Rust with no further change**, and
whoever implements it inherits two lines in `rparser.inc` beside its proc
epilogue. That is the one thing worth carrying forward from here.

**C's `setjmp`/`longjmp` is NOT this hole.** `cparser.inc:11286` emits real
setjmp/longjmp stubs (lua's error model rides them), so a C frame CAN be jumped
past. A landing pad would not fire — longjmp restores registers and never
consults the pad — and it must not: C semantics are that longjmp runs no
cleanup. Anything leaked across a longjmp is the program's, not ours.

**RESIDUAL, with an owner rather than a caveat.** An exception raised in
Pascal or NilPy code unwinding THROUGH a C/Rust/Zig frame is not expressible
today, because there is no way to call into another frontend's code — that is
[[feature-cross-frontend-interop-contract]], and the question returns with it.

Zig is vacuous on (1) as well: `zparser.inc` mentions no managed type kind at
all, so there is nothing in a Zig frame to release.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit aa2357a29.
