# Cross self-host: AArch64 generated compiler runs under QEMU

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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

Observed 2026-06-13: the generated AArch64 compiler starts but fails with:

```text
pascal26:0: error: Pascal define storage overflow
```

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
