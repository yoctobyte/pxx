# Inline Assembler

Status: **rudimentary, working**. Enough to pass tests and read/write Pascal
variables from hand-written machine code. Not a full assembler.

Encoder lives in `compiler/asmenc.inc` (included after `symtab.inc`, before
`parser.inc`). It encodes a subset of x86-64 in **Intel syntax** directly into
the `AsmBytes` buffer at parse time; the buffered bytes are blitted into the
code stream at codegen time as an `AN_ASM` / `IR_ASM` node.

## Forms

Statement-level block inside any routine body:

```pascal
asm
  mov eax, n
  xchg eax, m
  mov n, eax
end ['eax'];          { optional clobber list — parsed and ignored }
```

Whole-function `assembler` body (params copied to stack by the normal
prologue, read by name; result left in `rax`/`eax`):

```pascal
function AddMul(a, b: longint): longint; assembler;
{$asmMode intel}
asm
  mov eax, a
  add eax, b
  add eax, eax
end;
```

Tests: `test/test_asm.pas` (raw bytes / `exit` syscall),
`test/test_asm_func.pas` (assembler function), `test/test_asm_swap.pas`
(statement-level local swap). All wired into `make test`.

## How variable passing works

A bare identifier operand resolves via `FindSym` to the symbol's frame slot
and is encoded as `[rbp+disp32]` (mod=10, rm=101). Locals and params live
there; the operation size is taken from the register operand in the same
instruction (or the var's type when no register is present). This matches the
FPC `{$asmMode intel}` convention where `mov eax, n` means "load the variable
`n`", not its address.

Because this is a stack-machine codegen that keeps nothing live in registers
across statements, an `asm` block's writes to `[rbp+off]` are always visible
to the next Pascal statement (it reloads from memory), and the clobber list is
therefore moot — parsed and discarded.

`assembler` functions skip the Result reload in the epilogue (`EmitProcEpilog(-1)`)
so the asm body's `rax` survives as the return value.

## Supported

- Operands: registers (8/16/32/64-bit, including r8..r15), immediates
  (incl. negative), bare local/param names (memory).
- ALU: `mov add sub and or xor cmp test xchg lea imul`.
- Shifts: `sar shl sal shr rol ror` by `imm8` or `cl`.
- Unary: `inc dec neg not mul div idiv`.
- Stack: `push pop` (reg / imm / mem).
- `setcc` and `cmovcc` families (full condition-code set).
- Zero-operand: `nop ret leave syscall cdq cqo cdqe cwde`; `int imm8`.
- Raw data: `db dw dd dq` (comma lists).
- `{$asmMode intel}` accepted (ignored — Intel is the only mode).

## Limitations / not yet implemented

- **Global variables** as operands: error (`global var operands not yet
  supported`). They need a relocation entry, but the encoder writes into a
  flat byte buffer at parse time with no access to the codegen-time
  `EmitGlobRef` fixup machinery. Needs a structured (instruction-list) asm
  representation encoded at codegen time, or a parallel reloc list keyed by
  buffer offset.
- **Explicit memory operands** `[reg]`, `[reg+disp]`, `[reg+reg*scale]`: not
  parsed. Only bare-name memory (always `[rbp+disp32]`) is supported. No SIB.
- **Labels / branches inside asm** (`jmp`, `jcc`, `call`, `loop`): not
  supported. No intra-block label table, no fixups. This is the main thing
  blocking real algorithms.
- **AT&T syntax** (`{$asmMode att}`) and `direct`: not implemented (directive
  is silently accepted but ignored, so att source would mis-encode).
- **Operand-size disambiguation** (`byte ptr` / `word ptr` / `dword ptr`):
  not parsed. Size is inferred from the register operand; a mem+imm with no
  register defaults from the var type, else dword.
- **`test x, x`** where both operands are the same memory var: illegal in
  x86 (needs one register); the FPC docs example does not encode as-is.
- **xmm / floating-point / SSE / AVX**: none.
- **64-bit immediates**: only `mov reg64, imm64` uses the `B8+r` 8-byte form;
  other instructions take `imm32` (sign-extended).
- **Clobber list** is parsed and discarded, not validated (see above — moot
  for this codegen).

## TODO (rough priority)

1. **Labels + branches** inside an asm block (local label table + fixups).
   Highest value — unlocks loops and conditionals in asm.
2. **Global-var operands** via a codegen-time encode path (or buffer-offset
   reloc list) so `EmitGlobRef` can patch absolute addresses.
3. **Explicit `[reg+disp]` memory** + SIB, for pointer-style access.
4. **Operand-size keywords** (`byte/word/dword/qword ptr`).
5. Broaden register coverage edge cases (ah/ch/dh/bh high-byte regs are
   intentionally unsupported; document or reject clearly).
6. Eventually: AT&T mode, or commit to Intel-only and reject att explicitly.

## Self-hosting constraints (when editing `asmenc.inc`)

The bootstrap compiler must compile this file, so:

- **No `shl` operator** — the self-hosted compiler implements `shr` only. Use
  multiplication (`x * 8`) for left shifts.
- **No string `+`** on the hot path — string concatenation is unreliable when
  the compiler compiles itself. Build strings with `AppendChar`. (`+` in
  `Error(...)` messages is tolerated because those paths abort anyway.)
- Initialise a string with `s := ''` then `AppendChar`, not a single-char
  literal (single-char literals are `tyChar`).
