---
summary: "a local `array[0..N] of string` never releases its element handles at scope exit — merely FILLING one in a called procedure leaks linearly (~60 MB per 1M calls)"
type: bug
track: A
prio: 55
owner: claude-A
---

# Local static array of AnsiString leaks every element at scope exit

- **Type:** bug — Track A (codegen / scope-exit managed cleanup)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** Track A, while ARC-testing the fix for
  `bug-a-static-array-of-managed-whole-assign-loses-data`. **Pre-existing and
  independent of that fix** — measured on both sides of it, identical numbers.

## Repro

```pascal
procedure Round1;
var a: array[0..2] of string;
    i: Integer;
begin
  for i := 0 to 2 do a[i] := 'val' + Chr(48 + i);
end;
var k: Integer;
begin
  for k := 1 to 400000 do Round1;
  writeln('array done');
end.
```

No assignment between arrays, no aliasing — just filling the array. RSS grows
linearly with the call count:

| iterations | max RSS |
| --- | --- |
| 100 000 | 6.3 MB |
| 400 000 | 24.8 MB |
| 1 600 000 | 100.0 MB |

Perfectly linear (~62 bytes/iteration, three string handles). The identical
procedure with a plain `s: string` local instead of the array is flat at
264 KB, so the scalar scope-exit release works and only the ARRAY case is
missing.

## Diagnosis sketch (unverified — measure before writing it into a fix)

The whole-array *assignment* path proves the ingredients exist:
`PXXDynArrayRetainImmediate` / `PXXArrayReleaseImmediate` walk a raw element
buffer with an explicit count and no header, which is exactly the shape a
static array needs. The suspicion is that the proc-epilogue managed-cleanup
walk (`ProcHasManagedLocalCleanup` and friends in `symtab.inc`) considers a
symbol's own TypeKind but not `IsArray` + `ElemType`, so an array-of-string
local is simply not on the cleanup list. Confirm with `PXXDBG` / the emitted
epilogue before changing anything.

## Severity

Silent, unbounded growth in any hot procedure holding a static string array —
the shape that reads as "the process is just big" rather than as a bug. Not
data loss, so ranked below the assignment bug it was found next to.

## Interaction with the assignment fix

`b := a` now retains the source's element handles and releases the
destination's old ones (`IRManagedArrayCopy`). That accounting is correct in
itself and adds no leak on top of this one — measured: an elementwise copy loop
and a whole-array `b := a` reach the identical 24.96 MB at 400 000 iterations.
Once THIS bug is fixed, the assignment path's retain/release balances exactly
as intended; no change is needed there.

## Resolution (2026-08-05)

The diagnosis sketch was close but not right, and the difference matters.

It guessed the symbol was "simply not on the cleanup list". In fact
`SymNeedsManagedCleanup` **did** flag an `array[0..N] of string` — because an
array's `TypeKind` IS its element kind, so `TypeKind = tyAnsiString` matched.
The array then fell into the **scalar** AnsiString arm of the cleanup, which
does `mov rax, [rbp+off]; AnsiStrRelease` — releasing **element 0 only**.

Predicted from that reading and then measured, 400k calls:

| array | max RSS |
| --- | --- |
| 1 element | 264 KB (flat) |
| 3 elements | 24 960 KB |
| 6 elements | 62 464 KB |

Exactly **N-1** elements leak, which is what "the scalar arm frees the first
one" predicts. The guess of "not on the list at all" would have predicted N.

An array of managed RECORDS was the case the sketch actually described:
`SymNeedsManagedCleanup`'s record arm carries `not Syms[i].IsArray`, so no
cleanup was emitted and all N leaked.

**Fix.** A static-array arm in every backend's scope-exit cleanup, placed
BEFORE the scalar arms that would otherwise claim it, calling
`PXXArrayReleaseImmediate` — the header-free element walk added earlier today
for whole-array assignment, which already takes a raw buffer + explicit count
(a static array has no `[refcount][length]` prefix). N-D arrays are flat, so
`ArrLen` is the right count. `SymNeedsManagedCleanup` also gained the
array-of-managed-record case.

Five backends have their own cleanup loop; four got the arm (x86-64, aarch64,
arm32, riscv32). **xtensa was deliberately left alone** — it has no managed
dynarray/record heap helpers at all.

### Verified

| target | before | after |
| --- | --- | --- |
| x86-64 | 24 960 KB | **264 KB** |
| arm32 | 15 012 KB | 5 756 KB (baseline 5 524) |
| aarch64 | 17 748 KB | 6 384 KB (baseline 6 360) |
| riscv32 | — | 5 516 KB (baseline 5 456) |

Flat across 20k / 60k / 180k iterations on aarch64, i.e. genuinely flat rather
than smaller. Arrays of strings, of managed records, and 2-D arrays all fixed.
Correct output and no crash on all five targets; `-dPXX_HEAP_DEBUG` reports no
double-free or write-after-free.

**The prediction in `bug-a-static-array-of-managed-whole-assign-loses-data`
holds.** That ticket said its retain/release would balance exactly once this
landed, and it does: the whole-array-assign stress test went from 24.96 MB to
264 KB, identical for the elementwise and `b := a` spellings.

### i386 could not be measured, and why

i386 is the one target whose number did not go flat — and the residue is a
**different, much bigger, pre-existing** bug: a plain scalar
`var s: string; SetLength(s, 40)` local leaks ~150 MB per 60k calls there, on
`pinned` too. It swamps any managed-local RSS measurement on that target. Filed
as `bug-a-i386-scalar-string-local-never-released` (prio 60) with a 9-line
repro. The array arm IS emitted for i386 and is correct (output right, no
crash); its effect is simply unmeasurable until that one is fixed.

Locked in as `test/test_static_array_managed_scope_exit.pas`. It cannot assert
RSS portably, so it asserts what a correct release implies and a wrong one
breaks — values intact across 200 repeated calls, so a premature or double
release surfaces as corruption. Identical on all five targets and under FPC.

**Gate:** `testmgr --tier quick` 15/15; `selfhost_fixedpoint.sh` converges in 2
rounds from `pinned` and agrees with `compiler/pascal26`.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
