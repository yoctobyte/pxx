# `lib/asmcore` — functional design

Layer 1 of the assembler umbrella ([[feature-assembler-first-class-citizen]],
ticket [[feature-asmcore-encoder-library]]). Mechanical encode/decode only —
no labels, no symbol table, no compiler dependency. Plain procedural units,
no classes (see ticket for why).

## Directory / unit layout

```
lib/asmcore/
  asmcore_base.pas      shared types: operands, patch sites, byte buffer
  asmcore_x64.pas        x86-64 encode + textual print
  asmcore_i386.pas       (i386 — subset of x64, REX disabled)
  asmcore_aarch64.pas
  asmcore_arm32.pas
  asmcore_riscv32.pas
  asmcore_xtensa.pas
```

One unit per target, mirroring the existing `asmtext_<target>.inc` split —
same reason those were split (target-specific instruction sets shouldn't
live in one file), done as real units instead of includes. All target units
depend on `asmcore_base`; **never on each other** — shared logic belongs in
`asmcore_base`, not borrowed sideways between target units. That's the whole
fix for the "units have reference problems too" risk: one shared base, a
flat fan-out of target units, no cycles possible by construction.

## Core types (`asmcore_base.pas`)

```pascal
unit asmcore_base;

interface

type
  TAsmOperandKind = (opReg, opImm, opMem, opPatch);

  TAsmOperand = record
    Kind: TAsmOperandKind;
    Reg: Integer;          { register number, target-defined constant }
    RegSize: Integer;      { width in bytes, where it matters (x64) }
    Imm: Int64;
    MemBase: Integer;      { -1 = none }
    MemIndex: Integer;     { -1 = none }
    MemScale: Integer;     { 1/2/4/8 }
    MemDisp: Int64;
    PatchWidth: Integer;   { 0 = not a patch site; else 1/2/4/8 }
  end;

  TAsmInstr = record
    Mnemonic: AnsiString;
    Operands: array[0..3] of TAsmOperand;
    OperandCount: Integer;
  end;

  TAsmPatchSite = record
    Offset: Integer;        { byte offset into the output buffer }
    Width: Integer;         { 1/2/4/8 }
    OperandIndex: Integer;  { which operand produced this, caller bookkeeping }
  end;

  TAsmByteBuf = record
    Bytes: array of Byte;
    Len: Integer;
  end;

  TAsmPatchList = record
    Items: array of TAsmPatchSite;
    Count: Integer;
  end;

function RegOp(reg, size: Integer): TAsmOperand;
function ImmOp(v: Int64): TAsmOperand;
function MemOp(base, disp: Integer): TAsmOperand;
function PatchOp(width: Integer): TAsmOperand;

procedure BufAppend(var buf: TAsmByteBuf; b: Byte);
procedure BufAppendI32(var buf: TAsmByteBuf; v: Int64);
procedure PatchAdd(var list: TAsmPatchList; offset, width, operandIndex: Integer);

implementation
{ ... amortized-growth append (double capacity on overflow), same shape as
  the compiler's own CodeLen/CodeBuf pattern. }
end.
```

`TAsmOperand` deliberately has no x86-specific concept (no ModRM/SIB field)
— addressing-mode quirks stay local to `asmcore_x64.pas`'s encode functions.
`MemBase`/`MemIndex`/`MemScale`/`MemDisp` is general enough for x64's
`[base+index*scale+disp]` and degrades cleanly for simpler targets
(aarch64/arm32/riscv32 mostly use `MemBase+MemDisp`, no index/scale; xtensa's
load/store is base+immediate-offset, same fields, `MemIndex = -1` always).

## Per-target unit contract

```pascal
unit asmcore_x64;
interface
uses asmcore_base;

const
  reg_rax = 0; reg_rcx = 1; reg_rdx = 2; reg_rbx = 3;
  reg_rsp = 4; reg_rbp = 5; reg_rsi = 6; reg_rdi = 7;
  { r8-r15 = 8..15, sized via RegSize on the operand, not separate constants }

function AsmEncodeX64(const instr: TAsmInstr;
                       var buf: TAsmByteBuf;
                       var patches: TAsmPatchList): Boolean;
function AsmPrintX64(const instr: TAsmInstr): AnsiString;
function AsmCoreLastError: AnsiString;

implementation
{ AsmEncodeX64 dispatches on lowercased Mnemonic to small per-family
  functions (EncodeAluRegReg, EncodeMovRegImm, EncodeStackOp, ...), each
  independently testable — same idea as x64enc.inc's typed encoders, grouped
  by instruction family instead of one large case statement. Returns False
  and sets AsmCoreLastError on an unrecognized mnemonic/operand combination;
  never raises — this is a library, not the compiler's Error() abort path. }
end.
```

