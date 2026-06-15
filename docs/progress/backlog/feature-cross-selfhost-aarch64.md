# Cross self-host: AArch64 generated compiler runs under QEMU

- **Type:** feature
- **Status:** working
- **Owner:** codex
- **Blocked-by:** feature-cross-managed-string-cow
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split from cross self-host rollup)

## Goal

Make the AArch64 compiler binary emitted by native `pascal26` work as a compiler
under QEMU. Keep this platform-specific until the failure is understood.

## Current failure

Repro from repo root:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 \
  compiler/compiler.pas /tmp/compiler_aarch64
tools/run_target.sh aarch64 /tmp/compiler_aarch64 -dPXX_MANAGED_STRING \
  --target=x86_64 test/hello.pas /tmp/hello_aarch64_to_x64
```

Observed 2026-06-14: the native-built AArch64 compiler is produced, and the
AArch64-hosted self compile no longer segfaults in `FindProcOverload`. It now
fails deterministically while compiling the built-in heap unit:

```text
ok: /tmp/ca64  [code=2542476B  data=43368B  bss=133171336B  procs=801]
pascal26:82: error: invalid IR node reference in arg value ()
```

The previous crash was PC `0x48bda8`, fault address `0x48`, instruction
`ldrb w0, [x0]`, mapped to `FindProcOverload`. That was caused by AArch64
`IR_LEA` loading a non-byref open-array/fixed-string/set parameter slot with
the element width (`array of Boolean` loaded one byte, yielding pointer
`0x48`). The current wall is past that crash and is an IR validation failure
from an `IR_ARG` with an empty value while compiling `compiler/builtin/
builtinheap.pas` around the `HeapMmap` raw-syscall block.

## Acceptance

- The AArch64-generated compiler compiles `test/hello.pas` to x86-64 under
  QEMU.
- The emitted x86-64 `hello` is byte-identical to native `pascal26` output for
  the same command.
- The emitted x86-64 `hello` runs and prints `Hello, World!`.
- Then extend to `compiler/compiler.pas -> aarch64` self-fixedpoint and compare
  byte-identical outputs.

## Log

- 2026-06-13 — opened with current failure (`Pascal define storage overflow`).
- 2026-06-13 — diagnosis (no code change): the LowerCase crash is NOT the COW
  gap. AArch64 `IR_LEA` (`ir_codegen_aarch64.inc` ~799) only loads the heap
  handle for dyn arrays (`IsArray and ArrLen=-1`); for a scalar AnsiString it
  returns the slot ADDRESS, so `Length(s)`=0 and `s[i]` indexes the slot →
  garbage, and LowerCase's `res[i]:=...` writes to a bad address → segfault.
  This is exactly the already-fixed i386 bug #1 (IR_LEA scalar-AnsiString
  handle load). Fix first by mirroring the i386 IR_LEA change (load the handle
  for scalar AnsiString; add skParam IsArray/tyString/tySet content-load and
  by-ref-AnsiString deref-in-Length/index), THEN tackle COW
  (feature-cross-managed-string-cow). Repro: `var s:ansistring; s:='Hello';
  writeln(Length(s))` prints 0 on aarch64, 5 on x86-64. AArch64 is behind
  i386/ARM32 here — string indexing/Length isn't in its target suite yet.
- 2026-06-13 — Codex fixed the AArch64 scalar-AnsiString `IR_LEA` gap and added
  the existing `test_cross_str_length_index` oracle to `make test-aarch64`.
  `make test-aarch64` is green. The generated AArch64 compiler now gets past the
  original `Length(s)=0` class of bug, but the self-host repro still segfaults:
  GDB maps the fault to `PXXStrDecRef`, called from `ParseProgram`, with
  `p = -9`. The caller is releasing a stale local managed-string slot from
  `dummyNames: array[0..7] of AnsiString`; this is the remaining managed
  aggregate/static-array local initialization/release wall, not the old `IR_LEA`
  scalar-string wall.
- 2026-06-14 — advanced the wall. Implemented AArch64 string index-write COW
  (`PXXStrUnique` from write-mode `IR_INDEX`), explicit zeroing for hidden
  managed argument-temp locals allocated during IR lowering, AArch64 `IR_LEA`
  param-pointer loading for open-array/fixed-string/set params, and signed
  32-bit `EmitLoadVarA64` loads (`ldrsw`). `make test-aarch64` and `make test`
  pass. The full repro:
  `./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 compiler/compiler.pas /tmp/ca64`
  succeeds, but running `/tmp/ca64` under QEMU to produce `/tmp/ca64_self` still
  segfaults after reading `compiler/builtin/builtinheap.pas`. Latest GDB
  snapshot: PC `0x48bda8`, fault address `0x48`, instruction `ldrb w0, [x0]`;
  surrounding code forms a character access from a nil/wrong base plus a signed
  local offset. Next slice: map that proc and inspect the string/index base
  feeding the byte load.
- 2026-06-14 — fixed the `FindProcOverload` crash. AArch64 `IR_LEA` for
  non-byref parameter pointer slots (`array of T`, fixed string, set) now loads
  the full pointer-sized caller slot instead of delegating to `EmitLoadVarA64`,
  whose width follows the element type. Added
  `test/test_cross_open_array_params.pas` to lock the `array of Boolean`
  trigger used by `FindProcOverload(ptypes, parr, pbyref)`. `make test-aarch64`
  passes. Clean self-host probe now advances to:
  `pascal26:82: error: invalid IR node reference in arg value ()` while the
  AArch64-hosted compiler is compiling `builtinheap.pas` (`HeapMmap` /
  `__pxxrawsyscall`). A quick reduced probe showed any program still reaches
  this via built-in heap compilation; temporary syscall-specific parser/IR
  diagnostics did not prove a fix and were backed out. Next slice: identify the
  general call/argument lowering node that produces `IR_ARG(IRA=-1)` under the
  AArch64-hosted compiler.
- 2026-06-15 — blocker `feature-cross-managed-string-cow` is DONE (commit
  2fbaca4); AArch64 string COW was already in place, so the remaining wall here
  is independent of COW: the `IR_ARG(IRA=-1)` / `invalid IR node reference in arg
  value` crash while the AArch64-hosted compiler compiles `builtinheap.pas`.
  This ticket is now Ready.
