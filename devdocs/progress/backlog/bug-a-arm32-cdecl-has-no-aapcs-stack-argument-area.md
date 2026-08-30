---
track: A
prio: 45
type: bug
status: open
found: 2026-08-30
found-by: claude-A
---

# arm32 cdecl refuses any argument block over 4 core registers — so arm32 only HALF-joins the cdecl campaign

armel AAPCS soft-float places every argument, floats included, in the core
registers r0..r3 and then on the STACK. pxx implements the register half and
refuses the rest, on both sides of the call:

```
target arm32: external call argument block exceeds 4 core registers (stack args not supported yet)
target arm32: cdecl indirect call argument block exceeds 4 core registers (stack args not supported yet)
target arm32: a cdecl routine whose argument block exceeds 4 core registers is not supported yet
```

The third is new, added with arm32's AAPCS prologue arm so that the callee
refuses exactly what the caller refuses. An honest refusal on both sides beats a
prologue reading words the caller never wrote.

## Why this ticket exists rather than a footnote

`bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets`
gives arm32 a genuine AAPCS prologue, and after it arm32 is correct for every
signature it accepts. **It is not correct for every signature** — it simply
refuses the rest. A target that is done for signatures fitting in 16 bytes and
unsupported past that reads as complete a month later, so the boundary is
written down here.

**What arm32 does NOT support, concretely.** The argument block counts 4 bytes
per int/single/pointer and 8 bytes (8-byte aligned) per by-value
Double/Extended/Int64/UInt64. Over 16 bytes is refused. So:

| signature | block | arm32 |
| --- | --- | --- |
| `(a: Double; b: Integer)` | 12 | works |
| `(a: Integer; b: Double)` | 16 (r1 skipped for alignment) | works |
| `(var a: Double; b: Integer)` | 8 | works |
| `(i1: Integer; d1: Double; i2: Integer; d2: Double; ...)` | 40 | **refused** |
| any 5+ integer params | 20 | **refused** |

That last row is ordinary Pascal, which is why this is filed as a bug and not a
limitation note. `test/test_cdecl_bodied_cross.pas` cannot be compiled for arm32
for exactly this reason, and `test/test_cdecl_bodied_narrow.pas` exists to hold
the signatures arm32 can express.

## The work

An AAPCS stack argument area, on both sides:
- caller (`ir_codegen_arm32.inc`, both the direct `IR_CALL` external/cdecl arm
  and the `IR_CALL_IND` cdecl arm): grow the block past 16 bytes and place the
  overflow on the stack above the register words.
- callee (`ir_codegen.inc`, the `ProcCdecl` arm of `EmitParamSpillsForTarget`):
  read words 4.. from the incoming stack area instead of erroring.

Both sides must move together, and the two `Error` calls above are the marker
for where. The positional (non-cdecl) arm32 path already spills stack words at
`[fp + 8 + (pnWords-1-k)*4]`; the AAPCS incoming layout is NOT the same and must
not be copied without checking — AAPCS pushes in argument order with the lowest
index at the lowest address, and the positional path deliberately does the
reverse.

## Gate

`test/test_cdecl_bodied_cross.pas` compiles and passes for arm32, which it
cannot today. Add arm32 to that file's Makefile rows when it does.


## WHOEVER LIFTS THIS REFUSAL: the layout behind it is also wrong (2026-08-30)

The refusal above is what makes arm32's stack-argument layout unreachable — and
therefore invisible. It is recorded here rather than only in the riscv32 ticket
because **the person who removes this refusal is the person who needs to know**,
and they will be reading this page.

arm32 uses the same **descending** overflow layout riscv32 used until
`bug-a-riscv32-passes-stack-arguments-in-reverse-psabi-order`: word *k* at
`[fp + 8 + (pnWords-1-k)*4]`, at `ir_codegen.inc:1409/1412/1425` and
`cparser.inc:11133`. **AAPCS32 specifies ascending stack arguments**, so lifting
the >4-word refusal without also fixing the order would expose the same
pxx↔C divergence riscv32 had — silently, because pxx↔pxx agrees with itself.

**Not measured against a real arm32 gcc.** riscv32's was measured from both
sides against `riscv32-esp-elf-gcc` 15.2.0; no arm32 cross toolchain is
installed on this box, so this is a same-shape inference from the source, not an
oracle result. Treat it as a thing to check first, not a thing to assume.

And when checking it: on riscv32 the equivalent bug was **invisible at nine
words**, where the descending and ascending formulas coincide. Pick a case with
enough words that the two orders actually differ.