Register tables are **redeclared per target unit**, not imported from
`compiler/rv32enc.inc` / `xtensaenc.inc` — `asmcore` must have zero
dependency on `compiler/**` (the dependency runs the other way once Track A
promotes it; importing compiler-internal constants here would invert that).

## Patch sites — the entire boundary contract with Track A

A patch site means "I don't know this N-byte value yet." `asmcore` writes
zero bytes of the right width at the right offset and records
`(Offset, Width, OperandIndex)` in `TAsmPatchList`. No names, no symbol
table, no resolution — purely "your problem now." Track A's layer
([[feature-asm-structured-ir-library]]) owns turning a label name or global
symbol into a value and patching `buf.Bytes[Offset..Offset+Width-1]`. This
is intentionally the entire interface — resist adding anything richer here;
the elegant global-symbol-resolution design is Track A's to make, not ours
to pre-guess.

## Textual round-trip contract

`AsmPrintX64(instr)` renders the same `TAsmInstr` a future parser would need
to reproduce to get byte-identical `AsmEncodeX64` output. Concretely: encode
then print then (conceptually) re-parse-and-re-encode must be lossless. This
is what makes textual emit ([[feature-asm-textual-emit-mode]]) and the
`.asm` frontend ([[feature-asm-source-frontend]]) cheap once Track A wires
them up — the printer and the encoder share one operand model, so neither
can drift from the other.

## Worked examples (prove the abstraction before generalizing)

**x86-64** — `mov eax, 5`:
```pascal
instr.Mnemonic := 'mov';
instr.Operands[0] := RegOp(reg_rax, 4);
instr.Operands[1] := ImmOp(5);
instr.OperandCount := 2;
AsmEncodeX64(instr, buf, patches);
{ -> B8 05 00 00 00 appended to buf; patches unchanged (value fully known) }
```

**aarch64** — `movz x0, #100` (structurally different: fixed 32-bit width, no
ModRM/SIB, no variable instruction length; built 2026-06-30, see
`asmcore_aarch64.pas`):
```pascal
instr.Mnemonic := 'movz';
instr.Operands[0] := RegOp(reg_x0, 8);
instr.Operands[1] := ImmOp(100);
instr.OperandCount := 2;
AsmEncodeAArch64(instr, buf, patches);
{ -> single 4-byte word appended; same TAsmInstr/TAsmOperand shape, no x64-
  specific field was needed to express this. Note `movz`, not a `mov reg,imm`
  alias — real aarch64 has no single "load any 64-bit immediate" opcode (that
  needs up to 4 movz/movk instructions); asmcore picked the literal
  instruction set over inventing a multi-instruction pseudo-op, same
  philosophy as x64's documented divergences (movabs vs the c7 shortcut). }
```

Register naming also mirrors x64's choice: no separate `reg_w0` constants —
`RegOp(reg_x0, 4)` is the 32-bit (`w0`) view of the same register number,
exactly like `RegOp(reg_rax, 4)` is `eax` on x64. One register-number space
per target, width carried on the operand, not duplicated into the constant
table.

If aarch64 (or riscv32) needs *no* changes to `TAsmOperand`/`TAsmInstr` to
express its instructions cleanly, the abstraction is proven — that's the
explicit goal of doing one structurally-different target second, before the
remaining four. **Result: proven, with one real exception** — see "Branch
patch resolution is target-specific" below.

## Branch patch resolution is target-specific (the actual pressure-test finding)

