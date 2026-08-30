---
track: A
prio: 70
type: bug
status: done
found: 2026-08-30
found-by: claude-A
owner: claude-A
---

# A C program's own functions took the C-ABI call path on aarch64 and arm32

**Mine. Introduced by `eeb51710e` (aarch64) and `6d2939f38` (arm32), the cdecl
prologue arms.** Track T filed five NEW-REDs against it.

The aarch64/arm32 direct-call sites were taught to route `ProcCdecl` procs onto
the C-ABI marshalling path, so that bodied Pascal `cdecl` procs — which now have
a matching C-convention prologue — would be called correctly:

```pascal
if ProcExternal[procIdx] or ProcCdecl[procIdx] then
```

**The C frontend marks EVERY C function `ProcCdecl`, and a C-DEFINED function is
not `ProcExternal`.** So that expression dragged every function of every C
program onto the C-ABI path — where `cparser.inc`'s own prologue spill is
**positional**, not AAPCS, on exactly these two targets.

## Two symptoms, one cause

| | mechanism | how it presented |
| --- | --- | --- |
| `nine(a..i)` — 9 params | the C-ABI path refuses >8 args (aarch64) / a >16-byte block (arm32); the internal path has no such limit | **build refusal** — `test-lua-cross`: `external call with more than 8 parameters not supported` |
| `mix(int,double,int,double)` | marshalled AAPCS, received positionally | **wrong output** — four `test-c-conformance-aarch64` shards |

A refusal and a wrong value looked like two defects. They are one expression.

**x86-64 was never affected by the identical expression at `ir_codegen.inc`'s
`IR_CALL`,** because `cparser.inc`'s x86-64 spill really is SysV — caller and
callee agree there. The two targets where the halves disagree are precisely the
two that broke.

## Fix

```pascal
if ProcExternal[procIdx] or (ProcCdecl[procIdx] and (not CProgramMode)) then
```

In Pascal mode `ProcCdecl` implies the target has the prologue arm, which is what
makes the path safe. In C mode the callee's prologue is positional, so the call
must stay internal.

## The part worth reading twice

**This exact lesson was already written in the file, ~190 lines below the line I
changed**, on the `IR_CALL_IND` arm which has carried `and (not CProgramMode)`
for months:

> *PASCAL-mode only: the C frontend marks every C fnptr signature ProcCdecl, but
> a pxx-COMPILED callee reached through one uses pxx's internal convention —
> C-mode indirect calls keep the internal path, or lua's dispatch and sqlite's
> VFS miscompile (tstate caught exactly that at b362).*

Same file, same predicate, same two victims (lua, and a C corpus), and it had
already been paid for once at `b362`. I read that comment while surveying the
file and did not apply it to the direct-call arm. **A comment recording a bug is
not a guard against it** — the indirect arm was protected by a condition, the
direct arm by a paragraph, and only one of those is executable.

## Gate

`test/ccross_cdecl_cmode.c`, new, wired for i386/aarch64/arm32/riscv32. It
**fails to build** on aarch64 and arm32 at `83a767151ffa` with the two error
messages above, and prints `CDECL-CMODE OK` on all five targets with the fix.

The lua tree and the c-testsuite corpus are both absent from this checkout, so
the two originally-reported failures were **not** reproduced directly; the
mechanism was reproduced from synthetic C, yielding the reported error string
verbatim. Re-check the five tstate jobs against the fix.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
