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
- 2026-06-22 — **slice 1 landed.** `{$mode delphi}` parsed -> `DelphiMode` flag
  (lexer directive; objfpc/fpc/tp/macpas inert). Two deltas done:
  - **@-optional procedural value** at the proc-typed *assignment* bind site
    (`p := Fn` takes `@Fn`; default still needs `@`).
  - **Bare own-name reading**: in delphi a bare own-name is never the result var
    (paramless -> recursive call, with-params -> function value); objfpc/default
    keep the result-var flip (the second delta the user flagged). `Result` reads
    the result in delphi.
  Compiler is objfpc so self-host byte-identical; `make test` + cross-bootstrap
  green; `test/test_mode_delphi.pas` matches FPC `-Mdelphi`.
  **REMAINING slices:** @-relax at the other bind sites (call-arg `g(F)`, proc-
  value comparison `if p = F`, proc-typed record/array fields); method pointers
  (`p := obj.M`, 2-word `TMethod`); per-unit/section mode reset (currently a
  whole-compile flag — fine single-unit, revisit for multi-unit so a non-delphi
  unit can't inherit). Keep in backlog for those.
- 2026-06-22 — found a PRE-EXISTING (v37) bug while testing: `@procedure`-TYPED
  proc values (`type TP = procedure(...); var p: TP; p := @Proc`) error
  `unexpected token`; `@function`-typed work. Filed
  [[bug-procedure-typed-procvalue]] (independent of mode-delphi).
- 2026-06-22 — **call-arg @-relax slice DONE**. Passing a bare routine name to a
  proc-typed parameter now takes its address (no `@`), matching FPC `-Mdelphi`.
  Two mechanisms (parser.inc):
  - `TryDelphiBareProcArg` (parse-time peek in both arg loops): a bare ident
    naming a routine that CANNOT be a value-producing call here — a procedure, or
    a function taking parameters — and standing alone as the whole arg (next tok
    `,`/`)`) → `AN_PROCADDR`. Paramless functions are deliberately excluded here.
  - `MatchCallDelphiProcAddr` (overload-resolution wrapper at both call sites):
    a bare paramless-function arg parses call-first (`AN_CALL`); the match is
    retried with such args retyped `tyPointer` and rewritten to a fresh
    `AN_PROCADDR` **iff** the matched formal is procedural (`SymProcSig>=0`).
    Needed because PXX compat-matches a numeric call result to a proc-typed
    (pointer) param, so call-first alone would wrongly pass the result; the
    procedural-formal test forces the address (FPC precedence). Speculative
    probe is silenced via the new `MatchQuiet` flag (guards MatchProcCall diag).
  Test `test/test_mode_delphi_callarg.pas` (in `make test`), FPC `-Mdelphi`
  oracle-matched (42/20/14). make test + cross-bootstrap byte-identical.
- 2026-06-22 — **method-pointer @-relax slice DONE**. `p := obj.M` (no `@`) binds
  a method pointer == `p := @obj.M`, when `p` is a `procedure(...) of object`
  lvalue. Small slice — PXX already had the method-pointer infra (AN_METHODREF
  `@obj.M`→TMethod, EnsureMethodPtrRec, `of object` types, target-aware TMethod
  Data offset in AN_ASSIGN). Added a branch in the assignment-site relax
  (parser.inc, statement assign): in delphi mode, target proc-typed AND
  `TypeKind = tyRecord` (a method-pointer var; a plain proc-ptr var is tyPointer —
  this is what distinguishes the two) AND RHS is `obj.M` (`var.method`, no
  following `(`) → emit the same AN_METHODREF the `@obj.M` path emits. Reuses the
  existing AN_ASSIGN TMethod-target lowering, so cross targets (Data@4 on
  i386/arm32, @8 on 64-bit) come for free. Test
  `test/test_mode_delphi_methptr.pas` (in `make test`), FPC `-Mdelphi`
  oracle-matched (total=12 / kicked=1; covers with-params + paramless method).
  make test + cross-bootstrap byte-identical.
  **REMAINING:** proc-value comparison `if p = F`; proc-typed record/array
  fields; method pointers at the CALL-ARG bind site (`g(obj.M)` — only the
  assignment site is done); per-unit mode reset.
