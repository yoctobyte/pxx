---
prio: 60  # auto
---

# Self-host guard: reject IR_UNSUPPORTED at compile time (fail loud, not miscompile)

- **Type:** feature (compiler — self-host safety) — Track A
- **Status:** done
  remaining = flip to default once Track R coordinated (still gated, see risk)
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

## Log
- 2026-07-04 — **Track A: opt-in flag `--strict-ir` landed** (the sanctioned
  "off by default first" path from the risk section). `StrictIR` global
  (`defs.inc`), parsed in `compiler.pas`, checked in `IRVerify`'s
  `IR_UNSUPPORTED` case (`ir.inc`): when on, hard-errors with the offending AST
  kind number (`IR_UNSUPPORTED: frontend could not lower AST node (kind N)`).
  `IRVerify` walks ALL `IRCount` nodes, so it catches dead/unreferenced
  `IR_UNSUPPORTED` too (the exact self-host-miscompile hazard). Default OFF →
  Track R's in-development Rust frontend (which may still emit `IR_UNSUPPORTED`
  for unlowered constructs) is not broken; `-O0` self-host stays byte-identical
  (build vs verify `cmp` clean). Verified `--strict-ir` compiles cleanly (0
  errors = 0 `IR_UNSUPPORTED`) on: `compiler/compiler.pas` (self), Pascal
  (bootstrap_features, arrays, dynarray_torture), C (caddr_array_field,
  caddr_func), Nil-Python (test_nilpy_bool) — confirms mature frontends never
  trip it. `make test` green.
  **Remaining to close:** flip to default (make `IRVerify` always reject
  `IR_UNSUPPORTED`) once Track R's frontend is measured at 0 across the full
  suite — a cross-track coordination step, not a code gap here. No source-level
  negative regression test exists because no mature-frontend construct produces
  `IR_UNSUPPORTED` (that 0 is itself the acceptance evidence); the historical
  trigger (Rust `else if`, bug-selfhost-multifn-ifelse-miscompile) is already
  fixed on Track R.
- 2026-07-11 — resolved, commit 2b6c621f.
