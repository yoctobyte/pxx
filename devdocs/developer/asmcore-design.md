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

**aarch64** — `mov w0, #5` (structurally different: fixed 32-bit width, no
ModRM/SIB, no variable instruction length):
```pascal
instr.Mnemonic := 'mov';
instr.Operands[0] := RegOp(reg_w0, 4);
instr.Operands[1] := ImmOp(5);
instr.OperandCount := 2;
AsmEncodeAArch64(instr, buf, patches);
{ -> single 4-byte word appended; same TAsmInstr/TAsmOperand shape, no x64-
  specific field was needed to express this. }
```

If aarch64 (or riscv32) needs *no* changes to `TAsmOperand`/`TAsmInstr` to
express its instructions cleanly, the abstraction is proven — that's the
explicit goal of doing one structurally-different target second, before the
remaining four.

## Sequencing

1. `asmcore_base.pas` — types above, fully working (buffer growth, operand
   constructors).
2. `asmcore_x64.pas` first slice: `mov reg,imm`, `add reg,reg`, `ret` — small
   enough to prove the whole pipeline (types → encode → test) end to end.
3. One structurally different target (aarch64 or riscv32) at the same slice
   size, to pressure-test the operand model per the worked example above.
4. Widen x64 to match `x64enc.inc`/`asmtext.inc`'s existing coverage.
5. Remaining targets (i386, the other of aarch64/riscv32, arm32, xtensa) —
   same shape, new mnemonic tables, no new abstraction work expected.
6. Textual printer per target, in step with each target's encoder (not
   bolted on at the end).
