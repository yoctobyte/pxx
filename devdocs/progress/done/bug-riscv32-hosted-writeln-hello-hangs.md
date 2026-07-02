# riscv32 hosted: plain `writeln` hello hangs under qemu-user (pre-existing)

- **Type:** bug
- **Track:** A — `compiler/ir_codegen_riscv32.inc` / riscv32 hosted runtime
- **Status:** backlog
- **Opened:** 2026-07-02

## Repro

```pascal
program H; begin writeln('hi'); end.
```

```
$ pxx --target=riscv32 h.pas h_rv && tools/run_target.sh riscv32 h_rv
(no output, hangs until killed)
```

Reproduces with the pinned v154 binary — pre-existing, NOT a regression from
the 2026-07-02 stackless work. Unnoticed because `make test-riscv32` only
covers exit-code-based C-entry tests (no writeln). ESP bare riscv32 is fine
(UART path, test-esp-bare green) — this is specifically the HOSTED
(linux/qemu-user) riscv32 leg's console write.

## Impact

- Blocks running test_stackless_gen.pas (or any writeln program) on hosted
  riscv32 — the stackless-generator suite now COMPILES for riscv32 (SlNew
  rework) but can't be output-validated there until this is fixed.

## Acceptance

- hello prints `hi` under `tools/run_target.sh riscv32`.
- `make test-riscv32` gains a writeln-based smoke line.
- test_stackless_gen.pas output-identical to x86-64 on riscv32.

## Log
- 2026-07-02 — Filed by Track A; found while cross-validating stackless record
  generators (i386/aarch64/arm32 legs all output-identical, riscv32 hangs on
  ANY writeln, even pinned).
- 2026-07-02 — Track A: FIXED, and the hosted riscv32 leg brought up well past
  hello:
  - EmitExit: real exit_group(94) ecall when not EspBareBoot (was the bare
    self-loop park for ALL riscv32 — the actual hang).
  - IR_WRITE/IR_WRITELN (hosted): lowered to new portable buffer-based
    builtin writers (PXXWriteDecW/StrMW/CharW/BoolW/CStr/Pad/NL — single
    PXXSysWrite each, no write() recursion); const-str = inline write ecall;
    floats via the existing PXXWriteFloat* helpers.
  - IR_SYSCALL implemented (args -> a7/a0..a5, ecall, sign-extend result).
  - IR_READLINE/IR_READ_VAR/IR_READ_DISCARD + bare-Eof(210) wired (same
    helpers as the other cross targets).
  - in-operator (set membership, branch-free), IR_SET_LIT/COPY/BINOP/CMP
    (8-word ports of the aarch64 shapes).
  - Int64 negate fixed (was documented low-word-only LANDMINE — surfaced as
    garbage decimals via PXXWriteDecW's u := -v); __pxx_l2d/__pxx_ul2d
    softfloat kernels added for Int64->double.
  - >8 param words: callee reads word k>=8 from the caller-kept stack block
    ([s0+16+(pnWords-1-k)*4]); caller keeps/frees the block (unblocks
    CoAlloc-shaped signatures).
  - SetLength on var-array param; softfloat auto-pulled (before builtinheap)
    for riscv32/xtensa; builtin/textfile/pxxcio RTL gates now exclude only
    BARE riscv32 (hosted riscv32 = posix platform + PAL dir + riscv32
    syscall table in platform_backend, PAL_GENERIC_SYSCALLS define shared
    with aarch64); esp32 method-address fixups enabled (generic PatchDataU64
    path); coroutine.pas body {$ifdef CPUX86_64} (stackful is x86-64-only)
    so `uses coroutine` programs cross-compile.
  - make test-riscv32 extended: hello + stackless-generator (full record
    suite output-identical) + readln + eof-stdin.
  Remaining for chess on hosted riscv32: exceptions — filed
  feature-riscv32-hosted-exceptions.
