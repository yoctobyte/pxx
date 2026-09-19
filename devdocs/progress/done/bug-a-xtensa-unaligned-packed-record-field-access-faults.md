---
slug: bug-a-xtensa-unaligned-packed-record-field-access-faults
track: A
prio: 40
type: bug
status: done
created: 2026-09-18
found-by: frankH
owner: frankS
summary: "Any access to a packed-record field that is not naturally aligned dies with SIGBUS on xtensa: `packed record B: Byte; I: Integer; W: Word; end` and `r.I := n` -> `qemu: uncaught target signal 7 (Bus error)`. xtensa's l32i/s32i fault on a misaligned word; the backend emits them for a packed field at offset 1. Measured 2026-09-18 with HEAD 316bbefd65cd and with the typed-const-record change alike, --platform=posix. FIXED 2026-09-19: the frontend marks an IR_FIELD whose RECORD has any misaligned field (RecHasMisalignedField -- offsets, not the `packed` keyword, and all-or-nothing per record because an element of an array of them misaligns the base), and xtensa composes such loads/stores from l8ui/s8i. AND IT WAS TWO TARGETS: arm32 faulted too, on a Double field only -- its integer paths are plain ldr/str which ARMv7 absorbs, but `vldr d0,[r0]` does not, so a fixture without a float field reports arm32 clean. i386/aarch64/riscv32 measured clean. Guarded by test_pkfld26 plus six cross rows including both xtensa ABIs."
---

# Unaligned packed-record field access faults on xtensa

```pascal
program PK;
type TPk = packed record B: Byte; I: Integer; W: Word; end;
var r: TPk; n: Integer;
begin
  n := 5; r.B := 1; r.I := n; r.W := 3;
  WriteLn('I=', r.I);
end.
```

`--target=xtensa --platform=posix --xtensa-soft-mulhigh`, run under
`tools/run_target.sh xtensa`: `qemu: uncaught target signal 7 (Bus error)`.
x86-64 prints `I=5`.

`packed record` exists precisely to put fields at unaligned offsets (wire
formats, file headers), so this breaks real code on the ESP family, not an edge
case. The same class as the data-section alignment defect
(bug-a-a-perf-commit-silently-fixed-41-xtensa-windowed-divergences-and-nobody-knows-why),
one level down: there the section base was misaligned, here the field is by
design.

Found while differentially checking typed-const record baking. A packed record
CONST no longer faults at startup, because its bytes are baked now, but any
runtime access to `I` still faults.

Not checked: riscv32 (qemu tolerates misaligned access there, silicon may trap)
and arm32 (LDR alignment depends on SCTLR.A).

---

## Resolution 2026-09-19 (frankS, Track A) — fixed on xtensa AND on arm32

The ticket's last line, *"Other strict-alignment targets not checked"*, was the
load-bearing one. Checked: **arm32 was in this too**, and it is why that line
mattered — riscv32 and i386 and aarch64 are clean, arm32 is not, and the reason
arm32 looks clean to a casual fixture is worth stating because it will catch
the next person.

### What was wrong

A `packed record`'s whole purpose is fields at offsets the hardware does not
like. The backend emitted the ordinary sized load/store for them:

- **xtensa** — `l32i`/`s32i`/`l16ui`/`l16si` **fault** on a misaligned address.
  SIGBUS, every field wide enough to matter, on the primary ESP target.
- **arm32** — the INTEGER paths are two plain `ldr`/`str` and ARMv7 absorbs a
  misaligned word, so they were already right. The FLOAT path is
  `vldr d0,[r0]` / `vstr d0,[r0]`, and VFP does **not** absorb it: a `Double`
  field of a packed record bus-errored. `Int64` was fine for the same reason
  the integer path was. **A fixture without a float field reports arm32
  clean** — which is exactly what the original report did.
- i386, aarch64, riscv32 — clean as measured, both before and after.

### The predicate is the RECORD'S OFFSETS, not the `packed` keyword

`RecHasMisalignedField` (symtab.inc) walks a record's fields — and its parents,
and any nested record field — and asks whether any field's own offset violates
that field's `TypeFieldAlign`. It never looks at whether `packed` was written.
Two reasons, and the second is the one that decides the design:

1. A record can be ragged without the keyword (a nested ragged record makes its
   container ragged), and a `packed` record can be perfectly aligned.
2. **It is all-or-nothing per record, because the record's BASE may itself be
   misaligned.** With `SizeOf(TPk) = 7`, element 1 of an `array[0..3] of TPk`
   starts at base+7, so even the offset-0 field is misaligned there. A
   per-field rule — "use byte access when THIS field's offset is odd" — is
   correct for the first element and wrong for every other one. The fixture's
   last group walks that array for precisely this reason.