`TAsmPatchSite`'s `(Offset, Width, OperandIndex)` contract needed *zero*
changes for aarch64 — the encode side is exactly as generic as hoped. But
*resolving* a patch is not: x86's rel32 is a separate, byte-aligned trailing
field, so a generic "overwrite these N raw bytes" (`Patch32`, what the `.asm`
frontend and inline-asm both already use for x64) is correct and sufficient.
aarch64 branch immediates are bit-packed *inside* the same 32-bit opcode
word — `imm26` at bits[25:0] for `b`/`bl`, `imm19` at bits[23:5] for
`b.cond` — so a raw overwrite would clobber the opcode. The encode side
writes the **base opcode word** (with the immediate field zeroed) as the
"patch site" placeholder, not a zeroed field; resolution is a
read-modify-write (`word | (relValue & mask) << shift`) that has to know
which mnemonic it's resolving. That knowledge can't live in `asmcore_base`
(it's exactly the kind of target-specific bit-layout knowledge the base unit
is designed to stay ignorant of) — so each target that needs it exports its
own resolver: `AsmPatchBranchAArch64(var buf, offset, mnemonic, relWords):
Boolean` in `asmcore_aarch64.pas`. `relWords` is pre-divided by 4 (aarch64
instructions are always 4-byte aligned) the same way the `.asm` frontend
already computes `target - (patch+4)` for x64 — only the OR-into-existing-
word step differs. **Implication for Track A's layer 2**: when a frontend
eventually targets aarch64, it must call the target's `AsmPatchBranchAArch64`
(or whatever the riscv32/arm32/xtensa equivalents end up being) instead of a
generic byte-overwrite — the patch-resolution step is per-target, even
though the patch-*recording* step (`PatchAdd`) is fully generic. Worth a
`AsmPatchBranchAArch64`-shaped contract per target as that work lands, not a
single generalized resolver — the bit layouts genuinely differ enough
(imm26 vs imm19 vs riscv32's split/scrambled B-type and J-type immediates)
that a shared resolver would just be a dispatch table back to per-target
code anyway.

## Sequencing

1. `asmcore_base.pas` — types above, fully working (buffer growth, operand
   constructors). **Done.**
2. `asmcore_x64.pas` first slice: `mov reg,imm`, `add reg,reg`, `ret` — small
   enough to prove the whole pipeline (types → encode → test) end to end.
   **Done**, since widened well past the first slice (see ticket log).
3. One structurally different target (aarch64 or riscv32) at the same slice
   size, to pressure-test the operand model per the worked example above.
   **Done 2026-06-30 — aarch64** chosen over riscv32 for tooling reasons:
   `aarch64-linux-gnu-as`/`objdump` were available as a byte-exact host
   oracle (matching how x64 was validated); no riscv32 cross-toolchain was
   installed in this environment. mov/add/sub/and/orr/eor/cmp/ldr/str/movz/
   movk/movn/b/bl/b.cond/ret/nop, 26/26 checks byte-exact, both under PXX
   self-host and FPC (`test/test_asmcore_aarch64.pas`, in `make test`).
4. Widen x64 to match `x64enc.inc`/`asmtext.inc`'s existing coverage.
5. Remaining targets (i386, riscv32, arm32, xtensa) — same shape, new
   mnemonic tables; riscv32/arm32/xtensa will each need their own
   `AsmPatchBranch<Target>` per the finding above (i386 can likely reuse
   x64's `Patch32` raw-overwrite, being x86-family). **i386 done 2026-06-30**
   — confirmed mechanical as predicted: byte-identical opcodes to x64 minus
   REX, rel32 branches resolve via the same generic `Patch32` (no
   `AsmPatchBranchI386` needed). One real divergence: `inc`/`dec r32` use
   the 1-byte short form (`40+r`/`48+r`), only valid in 32-bit mode (those
   bytes are REX prefixes in long mode, so x64 has to use the longer
   `FF /digit` form) — matched `as`'s default choice. **arm32 (A32) done
   2026-06-30** — another real finding, distinct from aarch64's: every
   instruction is conditionally predicated (a 4-bit cond field in
   bits[31:28], this slice only emits `AL`/always for non-branches), and
   branch PC-relative arithmetic is off by **one whole word** from every
   other target here — A32's classic 3-stage-pipeline artifact where PC
   reads as `instr_addr+8` while an instruction executes, not the
   `instr_addr+4` ("next instruction") convention x64/aarch64/i386 all
   share. `AsmPatchBranchArm32` takes `relWords` in the same
   `(target-(patch+4))/4` convention every other resolver uses and
   subtracts 1 internally, so the *frontend-facing* contract stays uniform
   even though A32 hardware doesn't behave uniformly — verified against
   `arm-linux-gnueabi-as`/objdump (4 branch directions/conditions, all
   byte-exact). **riscv32 done 2026-06-30** (toolchain installed by user
   request: `binutils-riscv64-linux-gnu`, which assembles RV32I cleanly via
   `-march=rv32i -mabi=ilp32` — no separate riscv32-only package needed).
   Two more findings: (1) RV32I's `jal` (UJ-type) and branch (SB-type)
   immediates are **bit-scrambled** — non-contiguous, non-monotonic field
   placement (`imm[20|10:1|11|19:12]` for jal), a genuine hardware-wiring
   optimization in the ISA spec, not just a packed-and-shifted field like
   aarch64's. `AsmPatchBranchRiscv32` scatters the bits per-field rather
   than a single shift+OR. (2) RV32I branch/jal immediates are relative to
   the instruction's **own** address (no pipeline/next-instruction
   adjustment at all — the simplest PC-relative convention met so far);
   kept the uniform `relWords` *input* contract by having the resolver do
   `byteOffset = relWords*4 + 4` internally. (3) RISC-V branches compare two
   registers *in the branch instruction itself* (no separate flags-setting
   `cmp`), so a riscv32 branch's `TAsmInstr` is 3 operands (rs1, rs2, the
   patch site) where every other target here uses 1 (`<patch>` alone) —
   `TAsmOperand`/`TAsmInstr` needed no changes to express this either.
   **xtensa done 2026-06-30** (toolchain: `binutils-xtensa-lx106`) — the
   biggest structural departure yet and the last of the six targets:
   - The base (non-"narrow"/code-density) ISA is **24-bit (3 bytes), not
     32-bit**. This slice covers only the 3-byte forms (forced via
     `xtensa-lx106-elf-as --no-transform`, since the default behavior
     silently substitutes the 2-byte density forms where available —
     real xtensa assembly distinguishes `add` from `add.n` by mnemonic,
     an assembler doesn't choose between them on your behalf by spec, GNU
     as just defaults to relaxing). `TAsmByteBuf`/`TAsmPatchSite` needed
     no changes to support a 3-byte instruction width — `Width` was
     always caller bookkeeping, not enforced by `asmcore_base`.
   - **A genuine trap, not a finding about the ISA**: `objdump`'s
     disassembly text shows each instruction as a conventional hex number
     (most-significant-byte-leftmost in the printed string) — this is
     **not** the literal little-endian memory byte order. Hand-deriving
     bit layouts from `objdump -d` output alone (the method that worked
     fine for x64/aarch64/arm32/riscv32, all of which display the *raw*
     bytes left-to-right) silently produces a backwards encoder for
     xtensa. Caught it by cross-checking against `objcopy -O binary` +
     `xxd` (the actual memory bytes) — once seen, abandoned the from-
     scratch derivation and used this compiler's own existing,
     ESP-hardware-validated `compiler/xtensaenc.inc` as the formula
     source instead (still byte-verified against the corrected raw-byte
     oracle, not blindly trusted).
   - **`AsmPatchBranchXtensa` breaks the `relWords`-divided-by-4 pattern
     on purpose**: xtensa instructions are 3 bytes, so "words of 4" isn't
     a meaningful unit here — a sequence of 3-byte instructions lands on
     multiples of 3, not 4, and forcing the convention would silently go
     fractional. Takes a raw **byte** delta instead
     (`relBytes = target-(patch_offset+4)`), which happens to be *exactly*
     what the `.asm` frontend's existing generic `Patch32` already computes
     for x64 — the most natural-fitting resolver contract of the six, not
     a special case. (aarch64/arm32/riscv32's word-based resolvers are
     still correct for *those* targets, not changed — their instructions
     really are uniformly 4-byte and every valid branch target really
     does land on a multiple of 4, so no bug, just a convention that
     doesn't generalize to every target and shouldn't have been assumed
     to.)
   - Field formulas verified byte-exact (15 checks, encode + patch) against
     raw bytes from `xtensa-lx106-elf-as --no-transform` + `objcopy`.
   **All six `lib/asmcore` targets done.**
6. Textual printer per target, in step with each target's encoder (not
   bolted on at the end). **Done for x64 and aarch64** (`AsmPrintX64`/
   `AsmPrintAArch64`).
