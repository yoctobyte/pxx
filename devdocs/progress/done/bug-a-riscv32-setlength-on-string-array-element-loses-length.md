---
track: A
prio: 55
type: bug
summary: "riscv32: an indexed CHAR WRITE into a string array element (a[i][1] := x) scribbles into the handle slot — Length() then reads 0. IR_INDEX was missing the field/array-element shape arm32 has. (NOT SetLength, as this ticket originally said.)"
owner: claude-A
---

# riscv32: `SetLength` on a string array element loses the length

- **Type:** bug — Track A (riscv32 backend)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** Track A, adding the static-array scope-exit release
  (`bug-a-local-static-array-of-string-never-released-at-scope-exit`). riscv32
  was the one target where releasing the elements **segfaulted**, and the reason
  is that its element handles are already malformed. **Pre-existing** —
  reproduced identically on `pinned`.

## Repro

```pascal
program rc;
var a: array[0..2] of string; i: Integer;
begin
  for i := 0 to 2 do begin SetLength(a[i], 4 + i); a[i][1] := 'x'; end;
  for i := 0 to 2 do writeln('len=', Length(a[i]), ' [1]=', a[i][1]);
end.
```

| target | |
| --- | --- |
| x86-64 / i386 / arm32 / aarch64 | `len=4 [1]=x` / `len=5 [1]=x` / `len=6 [1]=x` |
| **riscv32** | **`len=0 [1]=x`** ×3 |

The character write lands (`[1]=x`), so a buffer exists — only the LENGTH is
wrong. A **scalar** `SetLength(s, 5)` on riscv32 reads back `len=5` correctly,
so this is specific to an ARRAY ELEMENT as the target.

## Why it matters beyond the wrong length

`Length()` returning 0 for a non-empty string is silent and wrong on its own,
but it also makes the handle unsafe to walk: adding the ordinary scope-exit
element release for `array[0..N] of string` makes riscv32 **segfault**, where
the other four targets are clean. So this bug is currently keeping riscv32 on
the leaking path deliberately — see the comment at the riscv32 branch of
`EmitProcEpilog` in `compiler/symtab.inc`.

## Where to look

riscv32's `IR_SETLEN_STR` arm is structurally identical to arm32's (which
works): both push the slot address, load n, and call
`PXXStrSetLen(slotAddr, n)`. So the fault is more likely in the **slot ADDRESS**
handed to it — i.e. how riscv32 lowers an `IR_INDEX` on a string array in WRITE
position — than in the SetLength arm itself. Compare against arm32's
`IR_INDEX`/`InLValueWrite` handling, and print the address rather than reasoning
about it.

## Unblocks

`bug-a-local-static-array-of-string-never-released-at-scope-exit` — once this is
fixed, add the static-array release arm to the riscv32 branch of
`EmitProcEpilog` (copy arm32's, registers a0..a3) and riscv32 joins the other
four. The measurement to confirm is heap-address growth, not RSS: see that
ticket's note on why RSS under qemu is not a valid leak signal.

## Resolution (2026-08-05) — and the ticket named the wrong operation

**`SetLength` is not the culprit.** `SetLength(a[i], n)` on a string array
element reads back the right length on riscv32. Isolated:

    SetLength(a[0], 4)   -> Length 4   (correct)
    a[0][1] := 'x'       -> Length 0   (broken)

It is the indexed **char write**. The ticket's title and summary are wrong; the
measurement that led here — riscv32 disagreeing with four other targets on one
program — was right.

### Cause: one missing shape in riscv32's IR_INDEX

Diffing against arm32 shows it plainly. arm32 handles TWO shapes:

1. a SCALAR managed string (`IR_LEA`, not an array), and
2. a managed string that is itself a FIELD or ARRAY ELEMENT — `IR_FIELD` /
   `IR_INDEX` with `IRTk = tyAnsiString` and a 1-byte stride.

riscv32 had only (1). So for `a[i][1] := 'x'`, `a0` held the element's **slot
address** and neither the `PXXStrUnique` copy-on-write call nor the read-position
deref ran — the character was stored into the handle itself. Length then read 0,
and the handle was left malformed, which is exactly why walking it at scope exit
segfaulted.

The ticket guessed the fault was "more likely in the slot ADDRESS handed to
`PXXStrSetLen` than in the SetLength arm itself". Right neighbourhood — it IS a
slot-address-vs-handle confusion — wrong operation.

**Fix:** mirror arm32's arm, including its read-position derefs (by-ref param,
field/index). One condition and three instructions.

### Unblocks, and immediately used

This was blocking the riscv32 half of
`bug-a-local-static-array-of-string-never-released-at-scope-exit`, whose release
arm had been deliberately guarded off there to avoid trading a leak for a crash.
That arm is **restored in the same commit**, and riscv32 now joins the rest:

    scope-exit leak, heap-address growth, all five targets:
      x86-64 / i386 / arm32 / aarch64 / riscv32  ->  strings grew=0 records grew=0

### Verified

All five targets identical on the char-write case (scalar, array element, record
field, and read position), and byte-identical to FPC. `testmgr --tier native`
**1159/1159 pass**, including the self-host fixedpoint. Locked in as
`test/test_string_array_element_charwrite.pas`.

## Log
- 2026-08-05 — resolved, commit e33cf842b.