The answer travels as **one bit in `IRC` on the `IR_FIELD` node** (ir.inc, the
three append sites), set by `IRFieldRaggedBit`. It is target-agnostic on
purpose: the frontend states a property of the layout and each backend decides
what to do about it. xtensa and arm32 read it; the other four ignore it.

### The emitters

`EmitUnalignedLoadXtensa` / `EmitUnalignedStoreXtensa`
(ir_codegen_xtensa.inc) compose the value from `l8ui`/`s8i`. Two constraints
recorded at the code:

- **There is no shift-by-immediate on this ISA.** `ssl`/`sll` and `ssr`/`srl`
  latch SAR from a register, so the shift amount is latched **once** and each
  step is a bare `sll`/`srl`.
- They build in **a8/a9**, so `rd` may equal `rs` — which is what the wiring
  needs at `IR_LOAD_MEM`, where the address and the result are both a2.

**a8 IS A LIVE BASE REGISTER ELSEWHERE, AND THAT IS NOT A STYLE POINT — IT IS
THE MEASUREMENT THAT DECIDED THE WIRING.** The first attempt routed
`EmitSizedLoadXtensa`/`EmitSizedStoreXtensa` themselves through the unaligned
path, unconditionally, as an experiment. It printed `Hello, World!` and then
segfaulted. Four of their call sites (ir_codegen_xtensa.inc:316/323/344/351)
pass **a8 as the base**, which these helpers clobber. So the unaligned path is
wired only where the registers are a2/a3: `IR_LOAD_MEM` (scalar and the 64-bit
arm), `IR_STORE_MEM` (scalar, the 64-bit arm, and both branches of the float
arm).

arm32 does not need byte composition at all — it needs the **integer file it
already had**. `Arm32AddrIsRagged` gates the float arms onto the same
`ldr`/`str` pair the Int64 arm uses, then `vmov` between core registers and
d0/s0. Nothing there is a wider alignment claim; it is the same two loads that
were already correct one arm over.

### Guard

`test/test_a_packed_record_field_reads_and_writes_at_any_offset.pas`, wired as
`test_pkfld26` plus six cross rows (i386, arm32, riscv32, aarch64, xtensa
Call0, **xtensa windowed** — the windowed row is not decoration, it is what
would catch a8/a9 clashing with the window ABI's own use).

**Every row is a VALUE, not an offset**, and the cross rows compare against the
x86-64 run of the same source, because where the fields LAND differs
legitimately per target while what comes back out of them may not. The signed
narrow fields (`SmallInt` at 17, `ShortInt` at 19) are there because a
byte-composed load that forgets to sign-extend turns -30000 into 35536 and an
unsigned-only fixture certifies that. Read-modify-write through the same field,
so a bad load and a bad store cannot cancel into a right-looking answer.

Positive control, measured before the fix: xtensa `qemu: uncaught target
signal 7 (Bus error)`; arm32 `q -> -5` (fine) and `d -> Bus error` (the
isolation that found the float arm).

Status: done.

### The walk's first cut crashed the compiler, and how it was caught

`RecHasMisalignedField` originally recursed on `UFldRec_[i] >= REC_UCLASS_BASE`
— "this field has a record id". **`UFldRec_` is populated for a CLASS field as
well**, and a class field is a pointer, so `TNode = class Next: TNode` — legal,
ordinary, and in half the RTL — recursed without bound. **23 of 60 `lib/rtl`
root units segfaulted the compiler.**

The field's record id is not the question; the field's KIND is. Fixed with
`UFldTk[i] = Ord(tyRecord)`, self-exclusion and a depth cap — which is exactly
the idiom `RecordHasManagedFieldsDepth2` already had 400 lines above in the
same file, with a comment recording the same hazard arriving from a C
struct-tag redefinition. A new walk was written where the one next door should
have been read.

**Caught by `gate.sh quick`'s HEAD rtl canary and by nothing cheaper.**
`make compiler/pascal26` converged, the fixture passed on all six targets, and
`testmgr --tier quick` would have passed as well: `compiler.pas` is a
deliberately procedural subset with no self-referential class in a
raggedness-relevant position, so the whole defect lives in code the self-host
build never writes — the second scope limit in CLAUDE.md's per-fix loop,
arriving exactly as written.

The same gate run caught the other half in the same pass: `TypeFieldAlign` is
declared ~4,400 lines BELOW its new caller. pxx resolves across the unit and
FPC resolves in source order, so the **seed** build would have broken. One
`forward;` at the top of `symtab.inc`, and the FPC seed canary is again the
only row that can see it.

Both are pinned by the fixture's last group — a self-referential class that
also holds a ragged record by value, so the walk has a real reason to look at
its fields rather than bailing on the class early. **The assertion there is
that the file BUILDS**, because the failure mode is a compiler crash and not a
wrong value.
