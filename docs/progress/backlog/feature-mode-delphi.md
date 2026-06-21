# `{$mode delphi}` support — incl. the @-optional proc-pointer disambiguation

- **Type:** feature (dialect mode + FPC/Delphi-source compat)
- **Status:** backlog
- **Owner:** — (Track A)
- **Opened:** 2026-06-21
- **Relation:** the `@`-rule half of [[bug-bare-function-name-call-vs-resultvar]];
  unblocks much library source. Companion to [[feature-mimic-fpc]],
  [[feature-networking]] (Synapse compiles via its `{$mode delphi}` path),
  [[goal-compile-fpc-compiler]].

## Why

A large amount of real Pascal library/source is written for `{$mode delphi}`
(Synapse, many Delphi-portable units). PXX currently largely **swallows** the
`{$mode}` directive (only `PasObjFpcModeOption` peeks for objfpc). To compile that
source we need a real Delphi mode, and the headline behavioural delta is the
**`@`-optional procedural value** — exactly the kind of mode-specific detail that
silently mis-compiles otherwise.

## The verified delta (the headline)

Assigning/passing a function as a procedural value (tested 2026-06-21):

- fpc/objfpc: `p := @F` required; `p := F` (no `@`) is a CALL → type error.
- **delphi: `p := F` (no `@`) works** — auto-takes the function's address.

So in Delphi mode a bare function name in a **procedural-target context** means
"the pointer", not "call it".

## NOT a rabbit hole — deterministic call-first precedence (FPC-verified 2026-06-21)

`p := F` is NOT ambiguous in FPC; it is resolved by a fixed precedence, not by
guessing intention:

1. **Try the call.** If `F`'s *result* type is assignment-compatible with the
   target → **call wins** — in ALL modes, even when `@F` would also fit. Tested:
   `function F: Pointer; var q: Pointer; q := F;` calls F (no warning) in default,
   objfpc, and delphi, although `@F` is equally Pointer-compatible. Call has
   priority, period.
2. **`@F` is a pure Delphi-mode fallback,** used only when the call result does
   NOT fit the target AND the target is procedural AND `@F` fits. Tested:
   `function F: Pointer; var p: TFn; p := F;` → default/objfpc ERROR (Pointer ≠
   TFn); `-Mdelphi` compiles (takes `@F`). No warnings either way.

So the implementer does **not** detect intention and does **not** need expected-
type propagation through `ParseExpr`. The rule is: at the few **bind sites** where
the target type is known, the EXISTING type check already prefers the call; just
add, *for delphi mode only*, a fallback when that type check fails on a procedural
target.

**Bind sites** (where the target type is in hand): assignment RHS to a proc-typed
lvalue (`p := F`), a call arg bound to a proc-typed parameter (`g(F)`), proc-value
comparison (`if p = F`), proc-typed record/array fields. At each: *if the call
interpretation type-checks → call (all modes); else if delphi AND target is
procedural AND the operand is a bare function-name (no required args, not already
`@`'d) AND `@F` fits → take the address.* Method pointers (`@obj.M`) carry Self —
2-word `TMethod` shape.

## Other Delphi-mode deltas (scope, lower priority than @-relax)

- `{$H+}` (AnsiString) is the default — PXX already defaults managed strings, so
  largely a no-op for us; confirm `string` semantics line up.
- `Result` keyword always available (already true).
- Class/`with`/property nuances, operator overloading spelling, integer
  division/`@@` — add only on concrete demand from real source, not speculatively.
- Pin down which deltas matter by actually compiling a `{$mode delphi}` unit
  (Synapse is the forcing function) and fixing what breaks.

## Acceptance

- `{$mode delphi}` is parsed and honoured (no longer swallowed); a non-Delphi
  unit is unaffected (mode is per-file/section).
- `test/test_mode_delphi_procptr.pas`: in `{$mode delphi}`, `p := F` and `g(F)`
  (proc-typed target) take the address and call through it correctly; the same
  source WITHOUT `{$mode delphi}` still requires `@` (no regression to default
  semantics). Method-pointer `p := obj.M` covered.
- `make test` green; self-host byte-identical (parser change = 1-gen reseed,
  [[feedback_codegen_reseed_not_nondeterminism]]); cross + ESP still build.

## Dependencies / ordering

- Best done after [[bug-bare-function-name-call-vs-resultvar]] lands a clean
  bare-name model (call vs result-var vs `@`-pointer), since Delphi mode is a
  variation on that model, not a separate one.
- `@`/proc-pointer plumbing already exists ([[project_procedural_types_arc]]);
  this adds the mode-gated bind-site disambiguation, not a new pointer ABI.

## Log
- 2026-06-21 — filed (Track A). Surfaced from the bare-function-name `@` rule;
  user flagged Delphi mode as worth implementing for library compat and noted the
  intention/type-detection rabbit hole — bounded here to bind-site special-casing.
