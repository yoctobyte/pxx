# riscv32 / xtensa (`--esp-profile=bare`) reject even a trivial program — unsupported `call_ind` node

- **Type:** bug (possible regression)
- **Track:** A — `compiler/ir_codegen_riscv32.inc`, `compiler/ir_codegen_xtensa.inc`
- **Status:** backlog
- **Opened:** 2026-07-02
- **Found while:** Track B validating `feature-demo-chess` cross-target
  buildability; widened into a standalone probe once the scope became clear.

## Problem

`stable_linux_amd64/default/pinned` (v153, the current pin — no live-source
confound) **cannot compile `test/test_esp_bare.pas`**, the project's own
ESP32 bare-metal boot test, for either bare-metal profile:

```
$ ./pinned --target=riscv32 --esp-profile=bare test/test_esp_bare.pas /tmp/out.elf
pascal26:1209: error: target riscv32: unsupported node in IR codegen ()

$ ./pinned --target=xtensa --esp-profile=bare test/test_esp_bare.pas /tmp/out.elf
pascal26:1209: error: target xtensa: unsupported node in IR codegen: call_ind ()
```

This reproduces deterministically (3/3 runs each, pinned binary is immutable
so there's no concurrent-rebuild confound). It also reproduces on a **maximally
trivial** program with nothing ESP-specific at all:

```pascal
program P;
begin
end.
```
— same error, both targets, with or without `--esp-profile=bare`, with or
without `-dPXX_ESP_BARE` (that define does nothing; the real flag is
`--esp-profile=bare`, confirmed from `tools/esp_run_bare.sh`). Bisected further
on riscv32: fails identically with just a bare `Int64`/`Integer` var decl, an
assignment, or `writeln` — i.e. the failure isn't specific to Int64 math,
`WriteLn`, or any RTL feature; it fires on **any** program, even one with an
empty body.

The riscv32 error message is missing the node name (`unsupported node in IR
codegen ()` — empty parens) while the xtensa one names it: `call_ind`
(indirect call). Given the riscv32 catch-all `Error(...)` call
(`ir_codegen_riscv32.inc:1344`) doesn't append `IROpName(IRKind[node])` the way
the xtensa one does (`ir_codegen_xtensa.inc:1737`), riscv32 is very likely
hitting the **same** `call_ind` node — just with a less informative message
(worth fixing alongside, see below).

## Why this looks like a regression, not a known gap

- `done/feature-esp-int64-arith.md` claims 64-bit arithmetic **validated** on
  both esp32c3 (riscv32) and esp32s3 (xtensa) via
  `test_esp_softfloat_probe.pas`, including "Int64 params/returns" and the
  full softfloat library, "byte-identical" vs the x86-64 oracle.
- `test/test_esp_bare.pas` itself is the subject of the `make test-esp-bare`
  Makefile gate (line 2699), which is presumably expected to pass — running it
  directly right now (`make test-esp-bare`, Espressif qemu is installed on
  this box) reproduces a **MISMATCH**: expected 3 lines of UART output
  (`hello esp32 bare` / `12345` / `-42`), got none.
- So either something regressed between whenever those tickets validated and
  now, or those validations used a program shape / compiler invocation this
  probe hasn't matched (e.g. a different flag combination, or a since-changed
  entry-point/finalization lowering that now emits an indirect call the ESP
  backends don't handle). Distinguishing "regression" from "this exact
  invocation was never actually exercised" needs Track A's own history/git
  bisection — flagging both possibilities since I can't tell from the outside.

## Impact

- Blocks `feature-demo-chess`'s ESP32 fit entirely (Slice: "Build under the
  existing ESP harness") — can't get past a trivial program, let alone the
  full engine.
- Blocks `make test-esp-bare` (currently failing on this checkout, esp32c3
  leg — did not check esp32s3/xtensa leg's actual boot behavior, only the
  compile-time error, since the same `call_ind` wall applies).
- Likely blocks anything else routed through the bare ESP profile.

## Suggested investigation starting points (not prescriptive — Track A's call)

- Find what `call_ind` node is being emitted for a program with **no**
  explicit indirect calls at all — almost certainly something synthesized by
  the compiler itself (unit init dispatch, finalization/exception-table setup,
  a Halt/exit trampoline, or similar), since the source has no function
  pointers.
- Fix the riscv32 `Error(...)` at `ir_codegen_riscv32.inc:1344` to append
  `IROpName(IRKind[node])` like the xtensa one does — cheap diagnostics fix,
  independent of the root cause.

## Acceptance

- `test/test_esp_bare.pas` compiles and boots correctly under
  `make test-esp-bare` for both esp32c3 and esp32s3 (UART output matches the
  x86-64 oracle, as the test already asserts).
- A truly empty `program P; begin end.` compiles under
  `--target=riscv32 --esp-profile=bare` and `--target=xtensa --esp-profile=bare`.
- riscv32's catch-all IR-codegen error names the unsupported node (matches
  xtensa's diagnostic quality).

## Log
- 2026-07-02 — Filed by Track B. Found while checking `feature-demo-chess`'s
  ESP32 cross-target viability; reproduced with the immutable pinned stable
  binary (v153) to rule out any concurrent-rebuild confound (this repo runs
  multiple parallel Track A/B/C/D agents). No code touched — test/repro only.
- 2026-07-02 — Track A: ROOT CAUSE = regression from v135 div-zero runtime:
  `PXXDivZero` (builtinheap.pas, always pulled) calls through the
  `PXXDivZeroHook` proc var — an IR_CALL_IND, which neither ESP backend
  implemented. Fixed by implementing IR_CALL_IND on riscv32 (jalr t0) and
  xtensa (callx8/callx0 a8, both ABIs), plus IR_PROCADDR on xtensa (L32R
  inline literal; elfwriter guard lifted) so `@proc` works there too.
  riscv32 catch-all error now names the node (matches xtensa). New qemu gate
  test/test_esp_procvar.pas (7/12/2 oracle-identical on esp32c3+esp32s3).
  make test-esp-bare fully green again; make test + self-host byte-identical.
