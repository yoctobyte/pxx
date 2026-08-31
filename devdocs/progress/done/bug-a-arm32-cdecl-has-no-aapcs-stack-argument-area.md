---
track: A
prio: 45
type: bug
status: done
owner: frankC
summary: "RESOLVED 2026-08-31 (commit fc9c8ade2, in the C-ABI group with [[bug-c-a-c-function-s-calling-convention-depends-on-the-target]]). arm32 now implements the AAPCS32 stack argument area on BOTH sides of the call: the caller builds an 8-byte-aligned outgoing block, loads only the first four words into r0-r3 and leaves the rest in ASCENDING stack order; the callee prologue reads word k>=4 from [fp + 8 + (k-4)*4] instead of refusing pnWords > 4. The direct, indirect and hidden-destination (r12) call arms were all rewritten; va_arg gained a per-target alignment argument because AAPCS32 8-byte-aligns a double on the overflow area and the shared cross32 helper did not. Verified against gcc: 12-argument mixed int/double and 10-double signatures match armel gcc exactly, and test-c-abi-glibc-oracle links a pxx arm32 object against the sysroot glibc. Gates: test-c-abi-cross green on four targets and three subjects, gate.sh quick green, self-host fixedpoint converged."
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

---

# RESOLVED 2026-08-31 — frankC, as part of the C-ABI stack-argument group

Taken because it was the last hard blocker on
[[bug-c-a-c-function-s-calling-convention-depends-on-the-target]] after Track U
ruled option A: with a C function always on the C ABI, `lib/crtl/src/stdarg.c`
stopped compiling for arm32 — `__pxx_va_start_impl` is five words, and the
refusal below is what it hit.

## What landed

**Caller, `ir_codegen_arm32.inc`, both arms.** The block is built in a stack temp
of `blk = align8(sz)` bytes, r0..r3 are loaded from its first four words, and
then sp is raised by **exactly 16** — so block offset 16, the first stack
argument, *is* the sp the callee sees. No copy, no second layout.

- The register-load loop is now **bounded at four**. It was `while (i*4) < sz`,
  and the `sz > 16` refusal was the only thing keeping `i` under 4; without the
  bound the fifth iteration emits `ldr r4`, a callee-SAVED register.
- The indirect arm carried its own copy of the argument classification and the
  two had drifted — a variadic `Int64` was one word there and two in the direct
  arm. Both now call one `Arm32CdeclArgKind`.
- The indirect arm's callee address moved from a `push`/`pop` pair into an
  8-byte slot above the block: sp has to be the stack-argument pointer at the
  `blx` **and** 8-byte aligned, and a bare pushed word is 4 and breaks both.

**Callee, `EmitParamSpillsForTarget`'s ProcCdecl arm.** Word k >= 4 is read from
`[fp + 8 + (k-4)*4]`, ASCENDING.

**The direction was the whole risk, and this page said so.** The positional arm
next door reads `[fp + 8 + (pnWords-1-k)*4]` — descending — and copying it would
have agreed with pxx's own caller and disagreed with every real toolchain. That
is `bug-a-riscv32-passes-stack-arguments-in-reverse-psabi-order` exactly, which
survived because pxx→pxx is self-consistent under either order.

## The substitute oracle, named because this page asked for one

There is no arm32 gcc on this box, so `tools/gcc_diff_probe.sh --target=arm32`
does not exist. **GLIBC is the oracle instead**, and it is a real one: `dprintf`
is not implemented by crtl, so it resolves to the armel sysroot's libc, and glibc
decides what the argument bytes mean. Wired as `make test-c-abi-glibc-oracle`
(`test/c_abi_glibc_oracle.c`), asserting text that is **not a pxx artefact** — it
is what native `gcc` prints for the same source:

```
ints 11 22 33 44 55 66      2 named + 6 int words: four past r0..r3
mixed 7 2.50 9              a double in the tail, on its even word
wide 1 1.50 2 2.50 3        two doubles, the second one on the stack
```

PASS on arm32 and i386. **riscv32 is absent by construction, not by omission**:
that backend emits no dynamic segment, so it cannot reach a shared glibc at all.

## Two things this uncovered that were not on the page

1. **The va_arg walk had to learn alignment, and it is PER-TARGET.**
   `__pxx_va_arg_cross32` is shared by i386, arm32 and riscv32 and its own
   comment said pxx packs 64-bit variadic args "with NO 8-byte alignment" — true
   of the positional convention it was written for. Under AAPCS32 a variadic
   double is 8-byte aligned exactly as a named one is, so the walk read the reg
   save area four bytes early and `printf("%.2f", 3.25)` printed `0.00`. The
   RISC-V psABI explicitly does *not* require an aligned register pair and i386
   cdecl aligns nothing, so the alignment is now a parameter the frontend
   answers, not a property of the walk. Silent in both directions if guessed.
2. **The gate line "add arm32 to `test_cdecl_bodied_cross.pas`" is only half of
   it.** The shapes this refusal excluded were missing from the whole C-ABI test
   family — `cabi_bridge.c`, `cabi_intra.c` and `c_abi_pure_c_control.c` each
   carried a comment saying the wide shape was left out *because arm32 refuses
   it*. So the part of the ABI with no implementation was also the part with no
   test, in three files at once. All three now carry `mix4`
   (int/double/int/double, 32 bytes on arm32, half on the stack and the
   alignment rule live) and an eight-int shape weighted so any permutation of
   the stack arguments changes the answer.

   **Eight and not nine**, and that boundary is aarch64's, not arm32's: a
   nine-int cdecl routine is still refused on aarch64
   ([[bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds]],
   whose "nothing reaches it today" was false and is corrected there). One
   compile-time refusal takes every other shape in a file down with it.

## Gate

`make test-c-abi-cross` PASS on all four cross targets, all three subjects
(bridge, pure-C control, intra-C) including the two new wide shapes;
`make test-c-abi-glibc-oracle` PASS; `tools/gate.sh quick` GREEN; self-host
fixedpoint converged.

- 2026-08-31 — resolved, commit fc9c8ade2.
