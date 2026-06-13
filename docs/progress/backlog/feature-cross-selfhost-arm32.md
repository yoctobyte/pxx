# Cross self-host: ARM32 generated compiler runs under QEMU

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-cross-managed-string-cow
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split from cross self-host rollup)

## Goal

Make the ARM32 compiler binary emitted by native `pascal26` work as a compiler
under QEMU. This is separate from the already-green stage-1 ARM32 emit and
target test suite.

## Current failure

Repro from repo root:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=arm32 \
  compiler/compiler.pas /tmp/compiler_arm32
./compiler/pascal26 -dPXX_MANAGED_STRING --target=x86_64 \
  test/hello.pas /tmp/hello_native_to_x64
tools/run_target.sh arm32 /tmp/compiler_arm32 -dPXX_MANAGED_STRING \
  --target=x86_64 test/hello.pas /tmp/hello_arm32_to_x64
```

Observed 2026-06-13: `tools/run_target.sh arm32 /tmp/compiler_arm32 ...`
segfaults under QEMU (`rc=139`) before producing a comparable output.

## Acceptance

- The ARM32-generated compiler compiles `test/hello.pas` to x86-64 under QEMU.
- The emitted x86-64 `hello` is byte-identical to native `pascal26` output for
  the same command.
- The emitted x86-64 `hello` runs and prints `Hello, World!`.
- Then extend to `compiler/compiler.pas -> arm32` self-fixedpoint and compare
  byte-identical outputs.

## Log

- 2026-06-13 — opened with current failure (`rc=139` segfault).
