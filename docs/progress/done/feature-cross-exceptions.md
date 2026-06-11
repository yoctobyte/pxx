# Exception runtime on cross targets (i386 / ARM32 / AArch64)

- **Type:** feature
- **Status:** done
- **Owner:** Antigravity <antigravity@google.com>
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-11 (user request)

## Motivation

`try/except`, `try/finally`, and `raise` are unsupported on every cross target —
`EnableExceptionRuntime` and the exception IR ops (`IR_EXC_ENTER/LEAVE/MATCH/
STORE/CLEAR`, `IR_RAISE`) are x86-64 machine code only. `compiler.pas` itself is
built around `try/except` (the `Error` path), so this is the dominant wall for
the cross self-host (see feature-cross-bootstrap-selfhost). Cross compiling the
compiler currently fails fast: `target arm32: builtin/exception runtime not yet
supported`.

## Scope

- Port the exception runtime to i386, ARM32, AArch64. The frame model
  (`BSS_EXC_TOP`, `EXC_FRAME_SIZE`, setjmp/longjmp-style unwinding) is in
  `exception_emit.inc` / `ir_codegen.inc` as x86-64 byte emission.
- Two routes, mirroring the managed-runtime approach:
  1. Move the unwinder body into a portable Pascal helper in `builtinheap`
     (or a new `builtinexc` unit) so the cross backends only emit thin
     register-setup shims — preferred, matches the layout-RTTI precedent.
  2. Or hand-emit the per-arch unwinder. Heavier, avoid unless the Pascal
     route can't express the stack juggling.
- Wire the exception IR ops in `ir_codegen386.inc`, `ir_codegen_arm32.inc`,
  `ir_codegen_aarch64.inc`.
- Relax the per-target `hasExceptions` guard in `ParseProgram`.

## Acceptance

A program using `try/except`/`raise` compiles and runs on i386, ARM32, AArch64
with output identical to x86-64 (oracle). New `test/test_cross_exception.pas`
joins the cross suites.

## Notes

- The unhandled-exception terminator and the unwind ABI must agree with the
  managed-local release that runs during unwinding (currently leaked on cross
  targets — see feature-cross-codegen-gaps).

## Log

- 2026-06-11 — Completed implementation of exception runtime and branch patchers on all cross-compilation targets, verified via emulator testing suite (commit 53c87bb).
