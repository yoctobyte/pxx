# bug: `not` on an integer is boolean-only on ESP (riscv32 / xtensa)

- **Type:** bug (codegen — `IR_NOT` on ESP backends)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-25 (split from bug-not-on-int64-is-boolean, host part fixed)

## Symptom

`not <integer>` (bitwise complement) miscompiles on the ESP backends because
their `IR_NOT` emits a **boolean** flip regardless of operand type:

- **riscv32** (`ir_codegen_riscv32.inc`, `IR_NOT`): always `xori a0, a0, 1`
  (low-bit flip) for every type — so even `not x` for an `Int64`/`Integer`
  variable is wrong, not just the expression cases.
- **xtensa** (`ir_codegen_xtensa.inc`, `IR_NOT`): the 64-bit path is correct
  (`xor a2/a3` with -1), but the **non-64 path** is `movi a8,1; xor a2,a2,a8`
  — a boolean flip, wrong for a 32-bit ordinal `not`.

The host fix (bug-not-on-int64-is-boolean) now types `not <int-expr>` as integer,
so these ESP paths are reached by more programs; previously the boolean tag
masked riscv32's defect for expressions (but not for `not x`).

## Fix

Mirror the i386/aarch64 `IR_NOT` shape:
- riscv32: `if Is64BitRISCV32(tk)` → `EmitNode64RISCV32`; `xori a0,a0,-1; xori
  a1,a1,-1`. `else if ordinal and <> tyBoolean` → `xori a0,a0,-1`. `else` → keep
  `xori a0,a0,1`. (RISC-V has no `not`; `xori reg,-1` is the bitwise complement.)
- xtensa: change the non-64 ordinal-non-boolean path from `movi a8,1` to
  `movi a8,-1` (full-width complement); keep the boolean path at `1`.

## Verify

Bare-metal harness — `tools/esp_run_bare.sh --chip esp32c3` (riscv32) and
`--chip esp32s3` (xtensa), UART vs x86-64 oracle (`make test-esp-bare`). Add an
ESP variant of `test/test_not_int64_expr.pas` (Int64 + 32-bit ordinal `not`).

## Acceptance

- `not x` (Int64 and Integer/LongWord) == bitwise complement on esp32c3 and
  esp32s3, matching the x86-64 oracle.
