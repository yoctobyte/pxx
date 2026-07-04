# Self-host guard: reject IR_UNSUPPORTED at compile time (fail loud, not miscompile)

- **Type:** feature (compiler — self-host safety) — Track A
- **Status:** backlog — **gated on Track R coordination** (see risk)
- **Opened:** 2026-07-04 (from root-causing bug-selfhost-multifn-ifelse-miscompile)

## Motivation

`IR_UNSUPPORTED` = "a frontend could not lower this AST node" (the `else`
fallbacks in `IRLowerAST`/`IRLowerAddress`, ir.inc ~965 + ~5107). When such a
node reaches codegen:
- if it is EMITTED (statement root / evaluated operand), IREmitNode's catch-all
  `else` already hard-errors ("Unsupported linear node") — good.
- if it is UNREFERENCED (dead value node), it is never emitted, so no error —
  BUT its presence can still perturb label positioning, and under self-host it
  did: it caused the silent `else if` miscompile (FPC-built correct, PXX-built
  wrong) that cost a full debugging session
  ([[bug-selfhost-multifn-ifelse-miscompile]]). A dead IR_UNSUPPORTED node means
  the program is already broken; it should FAIL LOUD, not compile.

## Proposed fix

`IRVerify` (runs per body after lowering, before codegen) errors on ANY
`IR_UNSUPPORTED` node, referenced or not, with an actionable message naming the
AST kind. Turns "frontend gap → silent miscompile" into "frontend gap →
immediate compile error at the exact site". Would have caught the Rust else-if
bug the instant it was generated.

## Measured (2026-07-04)

`IR_UNSUPPORTED` generation count = **0** on: the compiler self-compile, and a
C/Pascal/Nil-Python sample (hello.c, cexpr_b.c, cstmt_c.c, records.pas,
procs.pas, bootstrap_features.pas, test_dynarray_torture.pas,
test_nil_python_core.npy). So the mature frontends never trip it — safe for
them.

## Why gated (the risk)

The **Rust frontend (Track R) is actively in development and INCOMPLETE** — it
legitimately emits `IR_UNSUPPORTED` for constructs it does not yet lower, some
of which may currently "compile" with a dead/benign node. A hard `IRVerify`
error would break those Rust programs/tests and block Track R's in-flight work
(cross-track hazard, against the parallel-tracks rule). Do NOT land until:
- coordinated with Track R (their frontend no longer emits `IR_UNSUPPORTED` for
  anything in their test suite), OR
- landed as an opt-in flag (`--strict-ir` / `--warn-unsupported`) first, off by
  default, so Track R can adopt it when ready, then flipped to default once the
  full `make test` (all frontends) is measured at 0.

## Acceptance

- Full `make test` (ALL frontends) measured at 0 `IR_UNSUPPORTED`, then
  `IRVerify` hard-errors on it; `-O0` self-host byte-identical; regression test
  = a program with an unsupported construct fails loudly with the AST-kind
  message instead of silently miscompiling.
