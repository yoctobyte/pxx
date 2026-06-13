# Cross self-host: AArch64 generated compiler runs under QEMU

- **Type:** feature
- **Status:** backlog
- **Owner:** —
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
