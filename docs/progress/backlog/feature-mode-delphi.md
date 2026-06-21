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

## The rabbit hole (intention = target type)

`p := F` is genuinely ambiguous and is resolved by the **target type**:

- target is a procedural type  → take `@F` (address)
- target is `F`'s result type   → call `F`

PXX builds expression values **bottom-up** with no expected-type context, so a
naive `ParseExpr` can't tell which is meant at `F`. Do NOT try to thread an
expected type through all of `ParseExpr` (that is the deep rabbit hole).

**Bounded approach:** the @-relax only matters in a finite set of **binding
contexts** where the target type is already known:

1. assignment RHS to a proc-typed lvalue (`p := F`),
2. a call argument bound to a proc-typed parameter (`g(F)`),
3. comparison of a proc value (`if p = F`, `if @p = @F`), and proc-typed
   record/array fields.

At each of those bind points, special-case: *if the RHS/arg is a bare
function-name reference (a routine with no required args, not already called/`@`'d)
AND the target/param type is procedural → rewrite it to take the address instead
of emitting a call.* Method pointers (`@obj.M`) carry Self — handle the 2-word
`TMethod` shape. No global type propagation; just the bind-site check.

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
