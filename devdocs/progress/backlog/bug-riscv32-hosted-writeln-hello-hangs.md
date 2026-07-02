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
