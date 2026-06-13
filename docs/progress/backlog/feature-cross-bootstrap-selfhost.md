# Cross self-host bootstrap (compiler.pas → byte-identical under QEMU)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-cross-selfhost-i386, feature-cross-selfhost-aarch64, feature-cross-selfhost-arm32
- **Unblocks:** —
- **Opened:** 2026-06-11 (user request)

## Goal

The "fun test": cross-compile `compiler.pas` to a non-native target, run the
resulting binary under QEMU to compile `compiler.pas` again for the same target,
and verify the two outputs are **byte-identical** — the triple-stage bootstrap
correctness proof, applied across architectures. The earlier
`feature-cross-bootstrap` (now in `done/`) delivered the runtime *infrastructure*
analysis; this ticket is the end-to-end gate.

## Current state

Small test programs cross-compile and are byte/output-matched to x86-64 on the
Linux cross targets (managed runtime — heap, strings, records, dynarrays —
covered by target suites). `compiler.pas` now stage-1 emits successfully for
x86-64, i386, AArch64, and ARM32 with `-dPXX_MANAGED_STRING`, but the generated
cross compiler binaries do not yet reliably run as compilers under QEMU.

Baseline from 2026-06-11:

```
i386    : only ordinal/pointer parameters supported yet   (feature-cross-param-abi)
arm32   : builtin/exception runtime not yet supported     (feature-cross-exceptions)
aarch64 : load through pointer of this type not yet supported
```

Current stage-1 probe on 2026-06-13:

```
x86_64  : ok         emits /tmp/compiler_x86_64
i386    : ok         emits /tmp/compiler_i386
aarch64 : ok         emits /tmp/compiler_aarch64
arm32   : ok         emits /tmp/compiler_arm32
```

Current full-chain probe on 2026-06-13:

```
arm32 compiler under QEMU -> --target=x86_64 hello.pas : segfault (rc 139)
i386 compiler              -> --target=x86_64 hello.pas : segfault (rc 139)
aarch64 compiler under QEMU -> --target=x86_64 hello.pas: Pascal define storage overflow
```

This rollup is intentionally split by platform:

- [`feature-cross-selfhost-i386`](feature-cross-selfhost-i386.md)
- [`feature-cross-selfhost-aarch64`](feature-cross-selfhost-aarch64.md)
- [`feature-cross-selfhost-arm32`](feature-cross-selfhost-arm32.md)

## Plan (staged)

1. Land an xfail/non-voting chain probe helper if useful.
2. Tackle one platform at a time, starting from the smallest failing program
   emitted by that platform's cross-compiled compiler.
3. When every platform child ticket passes, wire voting `make
   cross-bootstrap-<arch>` targets and close this rollup.

## Acceptance / test plan

A `make cross-bootstrap-<arch>` target per cross arch:

1. `make test` still passes (x86-64 baseline unbroken).
2. `./compiler/pascal26 --target=<arch> compiler/compiler.pas /tmp/pc_<arch>` succeeds.
3. `qemu-<arch> /tmp/pc_<arch> --target=<arch> compiler/compiler.pas /tmp/pc_<arch>_2` succeeds.
4. `cmp /tmp/pc_<arch> /tmp/pc_<arch>_2` exits 0 (byte-identical).
5. Bonus: cross-compiled compiler reproduces the x86-64-built compiler's output
   for the test programs.

## Notes

- Until feasible, the target may be added as an xfail gate that prints the
  current blocker, so the goal is runnable and tracked rather than aspirational.
- ESP32 / bare-metal (feature-target-esp32) is a *different* axis (no
  Linux/QEMU ELF); this gate is Linux user-space cross only.
- **ESP32 self-host is explicitly NOT a goal.** Compiling the compiler *to*
  ESP32 and cross-compiling *from* ESP32 would be an utterly cool demo, but
  device RAM (a few hundred KB) won't hold the compiler's working set and the
  practical value is ~nil. Parked as a "maybe one day" curiosity, not on any
  roadmap. The fixedpoint gate stays on the Linux cross targets (i386 / ARM32 /
  AArch64).

## Log

- 2026-06-13 — stage-1 emit is now green for x86-64, i386, AArch64, and ARM32,
  but the full chain is not. Opened per-platform child tickets for i386,
  AArch64, and ARM32 after direct probes showed i386/ARM32 segfaulting and
  AArch64 failing with `Pascal define storage overflow`.
