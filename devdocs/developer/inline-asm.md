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
(statement-level local swap), `test/test_asm_branch.pas` (labels + `jcc`
loop), `test/test_asm_keywords.pas` (keyword-colliding mnemonics regression).
All wired into `make test`.

Labels:

```pascal
asm
  mov rdi, 0
  mov rcx, 9
sumloop:
  add rdi, rcx
  dec rcx
  cmp rcx, 0
  jg sumloop          { forward and backward both resolve }
end;
```

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
- **Labels + `jmp`/`call`/`jcc <label>`** (rel32, forward + backward) —
  encoded via `lib/asmcore`'s `AsmEncodeX64` (`PatchOp(4)`), resolved the
  same way the standalone `.asm` frontend resolves its own labels: a local
  fixup table, `target - (patch_offset + 4)` once every label in the block is
  known. See [[feature-asm-structured-ir-library]] TODO #1.
- `{$asmMode intel}` accepted (ignored — Intel is the only mode).
- **Global variables** as operands — `mov reg,global` / `mov global,reg` /
  ALU `global,reg`/`reg,global` / `cmp` / `lea reg,global`, resolved via a
  deferred `EmitGlobRef` fixup (`AsmGlobFix[]`, `defs.inc`): the encoder
  can't call `EmitGlobRef` at parse time (`AsmBytes` offsets aren't final
  code positions), so it records `(AsmBytes-offset, BSS-offset)` and writes
  a 4-byte zero placeholder; the `IR_ASM` codegen-replay loop in
  `ir_codegen.inc` calls the real `EmitGlobRef` once `CodeLen` is correct,
  in place of literally copying those 4 placeholder bytes. Absolute
  `[disp32]` addressing (`EncModRMAbs`, shared with regular codegen — the
  compiler builds non-PIE), not RIP-relative. **Not yet covered**: `mov
  global,imm` (the fast-path `x64_mov_mem_imm`/`x64_push_mem`/
  `x64_pop_mem` helpers hardcode an `[rbp+disp]` base) — load into a
  register first. Two memory/global operands in one instruction (`add
  globalA, globalB` or `add localA, localB`) was never possible — ModRM
  only has one r/m slot, pre-existing x86 limitation, not new.
- **Explicit memory operands** `[reg]`, `[reg+disp]`, `[reg+reg*scale]`,
  `[reg+reg*scale+disp]` (base register mandatory and always first; scale
  must be 1/2/4/8). SIB encoding reused directly from `lib/asmcore`'s
  `EmitModRMMem` (exported from `asmcore_x64` for exactly this — no second
  SIB implementation in the compiler) via a new `AOP_MEMR` operand kind,
  bridged through a throwaway `TAsmByteBuf`. `mov`/ALU/`lea`/unary/shifts/
  `test`/`xchg`/`setcc`/`cmovcc` all work generically once `AsmModRM`
  supported the new kind — only `mov [..], imm`/`push [..]`/`pop [..]`
  needed their own native encode (the fast-path typed helpers
  `x64_mov_mem_imm`/`x64_push_mem`/`x64_pop_mem` hardcode an `[rbp+disp]`
  base, wrong for an arbitrary register). `rsp` can't be a SIB index (that
  bit pattern is the dedicated "no index" encoding) — rejected with a clear
  error.
- **Operand-size keywords**: `byte`/`word`/`dword`/`qword [ptr]` before a
  bracketed memory operand (`inc byte [rbx]`, `mov dword ptr [rbx], 1000`)
  — disambiguates a bare-memory instruction's width when no register
  operand is present to infer it from (only applies to `[reg...]` forms;
  a named local/param/global already has its size from the Pascal var's
  own declared type, no keyword needed or accepted there). LANDMINE:
  `byte` lexes as `tkInteger_T` (shared with the `integer` type keyword),
  **not** `tkIdent` — the same keyword-collision class as `and`/`or`/`div`/
  `dec` (see `AsmTokIsWordLike` in `compiler/asmenc.inc`); `word`/`dword`/
  `qword`/`ptr` are plain `tkIdent`. `CurTok.SVal` holds the right text
  regardless of `Kind` either way.
- **AT&T syntax**: committed to Intel-only (2026-07-01) rather than
  implemented — `{$asmMode att}` now errors cleanly
  (`compiler/lexer.inc`'s `asmmode` directive handler) instead of being
  silently accepted and mis-encoding (AT&T's operand order is reversed
  from Intel's, so a compiled-clean `{$asmMode att}` program would have
  produced wrong instructions with no warning). `{$asmMode intel}` still
  a no-op (the only supported mode). `direct`: still not implemented,
  no known real use case surfaced yet.
- **`test x, x`** where both operands are the same memory var: illegal in
  x86 (needs one register); the FPC docs example does not encode as-is.
- **xmm / floating-point / SSE / AVX**: none.
- **64-bit immediates**: only `mov reg64, imm64` uses the `B8+r` 8-byte form;
  other instructions take `imm32` (sign-extended).
- **Clobber list** is parsed and discarded, not validated (see above — moot
  for this codegen).

## TODO (rough priority)

1. ~~**Labels + branches** inside an asm block (local label table + fixups).~~
   **Done 2026-06-30** — see Supported, above, and
   [[feature-asm-structured-ir-library]].
2. ~~**Global-var operands** via a codegen-time encode path (or buffer-offset
   reloc list) so `EmitGlobRef` can patch absolute addresses.~~ **Done
   2026-07-01** — see Supported, above.
3. ~~**Explicit `[reg+disp]` memory** + SIB, for pointer-style access.~~
   **Done 2026-07-01** — see Supported, above.
4. ~~**Operand-size keywords** (`byte/word/dword/qword ptr`).~~ **Done
   2026-07-01** — see Supported, above.
5. Broaden register coverage edge cases (ah/ch/dh/bh high-byte regs are
   intentionally unsupported; document or reject clearly).
6. ~~Eventually: AT&T mode, or commit to Intel-only and reject att
   explicitly.~~ **Done 2026-07-01** — committed to Intel-only, see
   Limitations, above.

## Self-hosting constraints (when editing `asmenc.inc`)

The bootstrap compiler must compile this file, so:

- **No string `+`** on the hot path — string concatenation is unreliable when
  the compiler compiles itself. Build strings with `AppendChar`. (`+` in
  `Error(...)` messages is tolerated because those paths abort anyway.)
- Initialise a string with `s := ''` then `AppendChar`, not a single-char
  literal (single-char literals are `tyChar`).
