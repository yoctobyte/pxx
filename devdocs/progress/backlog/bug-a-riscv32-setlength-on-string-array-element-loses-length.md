---
track: A
prio: 55
type: bug
summary: "riscv32: SetLength(a[i], n) on a string ARRAY ELEMENT leaves a malformed handle — Length() reads back 0 where every other target reads n. Scalar SetLength is fine. Blocks the scope-exit element release on that target"
---

# riscv32: `SetLength` on a string array element loses the length

- **Type:** bug — Track A (riscv32 backend)
- **Status:** backlog
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
