---
slug: bug-a-three-pxxsys-primitives-return-a-plausible-fd-on-wasm32
title: "PXXSysOpenRO / PXXSysClose / PXXSysLseek have no wasm32 arm and return a plausible SUCCESS value"
track: A
prio: 55
type: bug
status: done
owner: ""
created: 2026-08-29
found-by: frankwasm (sizing the builtins refusal block)
summary: "PXXSysOpenRO, PXXSysClose and PXXSysLseek in compiler/builtin/builtinheap.pas are ifdef chains with arms for x86-64/i386/arm32/aarch64 and NO CPU_WASM32 arm and no else. On wasm32 the body is empty, Result is never assigned, and the functions return whatever is in the result slot -- measured as 7, 6 and 6, where native returns -14, -9, -9. These are not garbage-looking values: 7 is a plausible file descriptor, so `if fd < 0 then error` passes and the caller reads a file it never opened. Same family as bug-a-pxxsyswrite-has-no-wasm32-arm (done) and HeapMmap, and the same failure direction: FAIL OPEN. The minimal fix is an explicit error return, not a WASI implementation."
---

# The measurement

```pascal
program fo;
begin
  writeln('openro=', PXXSysOpenRO(nil));
  writeln('close=',  PXXSysClose(7));
  writeln('lseek=',  PXXSysLseek(7, 0, 0));
end.
```

| | native x86-64 | `--target=wasm32` |
| --- | --- | --- |
| `PXXSysOpenRO(nil)` | `-14` (EFAULT) | **`7`** |
| `PXXSysClose(7)` | `-9` (EBADF) | **`6`** |
| `PXXSysLseek(7,0,0)` | `-9` (EBADF) | **`6`** |

The wasm module reports `123 of 123 bodies lowered — op coverage is complete
for this program`. Nothing warns.

# Why

`compiler/builtin/builtinheap.pas:1861`, `:1877`, `:1893` are the same shape:

```pascal
function PXXSysOpenRO(path: Pointer): Int64;
begin
{$ifdef CPUX86_64} Result := __pxxrawsyscall(2, Int64(path), 0, 0); {$endif}
{$ifdef CPU_I386}  ... {$endif}
{$ifdef CPU_ARM32} ... {$endif}
{$ifdef CPUAARCH64} ... {$endif}
end;
```

Four arms, no `CPU_WASM32`, **no `else`**. On a seventh target the body is
empty and `Result` is never assigned.

**The severity is in the VALUE, not the absence.** An unassigned result that
came back as 0 or a large negative would be caught by the first sanity check.
`7` is in the range a real `open` returns, and it is stable across runs, so it
survives every plausible caller guard. `PXXSysClose` returning `6` reads as
success.

# Relation to the family

`PXXSysWrite` in the same file had exactly this hole and was fixed
(`bug-a-pxxsyswrite-has-no-wasm32-arm`, done) by adding a `CPU_WASM32` arm over
`__wasi_fd_write`. These three were not swept at the same time. `HeapMmap` is
the third member and is still ungranted.

That makes this the **fourth** instance of one pattern in one file: a
per-target ifdef chain with no terminal `else`, where a new target gets silence
instead of a diagnostic. Worth fixing as a class -- an `{$else} Result :=
PAL_ERR_UNSUPPORTED; {$endif}` on every chain in the file would have made all
four fail closed on the day wasm32 was registered.

# The fix, and what it is NOT

**Minimal and correct: return an explicit error on wasm32.** That converts fail
open to fail closed, which is this project's stated preferred direction --
`bug-a-emitzeroframeslot-has-no-wasm32-arm` is prio 55 rather than 70
*precisely because* it fails loud.

**It is deliberately NOT "implement these over WASI".** A real `PXXSysOpenRO`
needs WASI's preopen resolution, rights computation and errno mapping, which
already exist once in `lib/rtl/platform/wasi/platform_backend.pas` and which
`compiler.pas` cannot reach -- it links no PAL by design. That is a separate
design fork, filed as
`decide-how-the-sys-intrinsics-reach-wasi-when-the-compiler-links-no-pal`.
Fixing the failure DIRECTION here does not depend on settling it, and should
not wait for it.

# Gate

Track A's: `make compiler/pascal26` plus the repro above on both targets. The
wasm32 column must stop reporting plausible success.

## Log
- 2026-08-29 — resolved, commit 4eeadadc4.

## Resolved 2026-08-29 — with the sibling, as one defect

Fixed by the chain restructure in
[[bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open]]; see that ticket for the
measurements, the three corrections it needed, and what was deliberately left.

**The severity argument in this ticket is the one that carried the fix, and it
should be quoted forward: the severity is in the VALUE, not the absence.** 7 is
a plausible file descriptor and it is stable across runs, so `if fd < 0 then
error` passes and the caller reads a file it never opened. A 0 or a large
negative would have been caught by the first sanity check. That is why this
outranked "a target is missing an arm" as a framing.

`PXXSysOpenRO/Close/Lseek` now return **-1** on any target with no arm —
verified on riscv32 with this ticket's own reproducer (`-1/-1/-1`, native
unchanged at `-14/-9/-9`) and by IR dump (`IR count=1`, an empty body, becoming
`Result := -1`).

**Not a wasm32 fix.** wasm32 cannot codegen this unit here at all
("wasm32: code generation not implemented"), so the measurement was taken on
**hosted riscv32**, an armless target that does build. The fix is target-shaped
rather than wasm-shaped, so it covers wasm32, riscv32 and xtensa/IDF at once —
and the next target too, which was the point.

## Log
- 2026-08-29 — resolved with the root-cause sibling. 4eeadadc4

## CORRECTION 2026-08-29 — `{$error}` exists; see the sibling ticket

This ticket's proposed compile-time refusal was available all along. It is
still not the right terminal here, but for a reachability reason rather than
an availability one: `{$error}` fires when `builtinheap.pas` is COMPILED, and
that file is compiled into every program on every target, so it would refuse
every wasm32/xtensa build including programs that never open a file. Full
correction, and how the wrong answer was produced, in
[[bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open]].
