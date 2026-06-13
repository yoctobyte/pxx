# Cross self-host: i386 generated compiler runs under Linux

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split from cross self-host rollup)

## Goal

Make the i386 compiler binary emitted by native `pascal26` work as a compiler.
Tackle this platform independently from AArch64 and ARM32, even if root causes
turn out to overlap.

## Current failure

Repro from repo root:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386 \
  compiler/compiler.pas /tmp/compiler_i386
./compiler/pascal26 -dPXX_MANAGED_STRING --target=x86_64 \
  test/hello.pas /tmp/hello_native_to_x64
tools/run_target.sh i386 /tmp/compiler_i386 -dPXX_MANAGED_STRING \
  --target=x86_64 test/hello.pas /tmp/hello_i386_to_x64
```

Observed 2026-06-13: `tools/run_target.sh i386 /tmp/compiler_i386 ...`
segfaults (`rc=139`) before producing a comparable output.

## Acceptance

- The i386-generated compiler compiles `test/hello.pas` to x86-64 under
  `tools/run_target.sh i386`.
- The emitted x86-64 `hello` is byte-identical to native `pascal26` output for
  the same command.
- The emitted x86-64 `hello` runs and prints `Hello, World!`.
- Then extend to `compiler/compiler.pas -> i386` self-fixedpoint and compare
  byte-identical outputs.

## Log

- 2026-06-13 — opened with current failure (`rc=139` segfault).
