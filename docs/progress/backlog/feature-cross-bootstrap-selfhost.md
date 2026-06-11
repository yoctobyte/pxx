# Cross self-host bootstrap (compiler.pas → byte-identical under QEMU)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-cross-exceptions, feature-cross-float-variant, feature-cross-param-abi, feature-cross-codegen-gaps
- **Unblocks:** —
- **Opened:** 2026-06-11 (user request)

## Goal

The "fun test": cross-compile `compiler.pas` to a non-native target, run the
resulting binary under QEMU to compile `compiler.pas` again for the same target,
and verify the two outputs are **byte-identical** — the triple-stage bootstrap
correctness proof, applied across architectures. The earlier
`feature-cross-bootstrap` (now in `done/`) delivered the runtime *infrastructure*
analysis; this ticket is the end-to-end gate.

## Current state (2026-06-11)

Small test programs cross-compile and are byte/output-matched to x86-64 on all
four targets (managed runtime — heap, strings, records, dynarrays — complete).
But cross-compiling `compiler.pas` itself fails immediately:

```
i386    : only ordinal/pointer parameters supported yet   (feature-cross-param-abi)
arm32   : builtin/exception runtime not yet supported     (feature-cross-exceptions)
aarch64 : load through pointer of this type not yet supported
```

`compiler.pas` uses `try/except` (exceptions), `uses SysUtils` (full builtin →
floats/variants), and richer parameter signatures — none yet on cross targets.

## Plan (staged)

1. feature-cross-exceptions — the dominant blocker (`try/except` everywhere in
   the compiler).
2. feature-cross-float-variant — so the full `builtin` unit compiles.
3. feature-cross-param-abi — record-by-value / float / open-array / >N args.
4. feature-cross-codegen-gaps — managed-local release (no leaks during a long
   compile), class instantiation, COW, remaining edge cases.

When those land, this ticket adds the actual gate.

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
